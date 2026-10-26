import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/greeting_header.dart';
import 'package:day_planner/features/tasks/task_home.dart';
import 'package:day_planner/platform/feedback_service.dart';

void main() {
  testWidgets(
    'week header above tasks stays readable at large text without motion',
    (tester) async {
      final db = AppDatabase.memory(workspaceId: 'local');
      final c = TaskController(
        SqliteTaskRepository(db),
        feedback: const SilentCompletionFeedback(),
        today: () => LocalDate.parse('2026-10-19'),
        clock: () => DateTime(2026, 10, 19, 13),
      );
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(1.5),
            ),
            child: TaskHome(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final island = find.text('Сегодня, 19 октября', findRichText: true);
      expect(island, findsOneWidget);
      expect(
        tester.getTopLeft(island).dy,
        lessThan(tester.getTopLeft(find.text('Активные')).dy),
      );
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
    },
  );
  test('header field follows the time of day', () {
    expect(FlowPalette.forHour(4), FlowPalette.roseGold);
    expect(FlowPalette.forHour(11), FlowPalette.roseGold);
    expect(FlowPalette.forHour(12), FlowPalette.blueSky);
    expect(FlowPalette.forHour(18), FlowPalette.blueSky);
    expect(FlowPalette.forHour(19), FlowPalette.night);
    expect(FlowPalette.forHour(3), FlowPalette.night);
  });
}
