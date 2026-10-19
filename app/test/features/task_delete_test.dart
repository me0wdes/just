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
  testWidgets('deleting from details offers undo and restores the task', (
    tester,
  ) async {
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db), id = const Uuid().v4();
    await repo.execute(
      TaskCommand.createTask(
        id: id,
        title: 'Вернуть после удаления',
        listId: inboxId,
      ),
    );
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: LocalDate.today,
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
    await tester.scrollUntilVisible(
      find.text('Удалить задачу'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Удалить задачу'));
    await tester.pumpAndSettle();
    expect((await repo.readTask(id))!.deleted, true);
    expect(find.text('Отменить'), findsOneWidget);
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect((await repo.readTask(id))!.deleted, false);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });
}
