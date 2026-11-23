import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/features/tasks/beam_border.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/task_home.dart';
import 'package:day_planner/features/tasks/task_row.dart';
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

  testWidgets('card menu moves the task to another list', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    const home = '6f0c2a54-4b9e-4f6b-9a51-0d3c7e1a2b01';
    await repo.execute(TaskCommand.createList(home, 'Дом'));
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
    await tester.tap(find.text('Сменить список'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дом').last);
    await tester.pumpAndSettle();
    expect((await repo.readTask('x'))!.listIds, [home]);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });

  testWidgets('overdue tasks sit apart under «Просроченные» in Сегодня', (
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
        id: 'old',
        title: 'Старое дело',
        listId: inboxId,
        fields: {'dueDate': '2026-10-17'},
      ),
    );
    await repo.execute(
      TaskCommand.createTask(
        id: 'new',
        title: 'Новое дело',
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
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(find.text('Просроченные'), findsOneWidget);
    expect(y('Новое дело') < y('Просроченные'), true);
    expect(y('Просроченные') < y('Старое дело'), true);
    // Only the day's own card carries the comet, and opening it ends it.
    expect(find.byType(BeamBorder), findsOneWidget);
    await tester.tap(find.text('Новое дело'));
    await tester.pumpAndSettle();
    expect(find.byType(BeamBorder), findsNothing);
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
    expect(find.text('Изменить'), findsOneWidget);
    await tester.tap(find.text('Удалить список'));
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });

  testWidgets('list icon changes from the menu and on creation', (
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
    await tester.tap(find.text('Дом'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сменить иконку'));
    await tester.pumpAndSettle();
    expect(find.text('Иконка списка'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('list-icon-home')));
    await tester.pumpAndSettle();
    expect(c.lists.firstWhere((l) => l.id == home).icon, 'home');
    // A new list gets its icon in the same dialog as its name.
    await tester.tap(find.text('Новый список'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Покупки');
    await tester.tap(find.byKey(const ValueKey('list-icon-cart')));
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();
    expect(c.lists.firstWhere((l) => l.name == 'Покупки').icon, 'cart');
    // …and its colour: the dialog offers the palette.
    await tester.tap(find.text('Новый список'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Здоровье');
    await tester.tap(find.byKey(const ValueKey('list-color-#F59E40')));
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();
    expect(
      c.lists.firstWhere((l) => l.name == 'Здоровье').color.toUpperCase(),
      '#F59E40',
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });

  testWidgets('«Предстоящие» puts every day under its own heading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    for (final (id, title, day) in [
      ('a', 'Давнее дело', '2026-10-17'),
      ('b', 'Дело на сегодня', '2026-10-19'),
      ('c', 'Дело на завтра', '2026-10-20'),
    ]) {
      await repo.execute(
        TaskCommand.createTask(
          id: id,
          title: title,
          listId: inboxId,
          fields: {'dueDate': day},
        ),
      );
    }
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    await tester.pumpWidget(MaterialApp(home: TaskHome(controller: c)));
    await tester.pumpAndSettle();
    c.navigate(TaskView.all);
    await tester.pumpAndSettle();
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(find.textContaining('Просроченные'), findsOneWidget);
    expect(find.textContaining('Сегодня'), findsWidgets);
    expect(find.textContaining('Завтра'), findsOneWidget);
    expect(y('Давнее дело') < y('Дело на сегодня'), true);
    expect(y('Дело на сегодня') < y('Дело на завтра'), true);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });

  testWidgets('an event shows a dot instead of a check', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    await repo.execute(
      TaskCommand.createTask(
        id: 'e',
        title: 'Созвон с Аней',
        listId: inboxId,
        fields: {'kind': 'event', 'dueDate': '2026-10-19', 'dueTime': '19:00'},
      ),
    );
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    await tester.pumpWidget(MaterialApp(home: TaskHome(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('Созвон с Аней'), findsOneWidget);
    expect(find.byType(EventDot), findsOneWidget);
    expect(find.byType(CheckCircle), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });
}
