import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/sync/protocol.dart';
import 'package:day_planner/features/tasks/task_controller.dart';
import 'package:day_planner/features/tasks/task_home.dart';
import 'package:day_planner/features/tasks/task_row.dart';
import 'package:day_planner/platform/feedback_service.dart';

void main() {
  testWidgets('1000 real tasks build only visible rows and search notes', (
    tester,
  ) async {
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    await repo.applySyncResponse(
      SyncResponse(
        workspaceId: 'remote',
        acknowledgements: [],
        changes: [
          for (var i = 0; i < 1000; i++)
            EntityChange.fromJson({
              'entityType': 'task',
              'entityId': 'task-$i',
              'revision': i + 1,
              'value': {
                'id': 'task-$i',
                'title': 'Дело $i',
                'position': i * 1024,
                'plannedForDate': '2026-10-19',
                'note': i == 999 ? 'Найти по заметке' : '',
              },
            }),
        ],
        nextCursor: 1000,
        hasMore: false,
      ),
    );
    final c = TaskController(
      repo,
      feedback: const SilentCompletionFeedback(),
      today: () => LocalDate.parse('2026-10-19'),
    );
    await tester.pumpWidget(MaterialApp(home: TaskHome(controller: c)));
    await tester.pumpAndSettle();
    expect(find.byType(TaskRow).evaluate().length, lessThan(30));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('task-search-input')),
      'Найти по заметке',
    );
    await tester.pumpAndSettle();
    expect(find.text('Дело 999'), findsOneWidget);
    expect(find.text('Дело 0'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });
}
