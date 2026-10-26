import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/task_home.dart';
import 'package:day_planner/platform/feedback_service.dart';

void main() {
  testWidgets('week calendar picks a day and opens the next week', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    // Monday 19 October 2026.
    Future<void> task(String title, String due) => repo.execute(
      TaskCommand.createTask(
        id: const Uuid().v4(),
        title: title,
        listId: inboxId,
        fields: {'dueDate': due},
      ),
    );
    await task('Сегодняшняя', '2026-10-19');
    await task('Завтрашняя', '2026-10-20');
    await task('На следующей неделе', '2026-10-27');
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    await tester.pumpWidget(MaterialApp(home: TaskHome(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('Сегодняшняя'), findsOneWidget);
    expect(find.text('Завтрашняя'), findsNothing);

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    expect(find.text('Завтрашняя'), findsOneWidget);
    expect(find.text('Сегодняшняя'), findsNothing);
    expect(find.textContaining('Завтра'), findsWidgets);

    // A task added on the picked day is due that day.
    await tester.enterText(find.byKey(const Key('task-title-input')), 'Новая');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final added = c.tasks.firstWhere((t) => t.title == 'Новая');
    expect(added.dueDate.toString(), '2026-10-20');

    // One task next week: «+1» opens it, × folds it back.
    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();
    expect(find.text('На следующей неделе'), findsOneWidget);
    await tester.tap(find.byTooltip('Свернуть неделю'));
    await tester.pumpAndSettle();
    expect(find.text('27'), findsNothing);
    expect(find.text('Сегодняшняя'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });

  testWidgets('on a phone the next week opens from a chip under the week', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    await repo.execute(
      TaskCommand.createTask(
        id: const Uuid().v4(),
        title: 'На следующей неделе',
        listId: inboxId,
        fields: {'dueDate': '2026-10-27'},
      ),
    );
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    await tester.pumpWidget(MaterialApp(home: TaskHome(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+1 на следующей неделе'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('27'));
    await tester.pumpAndSettle();
    expect(find.text('На следующей неделе'), findsWidgets);
    await tester.tap(find.text('Свернуть'));
    await tester.pumpAndSettle();
    expect(find.text('27'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });

  testWidgets('picking a day in «Все задачи» filters without leaving it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    for (final (title, due) in [
      ('Сегодня дело', '2026-10-19'),
      ('Завтра дело', '2026-10-20'),
    ]) {
      await repo.execute(
        TaskCommand.createTask(
          id: const Uuid().v4(),
          title: title,
          listId: inboxId,
          fields: {'dueDate': due},
        ),
      );
    }
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    c.navigate(TaskView.all);
    await tester.pumpWidget(MaterialApp(home: TaskHome(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20').first);
    await tester.pumpAndSettle();
    expect(c.query.view, TaskView.all);
    expect(find.text('Завтра дело'), findsOneWidget);
    expect(find.text('Сегодня дело'), findsNothing);
    await tester.tap(find.text('20').first);
    await tester.pumpAndSettle();
    expect(c.query.day, isNull);
    expect(find.text('Сегодня дело'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });

  testWidgets('on a phone a long press without moving opens the task menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    await repo.execute(
      TaskCommand.createTask(
        id: const Uuid().v4(),
        title: 'Подержать меня',
        listId: inboxId,
        fields: {'dueDate': '2026-10-19'},
      ),
    );
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    await tester.pumpWidget(MaterialApp(home: TaskHome(controller: c)));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Подержать меня'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.text('Выполнить'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });
}
