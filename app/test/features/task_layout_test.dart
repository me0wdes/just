import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/task_home.dart';
import 'package:day_planner/platform/feedback_service.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/domain/commands.dart';

void main() {
  for (final width in [360.0, 760.0, 1024.0, 1440.0]) {
    testWidgets('layout $width supports large text and keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.memory(workspaceId: 'local');
      final repo = SqliteTaskRepository(db);
      await repo.execute(
        TaskCommand.createTask(
          id: 'long',
          title: 'Длинное повседневное дело, которое нужно спокойно прочитать и выполнить',
          listId: inboxId,
          fields: {'plannedForDate': '2026-10-19'},
        ),
      );
      final controller = TaskController(
        repo,
        feedback: const SilentCompletionFeedback(),
        today: () => LocalDate.parse('2026-10-19'),
      );
      controller.reminderFailures = {
        'long': 'Не удалось поставить напоминание',
      };
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
              viewInsets: const EdgeInsets.only(bottom: 300),
            ),
            child: child!,
          ),
          home: TaskHome(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('desktop-sidebar')),
        width >= 900 ? findsOneWidget : findsNothing,
      );
      if (width >= 900) {
        expect(
          tester.getSize(find.byKey(const Key('desktop-sidebar'))).width,
          sidebarWidth,
        );
      }
      expect(find.byKey(const Key('task-title-input')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await db.close();
    });
  }
}
