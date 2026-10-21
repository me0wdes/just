import '../../theme/controls.dart';
import '../../theme/day_icon.dart';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../theme/motion_tokens.dart';

import 'package:flutter_timezone/flutter_timezone.dart';

import '../../domain/models.dart';
import '../../platform/feedback_service.dart';
import '../../theme/app_theme.dart';
import 'task_controller.dart';
import 'task_row.dart' show dueLabel;

class TaskDetailPanel extends StatefulWidget {
  final TaskItem task;
  final TaskController controller;
  final VoidCallback onClose;
  final Future<bool> Function()? onRequestReminder;
  const TaskDetailPanel({
    super.key,
    required this.task,
    required this.controller,
    required this.onClose,
    this.onRequestReminder,
  });
  @override
  State<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

bool _same(Object? a, Object? b) =>
    a is List && b is List ? listEquals(a, b) : a == b;

class _TaskDetailPanelState extends State<TaskDetailPanel> {
  late TextEditingController title, note;
  String? due, frequency;
  Set<String> listIds = {};
  String? reminderZone;
  DateTime? reminder;
  String? error;
  bool busy = false;
  bool repeatTouched = false, plannedToday = false;
  Set<int> weekdays = {};
  late Map<String, Object?> baseline;
  int loadGeneration = 0;
  Map<String, Object?> draft() => {
    'title': title.text,
    'note': note.text,
    'dueDate': due,
    // Sorted so the same set always compares equal against the baseline.
    'listIds': (listIds.toList()..sort()),
    'plannedForDate': plannedToday
        ? widget.controller.today().toString()
        : null,
    'reminderAtUtc': reminder?.toUtc().toIso8601String(),
    'reminderTimezone': reminder == null ? null : reminderZone,
  };
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final generation = ++loadGeneration;
    repeatTouched = false;
    frequency = null;
    title = TextEditingController(text: widget.task.title);
    note = TextEditingController(text: widget.task.note);
    due = widget.task.dueDate?.toString();
    listIds = {...widget.task.listIds};
    reminder = widget.task.reminderAtUtc;
    reminderZone = widget.task.reminderTimezone;
    plannedToday = widget.task.plannedForDate == widget.controller.today();
    weekdays = {(widget.task.dueDate ?? widget.controller.today()).utc.weekday};
    baseline = draft();
    final ruleId = widget.task.recurrenceRuleId;
    if (ruleId != null) {
      widget.controller.repository.readRule(ruleId).then((rule) {
        if (mounted &&
            generation == loadGeneration &&
            !repeatTouched &&
            rule != null) {
          setState(() {
            frequency = rule.frequency;
            weekdays = rule.weekdays.toSet();
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant TaskDetailPanel old) {
    super.didUpdateWidget(old);
    if (old.task.id != widget.task.id) {
      title.dispose();
      note.dispose();
      load();
    }
  }

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    super.dispose();
  }

  Future<DateTime?> date() async => showDatePicker(
    context: context,
    initialDate: DateTime.tryParse(due ?? '') ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final changes = {
        for (final entry in draft().entries)
          if (!_same(entry.value, baseline[entry.key])) entry.key: entry.value,
      };
      if (changes.isNotEmpty) {
        await widget.controller.patchTask(widget.task.id, changes);
      }
      final reminderChanged =
          changes.containsKey('reminderAtUtc') ||
          changes.containsKey('reminderTimezone');
      final current = await widget.controller.repository.readTask(
        widget.task.id,
      );
      if (current != null &&
          (repeatTouched ||
              (reminderChanged && current.recurrenceRuleId != null))) {
        final existing = current.recurrenceRuleId == null
            ? null
            : await widget.controller.repository.readRule(
                current.recurrenceRuleId!,
              );
        await widget.controller.setRecurrence(
          current,
          repeatTouched
              ? (frequency == 'none' ? null : frequency)
              : existing?.frequency,
          weekdays: repeatTouched ? (weekdays.toList()..sort()) : null,
        );
      }
      if (mounted) widget.onClose();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Не удалось сохранить изменения',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickReminder() async {
    if (widget.onRequestReminder != null &&
        !await widget.onRequestReminder!()) {
      return;
    }
    if (!mounted) return;
    final day = await date();
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    if (!mounted) return;
    reminderZone = zone;
    setState(
      () => reminder = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ).toUtc(),
    );
  }

  Future<void> delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = widget.controller, id = widget.task.id;
    await controller.deleteTask(id);
    if (mounted) widget.onClose();
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          persist: false,
          duration: MotionTokens.toast,
          content: const Text('Задача удалена'),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () => controller.restoreTask(id),
          ),
        ),
      );
    }
  }

  /// One property line: icon and label on the left, the control on the
  /// right, every row on the 36px control height.
  Widget prop(DayGlyph icon, String label, Widget control) {
    final c = DayColors.of(context);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          DayIcon(icon, size: 18, color: c.icon),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: c.muted),
            ),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: control),
          ),
        ],
      ),
    );
  }

  /// A value that opens a picker, with a clear button once it is set.
  Widget valueButton(
    String? value,
    String empty,
    VoidCallback onTap,
    VoidCallback onClear,
  ) {
    final c = DayColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: DayButton(
            onPressed: onTap,
            kind: DayButtonKind.ghost,
            sound: UiSound.open,
            padding: 10,
            label: Text(
              value ?? empty,
              style: TextStyle(
                color: value == null ? c.muted : c.text,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
        if (value != null)
          DayButton.icon(
            tooltip: 'Убрать',
            onPressed: onClear,
            icon: DayIcon(DayGlyph.close, size: 16, color: c.muted),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final theme = Theme.of(context);
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    final reminderLabel = reminder == null
        ? null
        : '${MaterialLocalizations.of(context).formatMediumDate(reminder!.toLocal())}, '
              '${TimeOfDay.fromDateTime(reminder!.toLocal()).format(context)}';
    final failure = widget.controller.reminderFailures[widget.task.id];
    return Material(
      color: c.screen,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Детали задачи',
                      style: theme.textTheme.titleMedium!.copyWith(
                        color: c.text,
                      ),
                    ),
                  ),
                  DayButton.icon(
                    tooltip: 'Закрыть',
                    sound: null,
                    onPressed: widget.onClose,
                    icon: DayIcon(DayGlyph.close, size: 18, color: c.text),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                children: [
                  DayField(
                    controller: title,
                    hint: 'Название',
                    maxLength: 500,
                    maxLines: 3,
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: c.text,
                      fontSize: 20,
                      height: 26 / 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  DayField(
                    controller: note,
                    hint: 'Заметка',
                    maxLength: 10000,
                    minLines: 2,
                    maxLines: 8,
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        prop(
                          DayGlyph.list,
                          'Списки',
                          DayCombobox(
                            selected: listIds,
                            items: [
                              for (final list in widget.controller.lists)
                                if (list.id != inboxId)
                                  DaySelectItem(list.id, list.name),
                            ],
                            onChanged: (v) => setState(() => listIds = v),
                            onCreate: widget.controller.createList,
                          ),
                        ),
                        prop(
                          DayGlyph.clock,
                          'Срок',
                          valueButton(
                            due == null
                                ? null
                                : dueLabel(
                                    LocalDate.parse(due!),
                                    widget.controller.today(),
                                  ),
                            'Добавить',
                            () async {
                              final selected = await date();
                              if (selected != null && mounted) {
                                setState(
                                  () => due = selected
                                      .toIso8601String()
                                      .substring(0, 10),
                                );
                              }
                            },
                            () => setState(() => due = null),
                          ),
                        ),
                        prop(
                          DayGlyph.repeat,
                          'Повтор',
                          DaySelect<String>(
                            key: ValueKey('repeat-$frequency'),
                            value: frequency ?? 'none',
                            items: const [
                              DaySelectItem('none', 'Без повтора'),
                              DaySelectItem('daily', 'Каждый день'),
                              DaySelectItem('weekly', 'Каждую неделю'),
                              DaySelectItem('monthly', 'Каждый месяц'),
                            ],
                            onChanged: (v) => setState(() {
                              repeatTouched = true;
                              frequency = v;
                              if (v == 'weekly' && weekdays.isEmpty) {
                                weekdays = {
                                  (widget.task.dueDate ??
                                          widget.controller.today())
                                      .utc
                                      .weekday,
                                };
                              }
                            }),
                          ),
                        ),
                        if (frequency == 'weekly')
                          Padding(
                            padding: const EdgeInsets.only(left: 28, bottom: 8),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (var day = 1; day <= 7; day++)
                                  _DayToggle(
                                    label: days[day - 1],
                                    selected: weekdays.contains(day),
                                    onTap: () => setState(() {
                                      repeatTouched = true;
                                      weekdays.contains(day)
                                          ? weekdays.remove(day)
                                          : weekdays.add(day);
                                    }),
                                  ),
                              ],
                            ),
                          ),
                        prop(
                          DayGlyph.bell,
                          'Напомнить',
                          valueButton(
                            reminderLabel,
                            'Добавить',
                            pickReminder,
                            () => setState(() => reminder = null),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (failure != null || error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: Text(
                        error ?? failure!,
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: c.overdue,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(color: c.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              child: Row(
                children: [
                  // Flexible so large text shortens the label, not the layout.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DayButton(
                        kind: DayButtonKind.ghost,
                        destructive: true,
                        sound: UiSound.delete,
                        onPressed: delete,
                        icon: DayIcon(
                          DayGlyph.delete,
                          size: 18,
                          color: c.overdue,
                        ),
                        label: const Text('Удалить задачу'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DayButton(
                    onPressed: busy ? null : save,
                    label: const Text('Сохранить'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Weekday pill: ink when chosen, a quiet tint otherwise.
class _DayToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    child: DayButton(
      onPressed: onTap,
      kind: selected ? DayButtonKind.primary : DayButtonKind.secondary,
      label: Text(label),
      sound: selected ? UiSound.toggleOff : UiSound.toggleOn,
    ),
  );
}
