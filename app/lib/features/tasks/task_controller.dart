import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../data/task_repository.dart';
import '../../domain/models.dart';
import '../../domain/commands.dart';
import '../../platform/feedback_service.dart';

class TaskController extends ChangeNotifier {
  final TaskRepository repository;
  final CompletionFeedback feedback;
  final LocalDate Function() today;
  final DateTime Function() clock;
  late TaskQuery query;
  List<TaskItem> tasks = [];
  List<TaskList> lists = [];
  bool loading = true;
  String? error, selectedId;
  Map<String, String> reminderFailures = {};
  void setReminderFailures(Map<String, String> value) {
    reminderFailures = Map.unmodifiable(value);
    _notify();
  }

  String? _openRequest;
  void requestOpen(String id) {
    _openRequest = id;
    _notify();
  }

  String? takeOpenRequest() {
    final id = _openRequest;
    _openRequest = null;
    return id;
  }

  StreamSubscription<List<TaskItem>>? _tasks;
  StreamSubscription<List<TaskList>>? _lists;
  StreamSubscription<List<TaskItem>>? _calendar;
  List<TaskItem> calendar = [];

  /// The day the «Сегодня» view shows.
  LocalDate get day => query.day ?? today();

  /// Open tasks on [date] in the current view (a list keeps its own).
  int countOn(LocalDate date) => calendar.where((t) {
    if (!TaskQuery.onDay(t, date, today())) return false;
    if (query.view != TaskView.list) return true;
    return query.listId == inboxId
        ? t.listIds.isEmpty
        : t.listIds.contains(query.listId);
  }).length;

  /// Picks a day in the calendar and stays in the current view. In
  /// «Сегодня» today means no filter; elsewhere the same day again clears it.
  void selectDay(LocalDate date) {
    selectedId = null;
    final clear = query.view == TaskView.today
        ? date == today()
        : date == query.day;
    setQuery(
      TaskQuery(
        view: query.view,
        listId: query.listId,
        today: today(),
        day: clear ? null : date,
        includeCompleted: true,
      ),
    );
  }

