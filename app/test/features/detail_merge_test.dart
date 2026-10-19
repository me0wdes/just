import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/task_detail_panel.dart';
import 'package:day_planner/platform/feedback_service.dart';

void main() {
  test(
    'editing monthly recurrence preserves day 31 and its existing zone',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local');
      final repo = SqliteTaskRepository(db);
      final id = const Uuid().v4(), rule = const Uuid().v4();
      final c = TaskController(
        repo,
        feedback: const SilentCompletionFeedback(),
        today: () => LocalDate.parse('2027-02-28'),
      );
      try {
        await repo.execute(
          TaskCommand.upsertRule(rule, {
            'frequency': 'monthly',
            'monthDay': 31,
            'timezone': 'America/New_York',
          }),
        );
        await repo.execute(
          TaskCommand.createTask(
            id: id,
            title: 'Месячное',
            listId: inboxId,
            fields: {'dueDate': '2027-02-28', 'recurrenceRuleId': rule},
          ),
        );
        await c.setRecurrence((await repo.readTask(id))!, 'monthly');
        expect((await repo.readRule(rule))!.monthDay, 31);
        expect((await repo.readRule(rule))!.timezone, 'America/New_York');
        final completed = await repo.execute(
          TaskCommand.completeTask(id, '2027-02-28'),
        );
        expect(
          (await repo.readTask(completed.provisionalSuccessorId!))!.dueDate
              .toString(),
          '2027-03-31',
        );
      } finally {
        c.dispose();
        await db.close();
      }
    },
  );
  testWidgets(
    'details submit only edited fields and preserve monthly day and zone',
    (tester) async {
      final db = AppDatabase.memory(workspaceId: 'local');
      final repo = SqliteTaskRepository(db),
          id = const Uuid().v4(),
          rule = const Uuid().v4();
      await repo.execute(
        TaskCommand.upsertRule(rule, {
          'frequency': 'monthly',
          'monthDay': 31,
          'timezone': 'America/New_York',
        }),
      );
      await repo.execute(
        TaskCommand.createTask(
          id: id,
          title: 'Старое название',
          listId: inboxId,
          fields: {'dueDate': '2027-02-28', 'recurrenceRuleId': rule},
        ),
      );
      final c = TaskController(
        repo,
        feedback: const SilentCompletionFeedback(),
        today: () => LocalDate.parse('2027-02-28'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskDetailPanel(
              task: (await repo.readTask(id))!,
              controller: c,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // A concurrent device update arrives while this details draft is open.
      await repo.execute(
        TaskCommand.patchTask(id, {
          'title': 'С другого устройства',
          'plannedForDate': '2027-03-04',
        }),
      );
      await tester.enterText(find.byType(TextField).at(1), 'Только заметка');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      final saved = (await repo.readTask(id))!;
      expect(saved.title, 'С другого устройства');
      expect(saved.plannedForDate.toString(), '2027-03-04');
      expect(saved.note, 'Только заметка');
      expect((await repo.allPending()).last.changes, {
        'note': 'Только заметка',
      });
      expect((await repo.readRule(rule))!.monthDay, 31);
      expect((await repo.readRule(rule))!.timezone, 'America/New_York');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
    },
  );
}
