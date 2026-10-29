import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/task_home.dart';
import 'package:day_planner/platform/feedback_service.dart';
import 'package:day_planner/domain/models.dart';

void main() {
  testWidgets('blocked reminders say why and offer the settings', (
    tester,
  ) async {
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
    await controller.addTask('Позвонить маме');
    await tester.pumpAndSettle();
    final id = controller.tasks.single.id;
    controller.setReminderFailures({
      id: 'Разрешите точные напоминания в настройках Android.',
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Напоминания выключены'));
    await tester.pumpAndSettle();
    expect(find.text('Напоминания не придут'), findsOneWidget);
    expect(find.textContaining('точные будильники'), findsOneWidget);
    expect(find.text('Позвонить маме'), findsOneWidget);
    expect(find.text('Открыть настройки'), findsOneWidget);
    await tester.tap(find.text('Не сейчас'));
    await tester.pumpAndSettle();
    expect(find.text('Напоминания не придут'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await db.close();
  });
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
