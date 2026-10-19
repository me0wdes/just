import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/commands.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/task_home.dart';
import 'package:day_planner/platform/feedback_service.dart';

// The live header field never settles, so step time instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('switching tasks keeps the detail panel open in place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    for (final (id, title) in [('a', 'Первое'), ('b', 'Второе')]) {
      await repo.execute(
        TaskCommand.createTask(
          id: id,
          title: title,
          listId: inboxId,
          fields: {'plannedForDate': '2026-10-19'},
        ),
      );
    }
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    // test/features runs with reduced motion; this test is about motion.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures();
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    await tester.pumpWidget(MaterialApp(home: TaskHome(controller: c)));
    await settle(tester);
    c.select('a');
    await settle(tester);
    final panel = tester.element(find.byKey(const ValueKey('detail')));
    c.select('b');
    await settle(tester);
    // Same panel element: no close-and-reopen, only the content changed.
    expect(tester.element(find.byKey(const ValueKey('detail'))), same(panel));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('detail')),
        matching: find.widgetWithText(TextField, 'Второе'),
      ),
      findsOneWidget,
    );
    // Closing animates too: the panel is still there mid-way, then gone.
    c.select(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('detail')), findsOneWidget);
    await settle(tester);
    expect(find.byKey(const ValueKey('detail')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });
}
