import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../platform/feedback_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/controls.dart';
import '../../theme/day_icon.dart';
import '../../theme/day_sound.dart';
import '../../theme/fluid_button.dart';
import '../../theme/fluid_surface.dart';
import '../../theme/motion_tokens.dart';
import '../../theme/pickers.dart';
import 'task_row.dart' show EventDot, dayHeading;

/// What an event is made of: its day and, if the user added one, a time.
typedef EventDraft = ({LocalDate day, String? time});

/// The add row pinned under the table. The send arrow appears once there is
/// something to send. At its left a drop-down picks what is made, a task or
/// an event; an event gets a row above with its day (today by default) and a
/// button that adds a time.
class TaskComposer extends StatefulWidget {
  final FocusNode focusNode;

  /// The day the list shows: an event starts on it.
  final LocalDate day;
  final Future<void> Function(String text, EventDraft? event) onAdd;
  const TaskComposer({
    super.key,
    required this.focusNode,
    required this.day,
    required this.onAdd,
  });
  @override
  State<TaskComposer> createState() => _TaskComposerState();
}

class _TaskComposerState extends State<TaskComposer> {
  final text = TextEditingController();
  bool saving = false, focused = false, event = false;
  String? error;
  LocalDate? eventDay;
  TimeOfDay? time;

  LocalDate get day => eventDay ?? widget.day;

  String _two(int n) => n.toString().padLeft(2, '0');
  String get timeText => '${_two(time!.hour)}:${_two(time!.minute)}';

  void _setEvent(bool value) {
    if (value == event) return;
    setState(() {
      event = value;
      eventDay = null;
      time = null;
    });
    widget.focusNode.requestFocus();
  }

  Future<void> _pickDay() async {
    final picked = await showDayDatePicker(context, initial: day.utc);
    if (picked != null && mounted) {
      setState(
        () => eventDay = LocalDate.parse(
          '${picked.year.toString().padLeft(4, '0')}-'
          '${_two(picked.month)}-${_two(picked.day)}',
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    // The next full hour is the likeliest time for something to come.
    final hour = DateTime.now().hour;
    final picked = await showDayTimePicker(
      context,
      initial: time ?? TimeOfDay(hour: hour >= 23 ? 23 : hour + 1, minute: 0),
      title: 'Время события',
    );
    if (picked != null && mounted) setState(() => time = picked);
  }

  /// The drop-down under the plus: a task or an event.
  void _chooseKind(BuildContext box) {
    final render = box.findRenderObject() as RenderBox;
    final at = render.localToGlobal(Offset.zero);
    showDayMenu(box, at, [
      DayMenuItem(
        'Задача',
        DayGlyph.check,
        () => _setEvent(false),
        leading: _TaskMark(DayColors.of(box).text),
      ),
      DayMenuItem(
        'Событие',
        DayGlyph.deadline,
        () => _setEvent(true),
        leading: const EventDot(),
      ),
    ]);
  }

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_focus);
    text.addListener(() => setState(() {}));
  }

  void _focus() => setState(() => focused = widget.focusNode.hasFocus);

  Future<void> save() async {
    if (saving || text.text.trim().isEmpty) return;
    final draft = text.text;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onAdd(
        draft,
        event ? (day: day, time: time == null ? null : timeText) : null,
      );
      if (mounted) DaySound.play(context, UiSound.add);
      if (mounted && text.text == draft) text.clear();
      if (mounted) {
        setState(() {
          event = false;
          eventDay = null;
          time = null;
        });
      }
    } catch (e) {
      if (mounted) {
        DaySound.play(context, UiSound.error);
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Не удалось сохранить. Текст остался в поле.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
        widget.focusNode.requestFocus();
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_focus);
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final ready = text.text.trim().isNotEmpty;
    final duration = MotionTokens.duration(context, MotionTokens.moderate);
    // Figma «Поле добавления»: 48 tall, radius 16, a drop-down, gap 14.
    // A tap anywhere but the field and its send button lets go of focus;
    // touch keeps it by default, so the field stayed lit after adding.
    final eventRow = event
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _Chip(
                  label: dayHeading(day, LocalDate.today()).title,
                  onTap: _pickDay,
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: time == null ? '+ Время' : timeText,
                  onTap: _pickTime,
                  onClear: time == null
                      ? null
                      : () => setState(() => time = null),
                ),
              ],
            ),
          )
        : const SizedBox(width: double.infinity);
    return TextFieldTapRegion(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // AnimatedSize with a zero duration re-dirties its own layout,
          // so reduced motion skips it.
          duration == Duration.zero
              ? eventRow
              : AnimatedSize(
                  duration: duration,
                  curve: MotionTokens.easeOut,
                  alignment: Alignment.bottomLeft,
                  child: eventRow,
                ),
          _field(c, ready, duration),
        ],
      ),
    );
  }

  Widget _field(DayColors c, bool ready, Duration duration) {
    return AnimatedContainer(
      duration: duration,
      curve: MotionTokens.easeOut,
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: c.input,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: error != null
              ? c.overdue
              : focused
              ? c.icon.withValues(alpha: .6)
              : c.input,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Builder(
            builder: (box) => Semantics(
              button: true,
              label: event ? 'Событие' : 'Задача',
              child: GestureDetector(
                key: const Key('composer-kind'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _chooseKind(box),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Center(
                          child: event
                              ? const EventDot()
                              : _TaskMark(focused ? c.text : c.muted),
                        ),
                      ),
                      const SizedBox(width: 6),
                      DayIcon(
                        DayGlyph.down,
                        size: 16,
                        color: focused ? c.text : c.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              key: const Key('task-title-input'),
              controller: text,
              focusNode: widget.focusNode,
              onTapOutside: (_) => widget.focusNode.unfocus(),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => save(),
              maxLength: 500,
              style: Theme.of(context).textTheme.bodyLarge!
                  .copyWith(fontSize: 16, height: 22 / 16, letterSpacing: 0),
              decoration: InputDecoration(
                hintText: event ? 'Добавить событие…' : 'Добавить задачу…',
                hintStyle: TextStyle(color: c.muted, fontSize: 16),
                counterText: '',
                errorText: error,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
              ),
            ),
          ),
          AnimatedScale(
            scale: ready ? 1 : .6,
            duration: duration,
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: ready ? 1 : 0,
              duration: duration,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: FluidIconButton(
                    tooltip: 'Добавить',
                    sound: null,
                    onPressed: saving || !ready ? null : save,
                    icon: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c.text,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DayIcon(DayGlyph.send, size: 18, color: c.screen),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The ring a task has instead of an event's dot.
class _TaskMark extends StatelessWidget {
  final Color color;
  const _TaskMark(this.color);
  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2),
    ),
  );
}

/// A small pill above the field (the event's day, its time); [onClear]
/// draws a cross that takes the value away.
class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _Chip({required this.label, required this.onTap, this.onClear});
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return FluidSurface(
      pressScale: .94,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 31,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.input,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.muted,
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClear,
                  child: DayIcon(DayGlyph.close, size: 14, color: c.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
