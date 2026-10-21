import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/app_database.dart';
import '../domain/models.dart';

enum ReminderPermission {
  granted,
  denied,
  needsExactAlarmPermission,
  unsupportedPackage,
  unknown,
}

class ReminderReport {
  final List<String> scheduled, cancelled;
  final Map<String, String> failures;
  const ReminderReport(this.scheduled, this.cancelled, this.failures);
}

abstract interface class NotificationPort {
  Future<ReminderPermission> currentPermission();
  Future<ReminderPermission> requestPermission();
  Future<void> schedule(int id, TaskItem task);
  Future<void> cancel(int id);
}

class NativeNotificationPort implements NotificationPort {
  final plugin = FlutterLocalNotificationsPlugin();
  final taps = StreamController<String>.broadcast();
  bool initialized = false;
  Future<bool> _supported() async {
    if (!Platform.isWindows) return Platform.isAndroid || Platform.isMacOS;
    try {
      return await const MethodChannel('day/platform')
              .invokeMethod<bool>('hasPackageIdentity') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> initialize() async {
    if (initialized || !await _supported()) return;
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Ask on the first reminder, not at launch.
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        windows: WindowsInitializationSettings(
          appName: 'Just',
          appUserModelId: 'ClaudeWork.Day',
          guid: 'b28de281-963c-405d-9724-4c0223ac4fd1',
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) taps.add(response.payload!);
      },
    );
    initialized = true;
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload != null) {
      scheduleMicrotask(() => taps.add(launch!.notificationResponse!.payload!));
    }
  }

  @override
  Future<ReminderPermission> currentPermission() async {
    if (!await _supported()) return ReminderPermission.unsupportedPackage;
    if (Platform.isWindows) {
      try {
        final setting = await const MethodChannel('day/platform')
            .invokeMethod<int>('notificationSetting');
        if (setting == null || setting < 0) return ReminderPermission.unknown;
        if (setting != 0) return ReminderPermission.denied;
      } catch (_) {
        return ReminderPermission.unknown;
      }
    }
    await initialize();
    if (Platform.isMacOS) {
      final options = await plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return options?.isEnabled == true
          ? ReminderPermission.granted
          : ReminderPermission.denied;
    }
    if (Platform.isAndroid) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await android?.areNotificationsEnabled() != true) {
        return ReminderPermission.denied;
      }
      if (await android?.canScheduleExactNotifications() != true) {
        return ReminderPermission.needsExactAlarmPermission;
      }
    }
    return ReminderPermission.granted;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    if (!await _supported()) return ReminderPermission.unsupportedPackage;
    await initialize();
    if (Platform.isMacOS) {
      final mac = plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      final ok = await mac?.requestPermissions(alert: true, sound: true);
      return ok == true
          ? ReminderPermission.granted
          : ReminderPermission.denied;
    }
    if (Platform.isAndroid) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await android?.requestNotificationsPermission() != true) {
        return ReminderPermission.denied;
      }
      if (await android?.canScheduleExactNotifications() != true) {
        await android?.requestExactAlarmsPermission();
      }
    }
    return currentPermission();
  }

  @override
  Future<void> schedule(int id, TaskItem task) => plugin.zonedSchedule(
    id: id,
    title: task.title,
    scheduledDate: tz.TZDateTime.from(task.reminderAtUtc!, tz.UTC),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'day-reminders',
        'Напоминания',
        channelDescription: 'Напоминания о ваших задачах',
      ),
      windows: WindowsNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: task.id,
  );
  @override
  Future<void> cancel(int id) => plugin.cancel(id: id);
  Future<void> close() => taps.close();
}

class ReminderService {
  final AppDatabase database;
  final NotificationPort notifications;
  final DateTime Function() now;
  Future<void> _tail = Future.value();
  ReminderService(this.database, this.notifications, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  Stream<String> get onNotificationTaskId =>
      notifications is NativeNotificationPort
      ? (notifications as NativeNotificationPort).taps.stream
      : const Stream.empty();
  Future<ReminderPermission> requestPermission() =>
      notifications.requestPermission();
  Future<ReminderReport> reconcile(List<TaskItem> tasks) {
    final result = Completer<ReminderReport>();
    _tail = _tail.catchError((Object _) {}).then((_) async {
      try {
        result.complete(await _reconcile(tasks));
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    return result.future;
  }

  Future<void> drain() => _tail;
  Future<int> _id(String taskId) => database.transaction(() async {
    final prior = (await database.rows(
      'SELECT notificationId FROM notificationIds WHERE taskId=?',
      [taskId],
    )).firstOrNull;
    if (prior != null) return prior['notificationId'] as int;
    final max =
        (await database.rows(
              'SELECT COALESCE(MAX(notificationId),0) AS n FROM notificationIds',
            )).single['n']
            as int;
    if (max >= 2147483647) throw StateError('Notification capacity reached');
    await database.run('INSERT INTO notificationIds VALUES (?,?)', [
      taskId,
      max + 1,
    ]);
    return max + 1;
  });
  Future<ReminderReport> _reconcile(List<TaskItem> tasks) async {
    final scheduled = <String>[],
        cancelled = <String>[],
        failures = <String, String>{};
    final wanted = {
      for (final t in tasks)
        if (!t.completed &&
            !t.deleted &&
            t.reminderAtUtc != null &&
            t.reminderAtUtc!.isAfter(now().toUtc()))
          t.id: t,
    };
    final old = jsonDecode(
      await database.setting('notificationSchedules') ?? '{}',
    ) as Map<String, dynamic>;
    final permission = await notifications.currentPermission();
    final next = Map<String, dynamic>.of(old);
    for (final id in old.keys) {
      final task = wanted[id];
      final fingerprint = task == null
          ? null
          : jsonEncode([
              task.title,
              task.reminderAtUtc!.toUtc().toIso8601String(),
            ]);
      if (permission != ReminderPermission.granted || fingerprint != old[id]) {
        try {
          await notifications.cancel(await _id(id));
          cancelled.add(id);
          next.remove(id);
        } catch (_) {
          failures[id] = 'Не удалось отменить прежнее напоминание';
        }
      }
    }
    for (final task in wanted.values) {
      final fingerprint = jsonEncode([
        task.title,
        task.reminderAtUtc!.toUtc().toIso8601String(),
      ]);
      if (permission != ReminderPermission.granted) {
        failures[task.id] = switch (permission) {
          ReminderPermission.unsupportedPackage =>
            'Для напоминаний установите MSIX-версию приложения.',
          ReminderPermission.denied =>
            'Уведомления выключены в настройках системы.',
          ReminderPermission.needsExactAlarmPermission =>
            'Разрешите точные напоминания в настройках Android.',
          _ => 'Не удалось проверить доступность системных уведомлений.',
        };
        continue;
      }
      if (next[task.id] == fingerprint || failures.containsKey(task.id)) {
        continue;
      }
      try {
        await notifications.schedule(await _id(task.id), task);
        scheduled.add(task.id);
        next[task.id] = fingerprint;
      } catch (_) {
        failures[task.id] = 'Не удалось поставить напоминание';
      }
    }
    await database.setSetting('notificationSchedules', jsonEncode(next));
    await database.setSetting('reminderFailures', jsonEncode(failures));
    return ReminderReport(scheduled, cancelled, failures);
  }
}
