import 'dart:async';
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

class PausedBackup extends BackupRepository {
  final entered = Completer<void>(), release = Completer<void>();
  PausedBackup(super.repository, {required super.directory});
  @override
  Future<File> createSafetyBackup() async {
    entered.complete();
    await release.future;
    return super.createSafetyBackup();
  }
}

class PausedExportRepository extends SqliteTaskRepository {
  final entered = Completer<void>(), release = Completer<void>();
  PausedExportRepository(super.db);
  @override
  Future<List<Map<String, Object?>>> entities(String type) async {
    final values = await super.entities(type);
    if (type == 'rule' && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return values;
  }
}

void main() {
  test('import validates all field types, zones, wall times and UTC timestamps before mutation', () async {
    final db = AppDatabase.memory(workspaceId: 'local'),
        dir = Directory.systemTemp.createTempSync('day-validate-');
    final repo = SqliteTaskRepository(db),
        backup = BackupRepository(repo, directory: dir);
    try {
      final id = const Uuid().v4();
      final invalid = [
        ('task', {'id': id, 'title': 'Дело', 'position': 'broken'}),
        (
          'task',
          {'id': id, 'title': 'Дело', 'reminderTimezone': 'Invalid/Zone'},
        ),
        (
          'task',
          {'id': id, 'title': 'Дело', 'reminderAtUtc': '2026-02-30T12:00:00Z'},
        ),
        (
          'task',
          {'id': id, 'title': 'Дело', 'completedAt': '2026-10-19T12:00:00'},
        ),
        (
          'rule',
          {
            'id': id,
            'frequency': 'daily',
            'timezone': 'UTC',
            'reminderTime': '29:99',
          },
        ),
        (
          'rule',
          {
            'id': id,
            'frequency': 'weekly',
            'timezone': 'UTC',
            'weekdays': [1, 1],
          },
        ),
        ('list', {'id': id, 'name': 'Список', 'color': 'red'}),
      ];
      for (final pair in invalid) {
        final bytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'schemaVersion': 1,
              'entities': [
                {'type': pair.$1, 'value': pair.$2},
              ],
            }),
          ),
        );
        await expectLater(
          backup.inspectImport(bytes),
          throwsFormatException,
          reason: pair.toString(),
        );
      }
      expect(await repo.allPending(), isEmpty);
      expect(await repo.entities('task'), isEmpty);
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
  test(
    'export serializes one consistent snapshot against concurrent writes',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local'),
          dir = Directory.systemTemp.createTempSync('day-export-');
      final repo = PausedExportRepository(db),
          backup = BackupRepository(repo, directory: dir);
      try {
        final exporting = backup.exportBytes();
        await repo.entered.future;
        final rule = const Uuid().v4(), id = const Uuid().v4();
        final writing = db.transaction(() async {
          await repo.execute(
            TaskCommand.upsertRule(rule, {
              'frequency': 'daily',
              'timezone': 'UTC',
            }),
          );
          await repo.execute(
            TaskCommand.createTask(
              id: id,
              title: 'Одновременно',
              listId: inboxId,
              fields: {'recurrenceRuleId': rule},
            ),
          );
        });
        await Future.any([
          writing,
          Future<void>.delayed(const Duration(milliseconds: 150)),
        ]);
        repo.release.complete();
        final json = jsonDecode(utf8.decode(await exporting)) as Map;
        await writing;
        final values = json['entities'] as List;
        if (values.any((e) => e['type'] == 'task')) {
          expect(values.any((e) => e['type'] == 'rule'), true);
        }
      } finally {
        await db.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
  test(
    'sync arriving during safety backup cannot be overwritten by stale import',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local'),
          dir = Directory.systemTemp.createTempSync('day-import-');
      final repo = SqliteTaskRepository(db),
          backup = PausedBackup(repo, directory: dir);
      try {
        final id = const Uuid().v4();
        await repo.execute(
          TaskCommand.createTask(id: id, title: 'Исходное', listId: inboxId),
        );
        final raw = jsonDecode(utf8.decode(await backup.exportBytes())) as Map;
        (raw['entities'] as List).firstWhere(
          (e) => e['type'] == 'task',
        )['value']['title'] = 'Из копии';
        final preview = await backup.inspectImport(
          Uint8List.fromList(utf8.encode(jsonEncode(raw))),
        );
        final importing = backup.applyImport(preview);
        await backup.entered.future;
        final writing = repo.execute(
          TaskCommand.patchTask(id, {'title': 'Свежая синхронизация'}),
        );
        await Future.any([
          writing,
          Future<void>.delayed(const Duration(milliseconds: 150)),
        ]);
        backup.release.complete();
        await importing;
        await writing;
        expect((await repo.readTask(id))!.title, 'Свежая синхронизация');
      } finally {
        await db.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
}
