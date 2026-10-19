import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/domain/models.dart';

void main() {
  const home = '6f0c2a54-4b9e-4f6b-9a51-0d3c7e1a2b01';
  final today = LocalDate.parse('2026-10-19');
  TaskItem task(Map<String, Object?> fields) =>
      TaskItem.fromJson({'id': 'x', 'title': 'Т', ...fields});

  test('old records keep their single list, inbox means no list', () {
    expect(task({'listId': home}).listIds, [home]);
    expect(task({'listId': inboxId}).listIds, isEmpty);
    expect(task({'listId': home, 'listIds': <String>[]}).listIds, isEmpty);
  });

  test('a list view matches any of the task lists; inbox shows unlisted', () {
    final both = task({
      'listIds': [home, inboxId == home ? '' : 'b'],
    });
    final none = task({'listIds': <String>[]});
    final inHome = TaskQuery(today: today, view: TaskView.list, listId: home);
    final noList = TaskQuery(
      today: today,
      view: TaskView.list,
      listId: inboxId,
    );
    expect(inHome.matches(both), isTrue);
    expect(inHome.matches(none), isFalse);
    expect(noList.matches(none), isTrue);
    expect(noList.matches(both), isFalse);
  });
}
