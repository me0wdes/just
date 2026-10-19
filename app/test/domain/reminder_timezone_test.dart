import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/domain/recurrence.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  test('recurring reminder retains local time across DST', () {
    final rule = RecurrenceRule(
      id: 'zone',
      frequency: 'daily',
      timezone: 'America/New_York',
      reminderTime: '09:00',
    );
    expect(
      nextReminderAt(rule, LocalDate.parse('2026-03-07'))!.toIso8601String(),
      '2026-03-07T14:00:00.000Z',
    );
    expect(
      nextReminderAt(rule, LocalDate.parse('2026-03-08'))!.toIso8601String(),
      '2026-03-08T13:00:00.000Z',
    );
    final moscow = RecurrenceRule(
      id: 'zone',
      frequency: 'daily',
      timezone: 'Europe/Moscow',
      reminderTime: '09:00',
    );
    expect(
      nextReminderAt(moscow, LocalDate.parse('2026-10-20'))!.toIso8601String(),
      '2026-10-20T06:00:00.000Z',
    );
  });
}
