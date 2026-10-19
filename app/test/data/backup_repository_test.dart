import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/data/backup_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';

void main() {
  test('backup previews without mutation, excludes credentials, imports history atomically', () async {
    final dir = Directory.systemTemp.createTempSync('day-backup-');
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    final backups = BackupRepository(repo, directory: dir);
    try {
      final id = const Uuid().v4(), rule = const Uuid().v4();
      await repo.execute(
        TaskCommand.upsertRule(rule, {
          'frequency': 'daily',
          'timezone': 'Europe/Moscow',
        }),
      );
      await repo.execute(
        TaskCommand.createTask(
          id: id,
          title: 'Чтение',
          listId: inboxId,
          fields: {'recurrenceRuleId': rule, 'dueDate': '2026-10-19'},
        ),
      );
      await repo.execute(TaskCommand.completeTask(id, '2026-10-19'));
      await db.setSetting('syncToken', 'TEST-SECRET');
      final bytes = await backups.exportBytes();
      expect(utf8.decode(bytes), isNot(contains('TEST-SECRET')));
      final preview = await backups.inspectImport(bytes);
      expect(preview.newCount, 0);
      expect(preview.matchingCount, 4);
      final before = (await repo.allPending()).length;
      expect((await repo.allPending()).length, before);
      final result = await backups.applyImport(preview);
      expect(File(result.safetyBackupPath).existsSync(), true);
      expect((await repo.entities('task')).length, 2);
      expect((await repo.readTask(id))!.completed, true);
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
  test('invalid import and stale preview never replace current data', () async {
    final dir = Directory.systemTemp.createTempSync('day-invalid-');
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    final backups = BackupRepository(repo, directory: dir);
    try {
      final id = const Uuid().v4();
      await repo.execute(
        TaskCommand.createTask(id: id, title: 'Исходное', listId: inboxId),
      );
      for (final json in [
        '{broken',
        '{"schemaVersion":2,"entities":[]}',
        jsonEncode({
          'schemaVersion': 1,
          'entities': [
            {
              'type': 'task',
              'value': {'id': id, 'title': '😀' * 501},
            },
          ],
        }),
      ]) {
        await expectLater(
          backups.inspectImport(Uint8List.fromList(utf8.encode(json))),
          throwsFormatException,
        );
      }
      final preview = await backups.inspectImport(await backups.exportBytes());
      await repo.execute(
        TaskCommand.patchTask(id, {'title': 'После просмотра'}),
      );
      await expectLater(backups.applyImport(preview), throwsStateError);
      expect((await repo.readTask(id))!.title, 'После просмотра');
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
}
