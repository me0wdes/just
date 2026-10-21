import 'dart:async';

import '../../theme/controls.dart';
import '../../theme/day_icon.dart';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
  String? due, dueTime, frequency;
  Set<String> listIds = {};
  String? reminderZone;
  DateTime? reminder;
  String? error;
  bool repeatTouched = false, plannedToday = false;
  Set<int> weekdays = {};
  late Map<String, Object?> baseline;
  int loadGeneration = 0;
  Map<String, Object?> draft() => {
    'title': title.text,
    'note': note.text,
    'dueDate': due,
    'dueTime': due == null ? null : dueTime,
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
    title = TextEditingController(text: widget.task.title)..addListener(_typed);
    note = TextEditingController(text: widget.task.note)..addListener(_typed);
    due = widget.task.dueDate?.toString();
    dueTime = widget.task.dueTime;
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
      // Pending typing belongs to the previous task.
      flush(old.task.id);
      title.dispose();
      note.dispose();
      load();
    }
  }

  @override
  void dispose() {
    flush(widget.task.id);
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
  // Autosave: pickers save at once, typing after a short pause, and
  // anything pending is flushed when the panel closes or switches task.
  Timer? _typing;
  Future<void> _queue = Future.value();

  void _typed() {
    if (draftDiffers()) {
      _typing?.cancel();
      _typing = Timer(const Duration(milliseconds: 600), persist);
    }
  }

  bool draftDiffers() =>
      draft().entries.any((e) => !_same(e.value, baseline[e.key]));

  /// Applies a change from a picker and saves it right away.
  void change(VoidCallback update) {
    setState(update);
    persist();
  }

  void flush(String id) {
    _typing?.cancel();
    persist(id: id);
  }

  /// Saves only the fields that differ from what was last saved, in order,
  /// so quick changes never overtake each other.
  void persist({String? id}) {
    _typing?.cancel();
    final taskId = id ?? widget.task.id;
    final snapshot = draft();
    final changes = {
      for (final e in snapshot.entries)
        if (!_same(e.value, baseline[e.key])) e.key: e.value,
    };
    final repeat = repeatTouched
        ? (frequency: frequency, weekdays: weekdays.toList()..sort())
        : null;
    if (changes.isEmpty && repeat == null) return;
    baseline = {...baseline, ...changes};
    repeatTouched = false;
    final controller = widget.controller;
    _queue = _queue.then((_) async {
      try {
        if (changes.isNotEmpty) await controller.patchTask(taskId, changes);
        final reminderChanged =
            changes.containsKey('reminderAtUtc') ||
            changes.containsKey('reminderTimezone');
        final current = await controller.repository.readTask(taskId);
        if (current != null &&
            (repeat != null ||
                (reminderChanged && current.recurrenceRuleId != null))) {
          final existing = current.recurrenceRuleId == null
              ? null
              : await controller.repository.readRule(current.recurrenceRuleId!);
          await controller.setRecurrence(
            current,
            repeat != null
                ? (repeat.frequency == 'none' ? null : repeat.frequency)
                : existing?.frequency,
            weekdays: repeat?.weekdays,
          );
        }
        if (mounted && error != null) setState(() => error = null);
      } catch (e) {
        if (mounted) {
          setState(
            () => error = e is FormatException
                ? e.message
                : 'Не удалось сохранить изменения',
          );
        }
      }
    });
  }

  /// Local due moment, only when the due date has a time.
  DateTime? dueAt() {
    final time = dueTime;
    if (due == null || time == null) return null;
    final d = DateTime.parse(due!);
    return DateTime(
      d.year,
      d.month,
      d.day,
      int.parse(time.substring(0, 2)),
      int.parse(time.substring(3)),
    );
  }

  /// Reminder presets relative to the due time, in minutes before it.
  static const _before = {
    0: 'В момент срока',
    15: 'За 15 минут',
    30: 'За 30 минут',
    60: 'За 1 час',
    1440: 'За день',
  };

  /// Minutes between the reminder and the due time when they form a preset.
  int? reminderPreset() {
    final at = dueAt(), r = reminder;
    if (at == null || r == null) return null;
    final minutes = at.difference(r.toLocal()).inMinutes;
    return _before.containsKey(minutes) ? minutes : null;
  }

  /// A date, then an optional time: «Только дата» keeps the whole day.
  Future<void> pickDue() async {
    final day = await date();
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: dueTime == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay(
              hour: int.parse(dueTime!.substring(0, 2)),
              minute: int.parse(dueTime!.substring(3)),
            ),
      helpText: 'Время срока',
      cancelText: 'Только дата',
      confirmText: 'Готово',
    );
    if (!mounted) return;
    final preset = reminderPreset();
    change(() {
      due = day.toIso8601String().substring(0, 10);
      dueTime = time == null
          ? null
          : '${time.hour.toString().padLeft(2, '0')}:'
                '${time.minute.toString().padLeft(2, '0')}';
      // «За 30 минут» follows the due time when it moves.
      final at = dueAt();
      if (preset != null && at != null) {
        reminder = at.subtract(Duration(minutes: preset)).toUtc();
      }
    });
  }

  /// Asks for notification access and the time zone; null when refused.
  Future<String?> reminderAccess() async {
    if (widget.onRequestReminder != null &&
        !await widget.onRequestReminder!()) {
      return null;
    }
    return (await FlutterTimezone.getLocalTimezone()).identifier;
  }

  Future<void> remindBefore(int minutes) async {
    final zone = await reminderAccess();
    final at = dueAt();
    if (zone == null || at == null || !mounted) return;
    reminderZone = zone;
    change(() => reminder = at.subtract(Duration(minutes: minutes)).toUtc());
  }

  Future<void> pickReminder() async {
    final zone = await reminderAccess();
    if (zone == null || !mounted) return;
    final day = await date();
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    reminderZone = zone;
    change(
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
  /// One property line: icon and label on the left, the control on the
  /// right. Figma «Свойство»: hovering the row lights its icon and label.
  Widget prop(DayGlyph icon, String label, Widget control) =>
      _PropRow(icon: icon, label: label, control: control);

  /// A value that opens a picker; its clear button shows on hover, as the
  /// «Значение» hover variant in Figma.
  Widget valueButton(
    String? value,
    String empty,
    VoidCallback onTap,
    VoidCallback onClear,
  ) => _ValueButton(value: value, empty: empty, onTap: onTap, onClear: onClear);

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
                          'Список',
                          // Figma: one list per task; «Без списка» clears it.
                          DaySelect<String>(
                            value: listIds.firstOrNull ?? inboxId,
                            emptyValue: inboxId,
                            arrow: false,
                            items: [
                              for (final list in widget.controller.lists)
                                DaySelectItem(
                                  list.id,
                                  TaskController.listTitle(list),
                                ),
                            ],
                            onChanged: (id) => change(
                              () => listIds = id == inboxId ? {} : {id},
                            ),
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
                                    dueTime,
                                  ),
                            'Добавить',
                            pickDue,
                            () => change(() {
                              due = null;
                              dueTime = null;
                            }),
                          ),
                        ),
                        prop(
                          DayGlyph.repeat,
                          'Повтор',
                          DaySelect<String>(
                            key: ValueKey('repeat-$frequency'),
                            value: frequency ?? 'none',
                            emptyValue: 'none',
                            items: const [
                              DaySelectItem('none', 'Без повтора'),
                              DaySelectItem('daily', 'Каждый день'),
                              DaySelectItem('weekly', 'Каждую неделю'),
                              DaySelectItem('monthly', 'Каждый месяц'),
                            ],
                            onChanged: (v) => change(() {
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
                                    onTap: () => change(() {
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
                          // With a due time, reminders are offsets from it.
                          dueAt() == null
                              ? valueButton(
                                  reminderLabel,
                                  'Добавить',
                                  pickReminder,
                                  () => change(() => reminder = null),
                                )
                              : DaySelect<String>(
                                  key: ValueKey('remind-$reminder-$dueTime'),
                                  value: reminder == null
                                      ? 'none'
                                      : '${reminderPreset() ?? 'custom'}',
                                  emptyValue: 'none',
                                  items: [
                                    const DaySelectItem(
                                      'none',
                                      'Без напоминания',
                                    ),
                                    for (final e in _before.entries)
                                      DaySelectItem('${e.key}', e.value),
                                    DaySelectItem(
                                      'custom',
                                      reminder != null &&
                                              reminderPreset() == null
                                          ? reminderLabel!
                                          : 'Своё время',
                                    ),
                                  ],
                                  onChanged: (v) => switch (v) {
                                    'none' => change(() => reminder = null),
                                    'custom' => pickReminder(),
                                    _ => remindBefore(int.parse(v)),
                                  },
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

class _ValueButton extends StatefulWidget {
  final String? value;
  final String empty;
  final VoidCallback onTap, onClear;
  const _ValueButton({
    required this.value,
    required this.empty,
    required this.onTap,
    required this.onClear,
  });
  @override
  State<_ValueButton> createState() => _ValueButtonState();
}

class _ValueButtonState extends State<_ValueButton> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final touch = !RendererBinding.instance.mouseTracker.mouseIsConnected;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: DayButton(
              onPressed: widget.onTap,
              kind: DayButtonKind.ghost,
              sound: UiSound.open,
              padding: 10,
              label: Text(
                widget.value ?? widget.empty,
                style: TextStyle(
                  color: widget.value == null ? c.muted : c.text,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          // Without a mouse there is no hover, so the button stays visible.
          if (widget.value != null)
            AnimatedOpacity(
              opacity: hovered || touch ? 1 : 0,
              duration: MotionTokens.duration(context, MotionTokens.fast),
              child: DayButton.icon(
                tooltip: 'Убрать',
                onPressed: widget.onClear,
                icon: DayIcon(DayGlyph.close, size: 16, color: c.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _PropRow extends StatefulWidget {
  final DayGlyph icon;
  final String label;
  final Widget control;
  const _PropRow({
    required this.icon,
    required this.label,
    required this.control,
  });
  @override
  State<_PropRow> createState() => _PropRowState();
}

class _PropRowState extends State<_PropRow> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final fast = MotionTokens.duration(context, MotionTokens.fast);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: hovered ? c.text : c.icon),
              duration: fast,
              builder: (context, color, _) =>
                  DayIcon(widget.icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 104,
              child: AnimatedDefaultTextStyle(
                duration: fast,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: hovered ? c.text : c.muted),
                child: Text(widget.label),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: widget.control,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
