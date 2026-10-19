import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/task_repository.dart';
import 'data/backup_repository.dart';
import 'domain/models.dart';
import 'features/settings/settings_controller.dart';
import 'features/tasks/task_controller.dart';
import 'platform/feedback_service.dart';
import 'platform/reminder_service.dart';
import 'platform/secure_connection_store.dart';
import 'sync/connection_service.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_transport.dart';

class DayHost extends StatefulWidget {
  final AppDatabase rootDatabase, taskDatabase;
  final Directory directory;
  final SettingsController settings;
  final ConnectionSecret? secret;
  final String deviceId;
  final NotificationPort? notificationPort;
  const DayHost({
    super.key,
    required this.rootDatabase,
    required this.taskDatabase,
    required this.directory,
    required this.settings,
    required this.deviceId,
    this.notificationPort,
    this.secret,
  });
  @override
  State<DayHost> createState() => _DayHostState();
}

class _DayHostState extends State<DayHost> with WidgetsBindingObserver {
  late AppDatabase database;
  late SqliteTaskRepository repository;
  late TaskController controller;
  late BackupRepository backups;
  late ConnectionService connections;
  SyncEngine? engine;
  ConnectionSecret? secret;
  final audio = AssetCompletionAudio();
  late final NotificationPort notifications;
  late ReminderService reminders;
  final navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<void>? edits;
  StreamSubscription<List<TaskItem>>? taskChanges;
  StreamSubscription<String>? taps;
  static const debugLoopback =
      kDebugMode && bool.fromEnvironment('DAY_DEBUG_HTTP');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    database = widget.taskDatabase;
    secret = widget.secret;
    notifications = widget.notificationPort ?? NativeNotificationPort();
    reminders = ReminderService(widget.rootDatabase, notifications);
    taps = reminders.onNotificationTaskId.listen((id) {
      controller.requestOpen(id);
    });
    configure();
  }

  void configure() {
    repository = SqliteTaskRepository(database);
    backups = BackupRepository(
      repository,
      directory: Directory('${widget.directory.path}/backups'),
    );
    connections = ConnectionService(
      rootDatabase: widget.rootDatabase,
      repository: repository,
      backups: backups,
      directory: widget.directory,
      secrets: const OsSecureConnectionStore(),
      beforeConnect: stopSync,
      connectFailed: () async {
        if (mounted && secret != null) {
          startSync();
          setState(() {});
        }
      },
      beforeDisconnect: disconnect,
      transportFactory: (uri, key) => HttpSyncTransport(
        uri,
        () async => key,
        allowDebugLoopback: debugLoopback,
      ),
    );
    controller = TaskController(
      repository,
      feedback: LocalCompletionFeedback(
        settings: widget.settings,
        audio: audio,
        policy: NativeSoundPolicy(),
        haptic: Platform.isAndroid ? HapticFeedback.lightImpact : null,
      ),
      today: LocalDate.today,
    );
    final configuredController = controller;
    widget.rootDatabase.setting('reminderFailures').then((value) {
      if (mounted &&
          identical(controller, configuredController) &&
          value != null) {
        controller.setReminderFailures(
          Map<String, String>.from(jsonDecode(value) as Map),
        );
      }
    });
    if (secret != null) {
      startSync();
    }
    edits = database.localUpdates.stream.listen((_) => engine?.localChanged());
    taskChanges = repository
        .watchTasks(
          TaskQuery(
            view: TaskView.all,
            today: LocalDate.today(),
            includeCompleted: true,
          ),
        )
        .listen((tasks) async {
          try {
            final report = await reminders.reconcile(tasks);
            if (mounted && identical(controller, configuredController)) {
              controller.setReminderFailures(report.failures);
            }
          } catch (_) {
            if (mounted && identical(controller, configuredController)) {
              controller.setReminderFailures({
                '*': 'Не удалось обновить системные напоминания. Проверьте настройки уведомлений.',
              });
            }
          }
        });
  }

  void startSync() {
    final profile = secret;
    if (profile == null) return;
    engine = SyncEngine(
      repository,
      HttpSyncTransport(
        profile.endpoint,
        () async => profile.token,
        allowDebugLoopback: debugLoopback,
      ),
      deviceId: widget.deviceId,
      scheduler: TimerScheduler(),
    );
    engine!.setForeground(true);
    engine!.addListener(showSyncConflict);
  }

  Future<void> stopSync() async {
    final previous = engine;
    engine = null;
    if (previous != null) {
      await previous.stop();
      previous.dispose();
    }
  }

  Future<void> activateWorkspace(ConnectionResult result) async {
    await edits?.cancel();
    await taskChanges?.cancel();
    await stopSync();
    await reminders.drain();
    controller.dispose();
    final previous = database;
    database = result.database;
    secret = result.secret;
    configure();
    setState(() {});
    if (previous != widget.rootDatabase) await previous.close();
  }

  String? _shownConflict;
  Future<void> showSyncConflict() async {
    if (engine == null || engine?.state == SyncState.syncing) return;
    final conflict = await repository.latestConflict();
    if (!mounted ||
        conflict == null ||
        conflict['operationId'] == _shownConflict) {
      return;
    }
    _shownConflict = conflict['operationId'] as String;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          conflict['code'] == 'successor_absent'
              ? 'Повтор отменён на другом устройстве. Ваши правки сохранены отдельными задачами.'
              : 'Отмена не выполнена: следующая задача уже изменена.',
        ),
        action: conflict['successorId'] == null
            ? null
            : SnackBarAction(
                label: 'Открыть',
                onPressed: () =>
                    controller.requestOpen(conflict['successorId'] as String),
              ),
      ),
    );
  }

  Future<void> disconnect() async {
    await stopSync();
    secret = null;
    setState(() {});
  }

  Future<bool> requestReminder() async {
    final permission = await reminders.requestPermission();
    if (permission == ReminderPermission.granted) return true;
    if (!mounted) return false;
    final text = switch (permission) {
      ReminderPermission.unsupportedPackage =>
        'Для системных напоминаний установите MSIX-версию приложения.',
      ReminderPermission.needsExactAlarmPermission =>
        'Разрешите точные напоминания в настройках Android.',
      ReminderPermission.unknown => 'Не удалось проверить доступность системных уведомлений. Проверьте настройки приложения в Windows.',
      _ => 'Разрешите уведомления для приложения в настройках системы.',
    };
    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return false;
    await showDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Напоминания'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    engine?.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      controller.setQuery(
        TaskQuery(
          view: controller.query.view,
          listId: controller.query.listId,
          today: LocalDate.today(),
          search: controller.query.search,
          includeCompleted: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => DayApp(
    controller: controller,
    settings: widget.settings,
    backups: backups,
    engine: engine,
    connections: connections,
    onConnected: activateWorkspace,
    onDisconnected: disconnect,
    onRequestReminder: requestReminder,
    navigatorKey: navigatorKey,
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    edits?.cancel();
    taskChanges?.cancel();
    taps?.cancel();
    final closingEngine = engine;
    engine?.dispose();
    controller.dispose();
    audio.close();
    if (notifications is NativeNotificationPort) {
      (notifications as NativeNotificationPort).close();
    }
    unawaited(() async {
      await closingEngine?.stop();
      await reminders.drain();
      await database.close();
      if (database != widget.rootDatabase) await widget.rootDatabase.close();
    }());
    widget.settings.dispose();
    super.dispose();
  }
}
