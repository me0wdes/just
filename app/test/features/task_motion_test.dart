import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/features/tasks/task_row.dart';
import 'package:day_planner/domain/models.dart';

void main() {
  testWidgets(
    'reduced motion resolves task state without a running transition',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final task = TaskItem.fromJson({
        'id': 'motion',
        'title': 'Прочитать',
        'completedAt': '2026-10-19T00:00:00Z',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: TaskRow(task: task, onToggle: () {}, onOpen: () {}),
          ),
        ),
      );
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.bySemanticsLabel(RegExp('Вернуть задачу')), findsWidgets);
      semantics.dispose();
    },
  );
}
