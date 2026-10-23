import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/task_home.dart';
import 'package:day_planner/platform/feedback_service.dart';
import 'package:day_planner/domain/models.dart';

void main() {
  testWidgets('Ctrl N focuses task entry', (
    tester,
  ) async {
    final db = AppDatabase.memory(workspaceId: 'local');
    final controller = TaskController(
      SqliteTaskRepository(db),
      feedback: const SilentCompletionFeedback(),
      today: LocalDate.today,
    );
    await tester.pumpWidget(
      MaterialApp(home: TaskHome(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('task-title-input')))
          .focusNode!
          .hasFocus,
      true,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await db.close();
  });
}