  bool _disposed = false;
  TaskController(
    this.repository, {
    required this.feedback,
    required this.today,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    query = TaskQuery(today: today(), includeCompleted: true);
    setQuery(query);
    // Open tasks of every day, for the dots under the week calendar.
    _calendar = repository
        .watchTasks(TaskQuery(view: TaskView.all, today: today()))
        .listen((value) {
          calendar = value;
          _notify();
        }, onError: _onError);
    _lists = repository.watchLists().listen((value) {
      lists = value;
      _notify();
    }, onError: _onError);
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onError(Object e) {
    error = 'Не удалось прочитать локальные данные';
    loading = false;
    _notify();
  }

  void setQuery(TaskQuery value) {
    query = value;
    loading = true;
    _tasks?.cancel();
    _tasks = repository.watchTasks(query).listen((value) {
      tasks = value;
      loading = false;
      _notify();
    }, onError: _onError);
    _notify();
  }

  void select(String? id) {
    selectedId = id;
    _notify();
  }

  TaskItem? get selected => tasks.where((t) => t.id == selectedId).firstOrNull;
  String get heading => switch (query.view) {
    TaskView.today => 'Сегодня',
    TaskView.all => 'Все задачи',
    TaskView.list =>
      lists.where((l) => l.id == query.listId).map(listTitle).firstOrNull ??
          'Список',
  };
  void navigate(TaskView view, {String? listId}) {
    selectedId = null;
    setQuery(
      TaskQuery(
        view: view,
        listId: listId,
        today: today(),
        includeCompleted: true,
      ),
    );
  }

  Future<CommandReceipt> addTask(String title) => repository.execute(
    TaskCommand.createTask(
      id: const Uuid().v4(),
      title: title,
      listId: inboxId,
      fields: {
        if (query.view == TaskView.list && query.listId != inboxId)
          'listIds': [query.listId!],
        'position': tasks.isEmpty
            ? 1024
            : tasks.map((t) => t.position).reduce((a, b) => a > b ? a : b) +
                  1024,
        // A task added while a day is shown is due on that day.
        if (query.view == TaskView.today || query.day != null)
          'dueDate': day.toString(),
      },
    ),
  );
  Future<CommandReceipt> patchTask(String id, Map<String, Object?> changes) =>
      repository.execute(TaskCommand.patchTask(id, changes));
  Future<CommandReceipt> completeTask(String id) async {
    final task = await repository.readTask(id);
    final rule = task?.recurrenceRuleId == null
        ? null
        : await repository.readRule(task!.recurrenceRuleId!);
    final date = rule == null
        ? today().toString()
        : tz.TZDateTime.from(
            clock().toUtc(),
            tz.getLocation(rule.timezone),
          ).toIso8601String().substring(0, 10);
    final result = await repository.execute(TaskCommand.completeTask(id, date));
    unawaited(feedback.onUserCompletion(undo: false).catchError((Object _) {}));
    return result;
  }

  Future<CommandReceipt> undoCompletion(String id, String completionId) async {
    final result = await repository.execute(
      TaskCommand.undoCompletion(id, completionId),
    );
    unawaited(feedback.onUserCompletion(undo: true).catchError((Object _) {}));
    return result;
  }

  Future<CommandReceipt> deleteTask(String id) =>
      repository.execute(TaskCommand.deleteTask(id));
  Future<CommandReceipt> restoreTask(String id) =>
      repository.execute(TaskCommand.restoreTask(id));
  Future<CommandReceipt> saveList(String? id, String name, {String? icon}) =>
      repository.execute(
        id == null
            ? TaskCommand.createList(const Uuid().v4(), name, icon: icon)
            : TaskCommand.patchList(id, {'name': name, 'icon': ?icon}),
      );
  Future<CommandReceipt> setListIcon(String id, String icon) =>
      repository.execute(TaskCommand.patchList(id, {'icon': icon}));

  /// Creates a list and returns its id, for the combobox «Создать».
  Future<String> createList(String name) async {
    final id = const Uuid().v4();
    await repository.execute(TaskCommand.createList(id, name));
    return id;
  }

  /// The inbox entry is shown as the bucket for tasks with no list.
  static String listTitle(TaskList list) =>
      list.id == inboxId ? 'Без списка' : list.name;

  Future<CommandReceipt> deleteList(String id) =>
      repository.execute(TaskCommand.deleteList(id));
  Future<CommandReceipt> reorderTask(String id, double position) =>
      repository.execute(TaskCommand.reorderTask(id, position));
  Future<void> setRecurrence(
    TaskItem task,
    String? frequency, {
    String? timezone,
    List<int>? weekdays,
    int? monthDay,
  }) async {
    if (frequency == null) {
      await patchTask(task.id, {'recurrenceRuleId': null});
      return;
    }
    final id = task.recurrenceRuleId ?? const Uuid().v4();
    final existing = task.recurrenceRuleId == null
        ? null
        : await repository.readRule(task.recurrenceRuleId!);
    final date = task.dueDate ?? today();
    final zone =
        timezone ??
        task.reminderTimezone ??
        existing?.timezone ??
        'Europe/Moscow';
    final reminder = task.reminderAtUtc == null
        ? null
        : tz.TZDateTime.from(task.reminderAtUtc!, tz.getLocation(zone));
    await repository.execute(
      TaskCommand.upsertRule(id, {
        'frequency': frequency,
        'timezone': zone,
        'reminderTime': reminder == null
            ? null
            : '${reminder.hour.toString().padLeft(2, '0')}:${reminder.minute.toString().padLeft(2, '0')}',
        'active': true,
        if (frequency == 'weekly')
          'weekdays':
              weekdays ??
              (existing?.frequency == 'weekly'
                  ? existing!.weekdays
                  : [date.utc.weekday]),
        if (frequency == 'monthly')
          'monthDay':
              monthDay ??
              (existing?.frequency == 'monthly'
                  ? existing!.monthDay
                  : date.utc.day),
      }),
    );
    await patchTask(task.id, {'recurrenceRuleId': id});
  }

  @override
  void dispose() {
    _calendar?.cancel();
    _disposed = true;
    _tasks?.cancel();
    _lists?.cancel();
    super.dispose();
  }
}
