import 'package:uuid/uuid.dart';
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

DateTime? nextReminderAt(RecurrenceRule rule, LocalDate date) {
  if (rule.reminderTime == null) return null;
  final parts = rule.reminderTime!.split(':').map(int.parse).toList();
  return tz.TZDateTime(
    tz.getLocation(rule.timezone),
    date.utc.year,
    date.utc.month,
    date.utc.day,
    parts[0],
    parts[1],
  ).toUtc();
}

String successorId(String ruleId, Object occurrenceDate) =>
    const Uuid().v5(ruleId, occurrenceDate.toString());
LocalDate nextOccurrence(
  RecurrenceRule rule,
  LocalDate? dueDate,
  LocalDate completionDate,
) {
  final base = dueDate != null && dueDate.compareTo(completionDate) > 0
      ? dueDate
      : completionDate;
  final date = base.utc;
  if (rule.frequency == 'monthly') {
    for (var offset = 0; offset < 3; offset++) {
      final first = DateTime.utc(date.year, date.month + offset, 1);
      final last = DateTime.utc(first.year, first.month + 1, 0).day;
      final next = LocalDate.parse(
        DateTime.utc(
          first.year,
          first.month,
          rule.monthDay!.clamp(1, last),
        ).toIso8601String().substring(0, 10),
      );
      if (next.compareTo(base) > 0) return next;
    }
  }
  for (var days = 1; days <= 7; days++) {
    final next = DateTime.utc(date.year, date.month, date.day + days);
    if (rule.frequency == 'daily' ||
        (rule.frequency == 'weekly' && rule.weekdays.contains(next.weekday))) {
      return LocalDate.parse(next.toIso8601String().substring(0, 10));
    }
  }
  throw const FormatException('Не удалось рассчитать повтор');
}
