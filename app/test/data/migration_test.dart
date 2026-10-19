import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';

void main() {
  test('reopening schema v1 retains queue and settings', () async {
    final dir = Directory.systemTemp.createTempSync('day-migration-');
    final file = File('${dir.path}/v1.sqlite');
    var db = AppDatabase.open(file, workspaceId: 'local');
    await SqliteTaskRepository(db).execute(
      TaskCommand.createTask(id: 'old', title: 'Сохранено', listId: inboxId),
    );
    await db.setSetting('theme', 'dark');
    await db.close();
    db = AppDatabase.open(file, workspaceId: 'local');
    try {
      expect(await db.setting('theme'), 'dark');
      expect((await SqliteTaskRepository(db).allPending()).length, 1);
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
}
