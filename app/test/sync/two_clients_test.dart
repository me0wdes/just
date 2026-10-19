import 'package:drift/drift.dart' show driftRuntimeOptions;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/sync/sync_engine.dart';
import 'package:day_planner/sync/sync_transport.dart';
import 'package:day_planner/sync/protocol.dart';

import 'server_fixture.dart';

class LoseResponse implements SyncTransport {
  final SyncTransport inner;
  bool drop = false;
  LoseResponse(this.inner);
  @override
  Future<SyncResponse> exchange(SyncRequest request) async {
    final result = await inner.exchange(request);
    if (drop) {
      drop = false;
      throw const SocketException('simulated response loss');
    }
    return result;
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  test(
    'bound client refuses a replacement workspace before sending local data',
    () async {
      final server = await ServerFixture.start();
      final db = AppDatabase.memory(workspaceId: 'local'),
          repo = SqliteTaskRepository(db);
      final transport = HttpSyncTransport(
        server.endpoint,
        () async => server.token,
        allowDebugLoopback: true,
      );
      final engine = SyncEngine(
        repo,
        transport,
        deviceId: uuid(),
        scheduler: TimerScheduler(),
      );
      try {
        await db.setMeta('remoteWorkspace', uuid());
        final id = uuid();
        await repo.execute(
          TaskCommand.createTask(
            id: id,
            title: 'Только прежнее пространство',
            listId: inboxId,
          ),
        );
        await engine.syncNow();
        expect(engine.state, SyncState.authRequired);
        final remote = await transport.exchange(
          SyncRequest(deviceId: uuid(), cursor: 0, operations: []),
        );
        expect(remote.changes.where((c) => c.entityType == 'task'), isEmpty);
        expect((await repo.allPending()).length, 1);
      } finally {
        engine.dispose();
        await db.close();
        await server.close();
      }
    },
  );
  test(
    'canonical null preserves edited provisional descendants as ordinary tasks',
    () async {
      final server = await ServerFixture.start();
      final da = AppDatabase.memory(workspaceId: 'local'),
          db = AppDatabase.memory(workspaceId: 'local');
      final a = SqliteTaskRepository(da), b = SqliteTaskRepository(db);
      SyncEngine engine(SqliteTaskRepository repo) => SyncEngine(
        repo,
        HttpSyncTransport(
          server.endpoint,
          () async => server.token,
          allowDebugLoopback: true,
        ),
        deviceId: uuid(),
        scheduler: TimerScheduler(),
      );
      final ea = engine(a), eb = engine(b);
      try {
        final id = uuid(), rule = uuid();
        await a.execute(
          TaskCommand.upsertRule(rule, {
            'frequency': 'daily',
            'timezone': 'Europe/Moscow',
          }),
        );
        await a.execute(
          TaskCommand.createTask(
            id: id,
            title: 'Повтор',
            listId: inboxId,
            fields: {'recurrenceRuleId': rule, 'dueDate': '2026-10-19'},
          ),
        );
        await ea.syncNow();
        await eb.syncNow();
        await a.execute(TaskCommand.patchTask(id, {'recurrenceRuleId': null}));
        await a.execute(TaskCommand.completeTask(id, '2026-10-19'));
        await ea.syncNow();
        final child = await b.execute(
          TaskCommand.completeTask(id, '2026-10-19'),
        );
        await b.execute(
          TaskCommand.patchTask(child.provisionalSuccessorId!, {
            'note': 'Правка первого потомка',
          }),
        );
        final grandchild = await b.execute(
          TaskCommand.completeTask(child.provisionalSuccessorId!, '2026-10-20'),
        );
        await b.execute(
          TaskCommand.patchTask(grandchild.provisionalSuccessorId!, {
            'title': 'Сохранить второго потомка',
          }),
        );
        await eb.syncNow();
        await ea.syncNow();
        final local = await b.entities('task'),
            remote = await a.entities('task');
        expect(local.any((t) => t['note'] == 'Правка первого потомка'), true);
        expect(
          local.any((t) => t['title'] == 'Сохранить второго потомка'),
          true,
        );
        expect(
          remote.any((t) => t['title'] == 'Сохранить второго потомка'),
          true,
        );
        expect((await b.readTask(id))!.successorId, isNull);
        expect(await b.allPending(), isEmpty);
      } finally {
        ea.dispose();
        eb.dispose();
        await da.close();
        await db.close();
        await server.close();
      }
    },
  );
  test('rejection stays visible across polls and explicit replacement unblocks corrected work', () async {
    final server = await ServerFixture.start();
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    final engine = SyncEngine(
      repo,
      HttpSyncTransport(
        server.endpoint,
        () async => server.token,
        allowDebugLoopback: true,
      ),
      deviceId: uuid(),
      scheduler: TimerScheduler(),
    );
    try {
      final id = uuid();
      await repo.execute(
        TaskCommand.createList(id, 'Название', color: 'broken'),
      );
      await engine.syncNow();
      expect(engine.state, SyncState.rejected);
      await engine.syncNow();
      expect(engine.state, SyncState.rejected);
      await repo.execute(
        TaskCommand.patchList(id, {'color': '#123456', 'name': 'Исправлено'}),
      );
      final rejected = (await repo.allPending()).first;
      await (repo as dynamic).resolveRejected(
        rejected.operationId,
        retry: true,
      );
      await engine.syncNow();
      expect(engine.state, SyncState.synced);
      expect(await repo.allPending(), isEmpty);
    } finally {
      engine.dispose();
      await db.close();
      await server.close();
    }
  });
  test(
    'rejected undo restores canonical completion and exposes its successor',
    () async {
      final server = await ServerFixture.start();
      final da = AppDatabase.memory(workspaceId: 'local'),
          db = AppDatabase.memory(workspaceId: 'local');
      final a = SqliteTaskRepository(da), b = SqliteTaskRepository(db);
      SyncEngine engine(SqliteTaskRepository repo) => SyncEngine(
        repo,
        HttpSyncTransport(
          server.endpoint,
          () async => server.token,
          allowDebugLoopback: true,
        ),
        deviceId: uuid(),
        scheduler: TimerScheduler(),
      );
      final ea = engine(a), eb = engine(b);
      try {
        final rule = uuid(), id = uuid();
        await a.execute(
          TaskCommand.upsertRule(rule, {
            'frequency': 'daily',
            'timezone': 'Europe/Moscow',
          }),
        );
        await a.execute(
          TaskCommand.createTask(
            id: id,
            title: 'Проверка отмены',
            listId: inboxId,
            fields: {'recurrenceRuleId': rule, 'dueDate': '2026-10-19'},
          ),
        );
        await ea.syncNow();
        await a.execute(TaskCommand.completeTask(id, '2026-10-19'));
        await ea.syncNow();
        await eb.syncNow();
        final completed = (await b.readTask(id))!;
        await b.execute(
          TaskCommand.patchTask(completed.successorId!, {
            'note': 'Изменено на другом устройстве',
          }),
        );
        await eb.syncNow();
        await a.execute(
          TaskCommand.undoCompletion(id, (await a.readTask(id))!.completionId!),
        );
        await ea.syncNow();
        expect((await a.readTask(id))!.completed, true);
        expect(ea.lastRejectionCode, 'successor_modified');
        expect(
          (await a.latestConflict())!['successorId'],
          completed.successorId,
        );
      } finally {
        ea.dispose();
        eb.dispose();
        await da.close();
        await db.close();
        await server.close();
      }
    },
  );
  test('two file databases converge after lost response and different offline completion dates', () async {
    final server = await ServerFixture.start();
    final dir = Directory.systemTemp.createTempSync('day-pair-');
    final dbA = AppDatabase.open(
          File('${dir.path}/a.sqlite'),
          workspaceId: 'local',
        ),
        dbB = AppDatabase.open(
          File('${dir.path}/b.sqlite'),
          workspaceId: 'local',
        );
    final a = SqliteTaskRepository(dbA), b = SqliteTaskRepository(dbB);
    final transport = LoseResponse(
      HttpSyncTransport(
        server.endpoint,
        () async => server.token,
        allowDebugLoopback: true,
      ),
    );
    final ea = SyncEngine(
          a,
          transport,
          deviceId: uuid(),
          scheduler: TimerScheduler(),
        ),
        eb = SyncEngine(
          b,
          HttpSyncTransport(
            server.endpoint,
            () async => server.token,
            allowDebugLoopback: true,
          ),
          deviceId: uuid(),
          scheduler: TimerScheduler(),
        );
    try {
      final id = uuid(), rule = uuid();
      await a.execute(
        TaskCommand.upsertRule(rule, {
          'frequency': 'daily',
          'timezone': 'Europe/Moscow',
        }),
      );
      await a.execute(
        TaskCommand.createTask(
          id: id,
          title: 'Хлеб',
          listId: inboxId,
          fields: {'recurrenceRuleId': rule, 'dueDate': '2026-10-19'},
        ),
      );
      await ea.syncNow();
      await eb.syncNow();
      expect((await b.readTask(id))!.title, 'Хлеб');
      await a.execute(TaskCommand.completeTask(id, '2026-10-19'));
      final offline = await b.execute(
        TaskCommand.completeTask(id, '2026-10-21'),
      );
      await b.execute(
        TaskCommand.patchTask(offline.provisionalSuccessorId!, {
          'note': 'Сохранить эту правку',
        }),
      );
      transport.drop = true;
      await ea.syncNow();
      expect(ea.state, SyncState.offline);
      await ea.syncNow();
      await eb.syncNow();
      await ea.syncNow();
      final children = (await b.entities('task'))
          .where((t) => t['id'] != id && t['deletedAt'] == null)
          .toList();
      expect(children.length, 1);
      expect(children.single['dueDate'], '2026-10-20');
      expect(children.single['note'], 'Сохранить эту правку');
      expect(
        (await a.readTask(children.single['id'] as String))!.note,
        'Сохранить эту правку',
      );
    } finally {
      ea.dispose();
      eb.dispose();
      await dbA.close();
      await dbB.close();
      await server.close();
      dir.deleteSync(recursive: true);
    }
  });
  test('UTF8 request stays within byte budget and 501 server changes page without loss', () async {
    final server = await ServerFixture.start();
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    final transport = HttpSyncTransport(
      server.endpoint,
      () async => server.token,
      allowDebugLoopback: true,
    );
    final engine = SyncEngine(
      repo,
      transport,
      deviceId: uuid(),
      scheduler: TimerScheduler(),
    );
    try {
      for (var i = 0; i < 9; i++) {
        await repo.execute(
          TaskCommand.createTask(
            id: uuid(),
            title: 'Задача $i',
            listId: inboxId,
            fields: {'note': '😀' * 10000},
          ),
        );
      }
      await engine.syncNow();
      expect(await repo.allPending(), isEmpty);
      for (var batch = 0; batch < 6; batch++) {
        await transport.exchange(
          SyncRequest(
            deviceId: uuid(),
            cursor: 0,
            operations: [
              for (var i = 0; i < (batch == 5 ? 1 : 100); i++)
                Operation(
                  operationId: uuid(),
                  entityType: 'task',
                  entityId: uuid(),
                  kind: 'create',
                  createdAt: '2026-10-19T00:00:00Z',
                  localSequence: 1,
                  changes: {'title': 'Удалённая $batch/$i'},
                ),
            ],
          ),
        );
      }
      await engine.syncNow();
      expect((await repo.entities('task')).length, 510);
      expect(await repo.getCursor(), 511);
    } finally {
      engine.dispose();
      await db.close();
      await server.close();
    }
  });
}
