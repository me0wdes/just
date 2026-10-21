import 'package:uuid/uuid.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

import 'models.dart';
import 'validation.dart';

const taskSnapshotFields = {
  'id',
  'title',
  'note',
  'listId',
  'listIds',
  'dueDate',
  'dueTime',
  'plannedForDate',
  'reminderAtUtc',
  'reminderTimezone',
  'recurrenceRuleId',
  'occurrenceDate',
  'position',
  'deletedAt',
  'completedAt',
  'completionId',
  'successorId',
};
const listSnapshotFields = {
  'id',
  'name',
  'color',
  'icon',
  'position',
  'deletedAt',
};
const ruleSnapshotFields = {
  'id',
  'frequency',
  'weekdays',
  'monthDay',
  'timezone',
  'reminderTime',
  'active',
  'deletedAt',
};
Set<String> snapshotFields(String type) => switch (type) {
  'task' => taskSnapshotFields,
  'list' => listSnapshotFields,
  'rule' => ruleSnapshotFields,
  _ => throw const FormatException('Неизвестный тип записи'),
};
bool _zonesReady = false;
void validateZone(Object? value) {
  if (!_zonesReady) {
    tzdata.initializeTimeZones();
    _zonesReady = true;
  }
  if (value is! String) throw const FormatException('Неверный часовой пояс');
  try {
    tz.getLocation(value);
  } catch (_) {
    throw const FormatException('Неверный часовой пояс');
  }
}

void validateUtc(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d\d-\d\dT(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,9})?Z$',
      ).hasMatch(value)) {
    throw const FormatException('Неверное время UTC');
  }
  LocalDate.parse(value.substring(0, 10));
}

void validateListIds(Object? v) {
  if (v is! List ||
      v.length > 50 ||
      v.toSet().length != v.length ||
      v.any((id) => id is! String || !Uuid.isValidUUID(fromString: id))) {
    throw const FormatException('Неверные списки');
  }
}

Map<String, Object?> validateSnapshot(String type, Map<String, Object?> value) {
  final allowed = snapshotFields(type), out = Map<String, Object?>.of(value);
  if (value.keys.any((k) => !allowed.contains(k))) {
    throw const FormatException('Неизвестное поле записи');
  }
  for (final entry in value.entries) {
    final k = entry.key, v = entry.value;
    if ([
          'id',
          'listId',
          'recurrenceRuleId',
          'completionId',
          'successorId',
        ].contains(k) &&
        (v != null || k == 'id')) {
      if (v is! String || !Uuid.isValidUUID(fromString: v)) {
        throw const FormatException('Неверная ссылка');
      }
    } else if (k == 'icon') {
      if (v is! String || !RegExp(r'^[a-z]{1,20}$').hasMatch(v)) {
        throw const FormatException('Неверная иконка');
      }
    } else if (k == 'listIds') {
      validateListIds(v);
    } else if (['title', 'name'].contains(k)) {
      if (v is! String) throw const FormatException('Неверное название');
      out[k] = normalizeTitle(v);
    } else if (k == 'note') {
      if (v is! String) throw const FormatException('Неверная заметка');
      validateNote(v);
    } else if (['dueDate', 'plannedForDate', 'occurrenceDate'].contains(k) &&
        v != null) {
      if (v is! String) throw const FormatException('Неверная дата');
      LocalDate.parse(v);
    } else if (['reminderAtUtc', 'completedAt', 'deletedAt'].contains(k) &&
        v != null) {
      validateUtc(v);
    } else if (['timezone', 'reminderTimezone'].contains(k) && v != null) {
      validateZone(v);
    } else if (k == 'position') {
      if (v is! num || !v.isFinite || v.abs() > 9007199254740991) {
        throw const FormatException('Неверный порядок');
      }
    } else if (k == 'color') {
      if (v is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) {
        throw const FormatException('Неверный цвет');
      }
    } else if (k == 'frequency' &&
        !['daily', 'weekly', 'monthly'].contains(v)) {
      throw const FormatException('Неверный повтор');
    } else if (k == 'weekdays') {
      if (v is! List ||
          v.isEmpty ||
          v.length > 7 ||
          v.any((d) => d is! int || d < 1 || d > 7) ||
          v.toSet().length != v.length) {
        throw const FormatException('Неверные дни недели');
      }
    } else if (k == 'monthDay' && (v is! int || v < 1 || v > 31)) {
      throw const FormatException('Неверный день месяца');
    } else if (k == 'active' && v is! bool) {
      throw const FormatException('Неверное состояние повтора');
    } else if (['reminderTime', 'dueTime'].contains(k) &&
        v != null &&
        (v is! String || !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(v))) {
      throw const FormatException('Неверное время');
    }
  }
  if (!out.containsKey('id')) throw const FormatException('Нет id записи');
  if (type == 'task' && out['title'] is! String ||
      type == 'list' && out['name'] is! String) {
    throw const FormatException('Нет названия');
  }
  if (type == 'rule') {
    validateZone(out['timezone']);
    RecurrenceRule.fromJson(out);
  }
  return out;
}
