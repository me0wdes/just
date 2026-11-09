import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:uuid/uuid.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/platform/feedback_service.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  test(
    'completion uses recurrence timezone and custom weekdays remain selected',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local');
      final repo = SqliteTaskRepository(db);
      final controller = TaskController(
        repo,
        feedback: const SilentCompletionFeedback(),
        today: () => LocalDate.parse('2026-10-19'),
        clock: () => DateTime.utc(2026, 10, 19, 22),
      );
      try {
        final id = const Uuid().v4();
        await repo.execute(
          TaskCommand.createTask(
            id: id,
            title: 'Прогулка',
            listId: inboxId,
            fields: {'dueDate': '2026-10-19'},
          ),
        );
        await controller.setRecurrence(
          (await repo.readTask(id))!,
          'weekly',
          timezone: 'Europe/Moscow',
          weekdays: [2, 4],
        );
        final rule = await repo.readRule(
          (await repo.readTask(id))!.recurrenceRuleId!,
        );
        expect(rule!.weekdays, [2, 4]);
        final receipt = await controller.completeTask(id);
        expect(
          (await repo.readTask(receipt.provisionalSuccessorId!))!.dueDate
              .toString(),
          '2026-10-22',
        );
        expect(
          (await repo.allPending()).last.changes['completionDate'],
          '2026-10-20',
        );
      } finally {
        controller.dispose();
        await db.close();
      }
    },
  );

  test('a done task is deleted a week after it was completed', () async {
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(
      db,
      clock: () => DateTime.utc(2026, 10, 1, 12),
    );
    const id = '6f0c2a54-4b9e-4f6b-9a51-0d3c7e1a2b01';
    await repo.execute(
      TaskCommand.createTask(
        id: id,
        title: 'Старое дело',
        listId: inboxId,
        fields: {'dueDate': '2026-10-01'},
      ),
    );
    await repo.execute(TaskCommand.completeTask(id, '2026-10-01'));
    expect((await repo.readTask(id))!.expiresAt, DateTime.utc(2026, 10, 8, 12));
    final controller = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-09'),
      clock: () => DateTime.utc(2026, 10, 9),
    );
    try {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect((await repo.readTask(id))!.deleted, true);
    } finally {
      controller.dispose();
      await db.close();
    }
  });
}
