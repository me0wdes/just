import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/sync/protocol.dart';

void main() {
  test('offline task and outbox survive reopen; pending title wins old server data', () async {
    final dir = Directory.systemTemp.createTempSync('day-client-');
    final file = File('${dir.path}/tasks.sqlite');
    var db = AppDatabase.open(file, workspaceId: 'local');
    var repo = SqliteTaskRepository(db);
    final id = const Uuid().v4();
    await repo.execute(
      TaskCommand.createTask(id: id, title: 'Хлеб', listId: inboxId),
    );
    await db.close();
    db = AppDatabase.open(file, workspaceId: 'local');
    repo = SqliteTaskRepository(db);
    try {
      expect((await repo.readTask(id))!.title, 'Хлеб');
      expect(
        (await repo.pendingBatch(
          maxOperations: 100,
          byteBudget: 260000,
        )).length,
        1,
      );
      await repo.applySyncResponse(
        SyncResponse.fromJson({
          'protocolVersion': 1,
          'workspaceId': 'local',
          'acknowledgements': [],
          'changes': [
            {
              'entityType': 'task',
              'entityId': id,
              'revision': 1,
              'value': {'id': id, 'title': 'Старое', 'listId': inboxId},
            },
          ],
          'nextCursor': 1,
          'hasMore': false,
        }),
      );
      expect((await repo.readTask(id))!.title, 'Хлеб');
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
  test(
    'failed commit rolls back both projected task and pending operation',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local');
      final repo = SqliteTaskRepository(db);
      try {
        await expectLater(
          db.transaction(() async {
            await repo.execute(
              TaskCommand.createTask(
                id: 'rollback',
                title: 'Не сохранять',
                listId: inboxId,
              ),
            );
            throw StateError('interrupted');
          }),
          throwsStateError,
        );
        expect(await repo.readTask('rollback'), isNull);
        expect(
          await repo.pendingBatch(maxOperations: 100, byteBudget: 260000),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'today includes overdue; list deletion and undo preserve tasks',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local');
      final repo = SqliteTaskRepository(db);
      try {
        await repo.execute(TaskCommand.createList('home', 'Дом'));
        await repo.execute(
          TaskCommand.createTask(
            id: 'a',
            title: 'Позавчера',
            listId: 'home',
            fields: {'dueDate': '2026-10-17', 'position': 1024},
          ),
        );
        await repo.execute(
          TaskCommand.createTask(
            id: 'b',
            title: 'Без срока',
            listId: inboxId,
            fields: {'position': 1024},
          ),
        );
        expect(
          (await repo
                  .watchTasks(TaskQuery(today: LocalDate.parse('2026-10-19')))
                  .first)
              .map((t) => t.id),
          ['a'],
        );
        await repo.execute(TaskCommand.deleteList('home'));
        expect((await repo.readTask('a'))!.listId, inboxId);
        await repo.execute(TaskCommand.deleteTask('a'));
        expect((await repo.readTask('a'))!.deleted, true);
        await repo.execute(TaskCommand.restoreTask('a'));
        expect((await repo.readTask('a'))!.deleted, false);
        expect(
          (await repo
                  .watchTasks(
                    TaskQuery(view: TaskView.all, today: LocalDate.today()),
                  )
                  .first)
              .map((t) => t.id),
          ['a', 'b'],
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'recurring completion projects successor without standalone create',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local');
      final repo = SqliteTaskRepository(db);
      try {
        final rule = const Uuid().v4(), id = const Uuid().v4();
        await repo.execute(
          TaskCommand.upsertRule(rule, {
            'frequency': 'daily',
            'timezone': 'Europe/Moscow',
          }),
        );
        await repo.execute(
          TaskCommand.createTask(
            id: id,
            title: 'Прогулка',
            listId: inboxId,
            fields: {'recurrenceRuleId': rule, 'dueDate': '2026-10-19'},
          ),
        );
        final receipt = await repo.execute(
          TaskCommand.completeTask(id, '2026-10-19'),
        );
        expect(receipt.provisionalSuccessorId, isNotNull);
        expect(
          (await repo.readTask(receipt.provisionalSuccessorId!))!.dueDate
              .toString(),
          '2026-10-20',
        );
        final ops = await repo.allPending();
        expect(
          ops.where(
            (o) =>
                o.entityId == receipt.provisionalSuccessorId &&
                o.kind == 'create',
          ),
          isEmpty,
        );
        await repo.execute(
          TaskCommand.undoCompletion(id, receipt.completionId!),
        );
        expect((await repo.readTask(id))!.completed, false);
      } finally {
        await db.close();
      }
    },
  );
}
