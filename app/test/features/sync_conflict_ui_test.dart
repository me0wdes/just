import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:day_planner/app.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/data/backup_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/platform/feedback_service.dart';
import 'package:day_planner/sync/sync_engine.dart';
import 'package:day_planner/sync/protocol.dart';
import 'package:day_planner/sync/sync_transport.dart';

class NoNetwork implements SyncTransport {
  @override
  Future<SyncResponse> exchange(SyncRequest request) async => SyncResponse(
    workspaceId: 'remote',
    acknowledgements: [],
    changes: [],
    nextCursor: 0,
    hasMore: false,
  );
}

class MemorySafetyBackup extends BackupRepository {
  int copies = 0;
  MemorySafetyBackup(super.repository, {required super.directory});
  @override
  Future<File> createSafetyBackup() async {
    copies++;
    return File('${directory.path}/safety.json');
  }
}

void main() {
  testWidgets('persisted rejection opens an actionable resolution dialog', (
    tester,
  ) async {
    final db = AppDatabase.memory(workspaceId: 'local'),
        dir = Directory.systemTemp.createTempSync('day-conflict-');
    final repo = SqliteTaskRepository(db);
    final id = const Uuid().v4();
    final op = await repo.execute(
      TaskCommand.createList(id, 'Мой список', color: 'broken'),
    );
    await repo.markRejected(op.operationId, 'invalid_color');
    final controller = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: LocalDate.today,
    );
    final engine = SyncEngine(
      repo,
      NoNetwork(),
      deviceId: const Uuid().v4(),
      scheduler: TimerScheduler(),
    )..state = SyncState.rejected;
    final backups = MemorySafetyBackup(repo, directory: dir);
    await tester.pumpWidget(
      DayApp(controller: controller, engine: engine, backups: backups),
    );
    await tester.pumpAndSettle();
    // On a phone-sized window the sync status lives in the lists drawer.
    await tester.tap(find.byTooltip('Списки'));
    await tester.pumpAndSettle();
    // The status is a cloud icon; its hint names the conflict.
    expect(
      find.byTooltip(
        'Есть конфликт · локальная копия сохранена · нажмите, чтобы повторить',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('sidebar-sync')));
    await tester.pumpAndSettle();
    expect(find.text('Неотправленные изменения'), findsOneWidget);
    expect(find.text('Не удалось принять цвет списка.'), findsOneWidget);
    expect(find.text('Версия сервера'), findsOneWidget);
    await tester.tap(find.text('Версия сервера'));
    await tester.pumpAndSettle();
    expect(await repo.allPending(), isEmpty);
    expect(backups.copies, 1);
    // The last conflict settled: the dialog closes by itself.
    await tester.pumpAndSettle();
    expect(find.text('Неотправленные изменения'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    engine.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });
}
