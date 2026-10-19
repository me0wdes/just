const inboxId = '00000000-0000-4000-8000-000000000001';

class LocalDate implements Comparable<LocalDate> {
  final String value;
  const LocalDate._(this.value);
  factory LocalDate.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Неверная дата');
    }
    final parsed = DateTime.tryParse('${value}T00:00:00Z');
    if (parsed == null ||
        parsed.year < 1 ||
        parsed.toIso8601String().substring(0, 10) != value) {
      throw const FormatException('Неверная дата');
    }
    return LocalDate._(value);
  }
  factory LocalDate.today() =>
      LocalDate.parse(DateTime.now().toIso8601String().substring(0, 10));
  DateTime get utc => DateTime.parse('${value}T00:00:00Z');
  @override
  int compareTo(LocalDate other) => value.compareTo(other.value);
  @override
  String toString() => value;
  @override
  bool operator ==(Object other) => other is LocalDate && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

class TaskItem {
  final Map<String, Object?> _data;
  TaskItem.fromJson(Map<String, Object?> data)
    : _data = Map.unmodifiable({...data});
  String get id => _data['id'] as String;
  String get title => _data['title'] as String;
  String get note => _data['note'] as String? ?? '';
  String get listId => _data['listId'] as String? ?? inboxId;

  /// Lists work like labels: none, one or several. Older records only
  /// carry `listId`; there the inbox means "no list".
  List<String> get listIds {
    final ids = _data['listIds'];
    if (ids is List) return ids.cast<String>();
    return listId == inboxId ? const [] : [listId];
  }

  LocalDate? get dueDate => _date('dueDate');
  LocalDate? get plannedForDate => _date('plannedForDate');
  LocalDate? get occurrenceDate => _date('occurrenceDate');
  LocalDate? _date(String field) =>
      _data[field] == null ? null : LocalDate.parse(_data[field] as String);
  DateTime? get reminderAtUtc => _data['reminderAtUtc'] == null
      ? null
      : DateTime.parse(_data['reminderAtUtc'] as String);
  String? get reminderTimezone => _data['reminderTimezone'] as String?;
  String? get recurrenceRuleId => _data['recurrenceRuleId'] as String?;
  String? get completionId => _data['completionId'] as String?;
  String? get successorId => _data['successorId'] as String?;
  bool get completed => _data['completedAt'] != null;
  bool get deleted => _data['deletedAt'] != null;
  double get position => (_data['position'] as num? ?? 0).toDouble();
  Map<String, Object?> toJson() => Map.of(_data);
}

class TaskList {
  final Map<String, Object?> _data;
  TaskList.fromJson(Map<String, Object?> data)
    : _data = Map.unmodifiable({...data});
  String get id => _data['id'] as String;
  String get name => _data['name'] as String;
  String get color => _data['color'] as String? ?? '#8C9B7A';
  bool get deleted => _data['deletedAt'] != null;
  double get position => (_data['position'] as num? ?? 0).toDouble();
  Map<String, Object?> toJson() => Map.of(_data);
}

class RecurrenceRule {
  final String id, frequency, timezone;
  final List<int> weekdays;
  final int? monthDay;
  final bool active;
  final String? reminderTime;
  RecurrenceRule({
    required this.id,
    required this.frequency,
    required this.timezone,
    List<int> weekdays = const [],
    this.monthDay,
    this.active = true,
    this.reminderTime,
  }) : weekdays = List.unmodifiable(weekdays) {
    if (!['daily', 'weekly', 'monthly'].contains(frequency)) {
      throw const FormatException('Неверный повтор');
    }
    if (frequency == 'weekly' &&
        (weekdays.isEmpty || weekdays.any((d) => d < 1 || d > 7))) {
      throw const FormatException('Неверные дни недели');
    }
    if (frequency == 'monthly' &&
        (monthDay == null || monthDay! < 1 || monthDay! > 31)) {
      throw const FormatException('Неверный день месяца');
    }
  }
  factory RecurrenceRule.fromJson(Map<String, Object?> d) => RecurrenceRule(
    id: d['id'] as String,
    frequency: d['frequency'] as String,
    timezone: d['timezone'] as String,
    weekdays: (d['weekdays'] as List? ?? []).cast<int>(),
    monthDay: d['monthDay'] as int?,
    active: d['active'] as bool? ?? true,
    reminderTime: d['reminderTime'] as String?,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'frequency': frequency,
    'timezone': timezone,
    if (frequency == 'weekly') 'weekdays': weekdays,
    if (frequency == 'monthly') 'monthDay': monthDay,
    'active': active,
    'reminderTime': reminderTime,
  };
}

enum TaskView { today, all, list }

class TaskQuery {
  final TaskView view;
  final String? listId;
  final LocalDate today;
  final String search;
  final bool includeCompleted;
  const TaskQuery({
    required this.today,
    this.view = TaskView.today,
    this.listId,
    this.search = '',
    this.includeCompleted = false,
  });
  bool matches(TaskItem task) {
    if (task.deleted || (!includeCompleted && task.completed)) return false;
    // The inbox entry now reads «Без списка»: tasks with no list at all.
    if (view == TaskView.list &&
        !(listId == inboxId
            ? task.listIds.isEmpty
            : task.listIds.contains(listId))) {
      return false;
    }
    if (view == TaskView.today &&
        !((task.dueDate != null && task.dueDate!.compareTo(today) <= 0) ||
            task.plannedForDate == today)) {
      return false;
    }
    final needle = search.trim().toLowerCase();
    return needle.isEmpty ||
        '${task.title}\n${task.note}'.toLowerCase().contains(needle);
  }
}

class CommandReceipt {
  final String operationId;
  final String? completionId, provisionalSuccessorId;
  const CommandReceipt(
    this.operationId, {
    this.completionId,
    this.provisionalSuccessorId,
  });
}
