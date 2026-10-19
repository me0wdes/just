import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';
import 'package:day_planner/app.dart';
import 'package:day_planner/app_host.dart';
import 'package:day_planner/main.dart' as bootstrap;
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/data/backup_repository.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/features/settings/settings_controller.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/platform/feedback_service.dart';
import 'package:day_planner/platform/secure_connection_store.dart';
import 'package:day_planner/platform/reminder_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:day_planner/features/tasks/greeting_header.dart';

class FailingNotifications implements NotificationPort {
  @override
  Future<ReminderPermission> currentPermission() async =>
      ReminderPermission.granted;
  @override
  Future<ReminderPermission> requestPermission() async =>
      ReminderPermission.granted;
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> schedule(int id, TaskItem task) async =>
      throw StateError('OS scheduling unavailable');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: true);
  testWidgets('native FLOW shader moves and stops when motion is disabled', (
    tester,
  ) async {
    await tester.runAsync(RoseGoldField.load);
    final key = GlobalKey();
    Widget scene({bool reduced = false, bool enabled = true}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: enabled,
          child: Center(
            child: SizedBox(
              width: 600,
              height: 160,
              child: RepaintBoundary(key: key, child: const RoseGoldField()),
            ),
          ),
        ),
      ),
    );
    Future<List<int>> pixels() async => (await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final result = bytes!.buffer.asUint8List().toList();
      image.dispose();
      return result;
    }))!;
    await tester.pumpWidget(scene());
    await tester.pump(const Duration(milliseconds: 100));
    final first = await pixels();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(await pixels(), isNot(orderedEquals(first)));
    await tester.pumpWidget(scene(enabled: false));
    final paused = await pixels();
    await tester.pump(const Duration(milliseconds: 500));
    expect(await pixels(), orderedEquals(paused));
    await tester.pumpWidget(scene(reduced: true));
    final still = await pixels();
    await tester.pump(const Duration(milliseconds: 500));
    expect(await pixels(), orderedEquals(still));
    expect(binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('production host exposes actual reminder scheduling failures', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('day-reminder-host-');
    final db = AppDatabase.open(
          File('${dir.path}/tasks.sqlite'),
          workspaceId: 'local',
        ),
        repo = SqliteTaskRepository(db);
    final id = const Uuid().v4();
    await repo.execute(
      TaskCommand.createTask(
        id: id,
        title: 'Проверка ошибки напоминания',
        listId: inboxId,
        fields: {
          'plannedForDate': LocalDate.today().toString(),
          'reminderAtUtc': '2099-10-20T10:00:00Z',
          'reminderTimezone': 'UTC',
        },
      ),
    );
    final settings = SettingsController(db);
    await settings.load();
    await tester.pumpWidget(
      DayHost(
        rootDatabase: db,
        taskDatabase: db,
        directory: dir,
        settings: settings,
        deviceId: const Uuid().v4(),
        notificationPort: FailingNotifications(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Напоминания: 1'), findsOneWidget);
    await tester.tap(find.text('Напоминания: 1'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось поставить напоминание'), findsOneWidget);
    expect(await db.setting('reminderFailures'), contains(id));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        try {
          await dir.delete(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  });
  testWidgets('native credential vault and bundled feedback asset work', (
    tester,
  ) async {
    const store = OsSecureConnectionStore();
    final profile = 'smoke-${const Uuid().v4()}';
    final secret = ConnectionSecret(
      endpoint: Uri.parse('https://example.invalid/sync'),
      token: 'x' * 43,
      workspaceId: const Uuid().v4(),
    );
    try {
      await store.write(profile, secret);
      expect(
        (await const OsSecureConnectionStore().read(profile))!.token,
        secret.token,
      );
    } finally {
      await store.delete(profile);
    }
    expect(await store.read(profile), isNull);
    final audio = AudioPlayer();
    try {
      await audio.setSource(AssetSource('sounds/complete.wav'));
      expect(
        (await audio.getDuration())!.inMilliseconds,
        inInclusiveRange(170, 190),
      );
    } finally {
      await audio.dispose();
    }
    expect(
      await NativeNotificationPort().currentPermission(),
      ReminderPermission.unsupportedPackage,
    );
  });
  testWidgets(
    'production bootstrap exposes settings and secret field stays hidden',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('day-bootstrap-');
      await bootstrap.main(['--data-directory', dir.path]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('sync-secret')))
            .obscureText,
        true,
      );
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-title-input')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        for (var i = 0; i < 20; i++) {
          try {
            await dir.delete(recursive: true);
            break;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      });
    },
  );
  testWidgets(
    'native Windows task survives database reopen and theme changes',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('day-native-smoke-');
      final file = File('${dir.path}/tasks.sqlite');
      var db = AppDatabase.open(file, workspaceId: 'smoke');
      var repo = SqliteTaskRepository(db);
      var settings = SettingsController(db);
      await settings.load();
      var controller = TaskController(
        repo,
        feedback: const SilentCompletionFeedback(),
        today: LocalDate.today,
      );
      await tester.pumpWidget(
        DayApp(
          controller: controller,
          settings: settings,
          backups: BackupRepository(
            repo,
            directory: Directory('${dir.path}/backups'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('task-title-input')),
        'Нативная проверка ${const Uuid().v4()}',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final task =
          (await repo
                  .watchTasks(
                    TaskQuery(view: TaskView.all, today: LocalDate.today()),
                  )
                  .first)
              .single;
      await tester.tap(find.text(task.title));
      await tester.pumpAndSettle();
      expect(find.text('Детали задачи'), findsOneWidget);
      await controller.patchTask(task.id, {'dueDate': '2026-12-31'});
      await settings.setTheme(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await db.close();
      db = AppDatabase.open(file, workspaceId: 'smoke');
      repo = SqliteTaskRepository(db);
      expect((await repo.readTask(task.id))!.dueDate.toString(), '2026-12-31');
      expect((await repo.readTask(task.id))!.title, task.title);
      await db.close();
      await dir.delete(recursive: true);
    },
  );
}
