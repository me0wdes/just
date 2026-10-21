import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/features/tasks/task_row.dart';

void main() {
  test('due time is optional, validated and shown after the day', () async {
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    final id = const Uuid().v4();
    try {
      await repo.execute(
        TaskCommand.createTask(id: id, title: 'Созвон', listId: inboxId),
      );
      await repo.execute(
        TaskCommand.patchTask(id, {
          'dueDate': '2026-10-22',
          'dueTime': '13:00',
        }),
      );
      final task = (await repo.readTask(id))!;
      expect(task.dueTime, '13:00');
      final today = LocalDate.parse('2026-10-21');
      expect(dueLabel(task.dueDate!, today, task.dueTime), 'Завтра, 13:00');
      expect(dueLabel(task.dueDate!, today), 'Завтра');
      await expectLater(
        repo.execute(TaskCommand.patchTask(id, {'dueTime': '25:00'})),
        throwsFormatException,
      );
      await repo.execute(TaskCommand.patchTask(id, {'dueTime': null}));
      expect((await repo.readTask(id))!.dueTime, isNull);
    } finally {
      await db.close();
    }
  });

  test('a timed task is overdue from its due time, a dated one next day', () {
    final today = LocalDate.parse('2026-10-21');
    TaskItem task(Map<String, Object?> f) =>
        TaskItem.fromJson({'id': 'x', 'title': 'Т', ...f});
    final timed = task({'dueDate': '2026-10-21', 'dueTime': '13:00'});
    final dated = task({'dueDate': '2026-10-21'});
    expect(timed.isOverdue(today, DateTime(2026, 10, 21, 12, 59)), isFalse);
    expect(timed.isOverdue(today, DateTime(2026, 10, 21, 13)), isTrue);
    expect(dated.isOverdue(today, DateTime(2026, 10, 21, 23, 59)), isFalse);
    expect(
      dated.isOverdue(LocalDate.parse('2026-10-22'), DateTime(2026, 10, 22)),
      isTrue,
    );
  });
}
