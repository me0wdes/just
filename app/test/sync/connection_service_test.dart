import 'package:drift/drift.dart' show driftRuntimeOptions;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/data/backup_repository.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/platform/secure_connection_store.dart';
import 'package:day_planner/sync/connection_service.dart';
import 'package:day_planner/sync/sync_transport.dart';

import 'server_fixture.dart';

class MemorySecrets implements SecureConnectionStore {
  final values = <String, ConnectionSecret>{};
  bool fail = false;
  @override
  Future<ConnectionSecret?> read(String id) async => values[id];
  @override
  Future<void> write(String id, ConnectionSecret value) async {
    if (fail) throw StateError('storage unavailable');
    values[id] = value;
  }

  @override
  Future<void> delete(String id) async {
    values.remove(id);
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  test(
    'empty preview and separate workspace preserve original pending operations',
    () async {
      final server = await ServerFixture.start(),
          dir = Directory.systemTemp.createTempSync('day-connection-');
      final db = AppDatabase.open(
        File('${dir.path}/day.sqlite'),
        workspaceId: 'local',
      );
      final repo = SqliteTaskRepository(db);
      final secrets = MemorySecrets();
      final service = ConnectionService(
        rootDatabase: db,
        repository: repo,
        backups: BackupRepository(
          repo,
          directory: Directory('${dir.path}/backups'),
        ),
        directory: dir,
        secrets: secrets,
        transportFactory: (uri, key) =>
            HttpSyncTransport(uri, () async => key, allowDebugLoopback: true),
      );
      try {
        final id = uuid();
        await repo.execute(
          TaskCommand.createTask(id: id, title: 'Локальное', listId: inboxId),
        );
        final preview = await service.inspect(server.endpoint, server.token);
        expect(preview.remoteCount, 0);
        expect(preview.pendingCount, 1);
        expect(await repo.getCursor(), 0);
        final result = await service.connect(
          preview,
          ConnectionChoice.openSeparate,
        );
        try {
          expect((await repo.allPending()).length, 1);
          expect(await result.repository.readTask(id), isNull);
          expect(File(result.safetyBackupPath).existsSync(), true);
          expect(secrets.values.length, 1);
        } finally {
          await result.database.close();
        }
      } finally {
        await db.close();
        await server.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
  test('secure storage failure leaves active profile and original records unchanged', () async {
    final server = await ServerFixture.start(),
        dir = Directory.systemTemp.createTempSync('day-connect-failure-');
    final db = AppDatabase.open(
      File('${dir.path}/day.sqlite'),
      workspaceId: 'local',
    );
    final repo = SqliteTaskRepository(db),
        secrets = MemorySecrets()..fail = true;
    final service = ConnectionService(
      rootDatabase: db,
      repository: repo,
      backups: BackupRepository(
        repo,
        directory: Directory('${dir.path}/backups'),
      ),
      directory: dir,
      secrets: secrets,
      transportFactory: (uri, key) =>
          HttpSyncTransport(uri, () async => key, allowDebugLoopback: true),
    );
    try {
      final id = uuid();
      await repo.execute(
        TaskCommand.createTask(id: id, title: 'Останется', listId: inboxId),
      );
      final preview = await service.inspect(server.endpoint, server.token);
      await expectLater(
        service.connect(preview, ConnectionChoice.merge),
        throwsStateError,
      );
      expect(await db.setting('activeConnectionProfile'), isNull);
      expect((await repo.readTask(id))!.title, 'Останется');
      expect((await repo.allPending()).length, 1);
    } finally {
      await db.close();
      await server.close();
      dir.deleteSync(recursive: true);
    }
  });
}
