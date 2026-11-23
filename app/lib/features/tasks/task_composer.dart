import 'package:flutter/material.dart';

import '../../platform/feedback_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/day_icon.dart';
import '../../theme/day_sound.dart';
import '../../theme/fluid_button.dart';
import '../../theme/fluid_surface.dart';
import '../../theme/motion_tokens.dart';
import '../../theme/pickers.dart';
import 'task_row.dart' show EventDot;

/// The add row pinned under the table. The send arrow appears once there is
/// something to send. Above it a «Задача / Событие» switch: an event also
/// carries a time («HH:MM», the second argument of [onAdd]).
class TaskComposer extends StatefulWidget {
  final FocusNode focusNode;
  final Future<void> Function(String text, String? eventTime) onAdd;
  const TaskComposer({super.key, required this.focusNode, required this.onAdd});
  @override
  State<TaskComposer> createState() => _TaskComposerState();
}

class _TaskComposerState extends State<TaskComposer> {
  final text = TextEditingController();
  bool saving = false, focused = false, event = false;
  String? error;
  TimeOfDay time = const TimeOfDay(hour: 9, minute: 0);

  String get timeText =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  void _setEvent(bool value) {
    if (value == event) return;
    setState(() {
      event = value;
      if (value) {
        // The next full hour is the likeliest time for something to come.
        final hour = DateTime.now().hour;
        time = TimeOfDay(hour: hour >= 23 ? 23 : hour + 1, minute: 0);
      }
    });
    widget.focusNode.requestFocus();
  }

  Future<void> _pickTime() async {
    final picked = await showDayTimePicker(
      context,
      initial: time,
      title: 'Время события',
    );
    if (picked != null && mounted) setState(() => time = picked);
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
      await widget.onAdd(draft, event ? timeText : null);
      if (mounted) DaySound.play(context, UiSound.add);
      if (mounted && text.text == draft) text.clear();
      if (mounted) setState(() => event = false);
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
    // Figma «Поле добавления»: 48 tall, radius 16, plus 22, gap 14.
    // A tap anywhere but the field and its send button lets go of focus;
    // touch keeps it by default, so the field stayed lit after adding.
    final showKind = focused || event;
    return TextFieldTapRegion(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: duration,
            curve: MotionTokens.easeOut,
            alignment: Alignment.bottomLeft,
            child: showKind
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        _KindChip(
                          label: 'Задача',
                          selected: !event,
                          onTap: () => _setEvent(false),
                        ),
                        const SizedBox(width: 8),
                        _KindChip(
                          label: 'Событие',
                          selected: event,
                          dot: true,
                          onTap: () => _setEvent(true),
                        ),
                        if (event) ...[
                          const SizedBox(width: 8),
                          _KindChip(
                            label: timeText,
                            selected: false,
                            onTap: _pickTime,
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
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
            AnimatedRotation(
              turns: focused ? .25 : 0,
              duration: duration,
              curve: MotionTokens.easeOut,
              child: DayIcon(
                DayGlyph.add,
                size: 22,
                color: focused ? c.text : c.muted,
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
                        child: DayIcon(
                          DayGlyph.send,
                          size: 18,
                          color: c.screen,
                        ),
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

/// A small pill of the switch above the field; [dot] draws the event's dot.
class _KindChip extends StatelessWidget {
  final String label;
  final bool selected, dot;
  final VoidCallback onTap;
  const _KindChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final fg = selected ? c.screen : c.muted;
    return FluidSurface(
      pressScale: .94,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MotionTokens.duration(context, MotionTokens.fast),
          height: 31,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? c.text : c.input,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot) ...[const EventDot(), const SizedBox(width: 6)],
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
