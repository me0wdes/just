import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/task_home.dart';
import 'package:day_planner/platform/feedback_service.dart';

void main() {
  testWidgets('right click on a card opens its menu and deletes with undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    await repo.execute(
      TaskCommand.createTask(
        id: 'x',
        title: 'Лишнее дело',
        listId: inboxId,
        fields: {'plannedForDate': '2026-10-19'},
      ),
    );
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    await tester.pumpWidget(MaterialApp(home: TaskHome(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Лишнее дело'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Открыть'), findsOneWidget);
    expect(find.text('Выполнить'), findsOneWidget);
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect((await repo.readTask('x'))!.deleted, true);
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect((await repo.readTask('x'))!.deleted, false);
    // The undo toast leaves on its own after 3 seconds.
    await tester.tap(find.text('Лишнее дело'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Задача удалена'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Задача удалена'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });

  testWidgets('right click on a sidebar list offers rename and delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    const home = '6f0c2a54-4b9e-4f6b-9a51-0d3c7e1a2b01';
    await repo.execute(TaskCommand.createList(home, 'Дом'));
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    await tester.pumpWidget(MaterialApp(home: TaskHome(controller: c)));
    await tester.pumpAndSettle();
    // No «…» button on list rows any more.
    expect(find.byTooltip('Действия со списком'), findsNothing);
    await tester.tap(find.text('Дом'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Переименовать'), findsOneWidget);
    await tester.tap(find.text('Удалить список'));
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });
}
