import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/platform/reminder_service.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/domain/models.dart';

class Notifications implements NotificationPort {
  ReminderPermission permission = ReminderPermission.granted;
  final times = <int, DateTime>{};
  final cancelled = <int>[];
  int calls = 0;
  @override
  Future<ReminderPermission> currentPermission() async => permission;
  @override
  Future<ReminderPermission> requestPermission() async => permission;
  @override
  Future<void> schedule(int id, TaskItem task) async {
    calls++;
    times[id] = task.reminderAtUtc!;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    times.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'actual reminder failures persist for UI after a remote task update',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local'),
          port = Notifications()..permission = ReminderPermission.denied;
      final service = ReminderService(
        db,
        port,
        now: () => DateTime.utc(2026, 10, 19),
      );
      try {
        await service.reconcile([
          TaskItem.fromJson({
            'id': 'remote',
            'title': 'С другого устройства',
            'reminderAtUtc': '2026-10-20T10:00:00Z',
          }),
        ]);
        final saved = await db.setting('reminderFailures');
        expect(saved, isNotNull);
        expect((jsonDecode(saved!) as Map).containsKey('remote'), true);
      } finally {
        await db.close();
      }
    },
  );
  test(
    'Windows package identity alone does not mean notifications are enabled',
    () async {
      if (!Platform.isWindows) return;
      const channel = MethodChannel('day/platform');
      var setting = 1;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async =>
                call.method == 'hasPackageIdentity' ? true : setting,
          );
      try {
        expect(
          await NativeNotificationPort().currentPermission(),
          ReminderPermission.denied,
        );
        setting = -1;
        expect(
          await NativeNotificationPort().currentPermission(),
          ReminderPermission.unknown,
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );
  test('stable notification ids cancel changed/deleted reminders and denied never schedules', () async {
    final db = AppDatabase.memory(workspaceId: 'local');
    final port = Notifications();
    final service = ReminderService(
      db,
      port,
      now: () => DateTime.utc(2026, 10, 19),
    );
    TaskItem task(String id, String time) => TaskItem.fromJson({
      'id': id,
      'title': 'Напоминание',
      'reminderAtUtc': time,
    });
    try {
      final a = task('a', '2026-10-20T10:00:00Z'),
          b = task('b', '2026-10-20T11:00:00Z');
      final first = await service.reconcile([a, b]);
      expect(first.scheduled.length, 2);
      final ids = port.times.keys.toList();
      expect(ids.toSet().length, 2);
      await service.reconcile([a, b]);
      expect(port.calls, 2);
      final report = await service.reconcile([
        task('a', '2026-10-20T12:00:00Z'),
      ]);
      expect(report.cancelled.toSet(), {'a', 'b'});
      expect(port.times.length, 1);
      expect(port.times.keys.single, ids.first);
      expect(port.times.values.single, DateTime.utc(2026, 10, 20, 12));
      port.permission = ReminderPermission.denied;
      final denied = await service.reconcile([a, b]);
      expect(denied.scheduled, isEmpty);
      expect(denied.failures.length, 2);
    } finally {
      await db.close();
    }
  });
}
