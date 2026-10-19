import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/task_home.dart';
import 'package:day_planner/platform/feedback_service.dart';
import 'package:day_planner/domain/models.dart';

void main() {
  testWidgets('Enter saves a real task without network', (tester) async {
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    final controller = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    await tester.pumpWidget(
      MaterialApp(home: TaskHome(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-title-input')),
      'Записаться к врачу',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Записаться к врачу'), findsOneWidget);
    expect(
      (await repo.allPending()).single.changes['title'],
      'Записаться к врачу',
    );
    await tester.tap(find.byTooltip('Выполнить'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    // A finished item leaves «Активные» and shows up in «Выполненные».
    expect(find.text('Записаться к врачу'), findsNothing);
    await tester.tap(find.text('Выполненные'));
    await tester.pumpAndSettle();
    expect(find.text('Записаться к врачу'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await db.close();
  });
}
