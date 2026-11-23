import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/controls.dart';

import '../../domain/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/day_icon.dart';
import '../../theme/fluid_surface.dart';
import '../../theme/motion_tokens.dart';
import 'beam_border.dart';

const _months = [
  'янв',
  'фев',
  'мар',
  'апр',
  'мая',
  'июн',
  'июл',
  'авг',
  'сен',
  'окт',
  'ноя',
  'дек',
];

/// «Завтра» or «Завтра, 13:00» when the due date has a time.
String dueLabel(LocalDate due, LocalDate today, [String? time]) =>
    time == null ? _dayLabel(due, today) : '${_dayLabel(due, today)}, $time';

/// «7 дн.» while more than a day is left, «5 ч» in the last day.
String keepLabel(Duration left) => left.inHours < 24
    ? '${math.max(1, (left.inMinutes / 60).ceil())} ч'
    : '${(left.inMinutes / 1440).ceil()} дн.';

const _weekdays = [
  'Понедельник',
  'Вторник',
  'Среда',
  'Четверг',
  'Пятница',
  'Суббота',
  'Воскресенье',
];
const _weekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// The heading of a day in «Предстоящие»: «Сегодня · Пн, 23 ноя»,
/// «Завтра · Вт, 24 ноя», then «Пятница · 27 ноя».
({String title, String sub}) dayHeading(LocalDate day, LocalDate today) {
  final d = day.utc, days = d.difference(today.utc).inDays;
  final date =
      '${d.day} ${_months[d.month - 1]}'
      '${d.year == today.utc.year ? '' : ' ${d.year}'}';
  final short = _weekdaysShort[d.weekday - 1];
  if (days == 0) return (title: 'Сегодня', sub: '$short, $date');
  if (days == 1) return (title: 'Завтра', sub: '$short, $date');
  return (title: _weekdays[d.weekday - 1], sub: date);
}

String _dayLabel(LocalDate due, LocalDate today) {
  final days = due.utc.difference(today.utc).inDays;
  if (days == 0) return 'Сегодня';
  if (days == 1) return 'Завтра';
  if (days == -1) return 'Вчера';
  final d = due.utc;
  return '${d.day} ${_months[d.month - 1]}'
      '${d.year == today.utc.year ? '' : ' ${d.year}'}';
}

/// Figma «Карточка дела»: check and a title with a due line. The whole
/// card drags to reorder; deleting lives in the detail panel.
/// Padding 12/16, radius 14; flat, done titles are struck through.
class TaskRow extends StatefulWidget {
  final TaskItem task;
  final VoidCallback onToggle, onOpen;

  /// Right click: the menu that replaced the row's «…».
  final void Function(Offset globalPosition)? onMenu;

  /// Opens [onMenu] on a long press (touch, when no drag owns it).
  final bool longPressMenu;
  final bool selected;
  final LocalDate? today;

  /// Marks a new task among overdue ones; null for every other card.
  final BeamStyle? beam;

  /// The task's list, shown as a coloured pill after the due line.
  final TaskList? list;
  const TaskRow({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onOpen,
    this.onMenu,
    this.longPressMenu = false,
    this.selected = false,
    this.today,
    this.beam,
    this.list,
  });
  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool hovered = false, pressed = false;
  Timer? _due;

  @override
  void dispose() {
    _due?.cancel();
    super.dispose();
  }

  Widget _beamed(Widget child) => widget.beam == null
      ? child
      : BeamBorder(style: widget.beam!, child: child);

  Widget _lit(Widget child) => widget.beam == null
      ? child
      : Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: BeamGlow(palette: widget.beam!.palette),
              ),
            ),
            child,
          ],
        );

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final theme = Theme.of(context);
    final task = widget.task;
    final today = widget.today ?? LocalDate.today();
    final now = DateTime.now(), at = task.dueAt;
    final overdue = task.isOverdue(today, now);
    // Turns red at the due time without waiting for another rebuild.
    _due?.cancel();
    if (!overdue && !task.completed && task.dueDate == today && at != null) {
      _due = Timer(at.difference(now), () {
        if (mounted) setState(() {});
      });
    }
    final metaColor = overdue ? c.overdue : c.muted;
    final meta = <Widget>[
      if (task.dueDate != null) ...[
        DayIcon(DayGlyph.clock, size: 14, color: metaColor),
        const SizedBox(width: 6),
        Text(
          dueLabel(task.dueDate!, today, task.dueTime),
          style: theme.textTheme.bodySmall!.copyWith(color: metaColor),
        ),
      ],
      if (widget.list != null) ...[
        const SizedBox(width: 6),
        ListPill(widget.list!),
      ],
      if (task.recurrenceRuleId != null) ...[
        if (task.dueDate != null) const SizedBox(width: 10),
        DayIcon(DayGlyph.repeat, size: 14, color: c.muted),
      ],
      if (task.reminderAtUtc != null) ...[
        const SizedBox(width: 10),
        DayIcon(DayGlyph.bell, size: 14, color: c.muted),
      ],
      // A done task shows how long it stays before it is cleared out.
      if (task.completed && task.expiresAt != null)
        if (task.expiresAt!.difference(now) case final left
            when left > Duration.zero) ...[
          if (task.dueDate != null) const SizedBox(width: 10),
          DayIcon(DayGlyph.delete, size: 14, color: c.muted),
          const SizedBox(width: 6),
          Text(
            'через ${keepLabel(left)}',
            style: theme.textTheme.bodySmall!.copyWith(color: c.muted),
          ),
        ],
    ];
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      // iOS-like press: the ink highlight starts after a short hold and
      // drops when the finger scrolls, so a scroll never dents a card; it
      // sinks quickly and settles back slower.
      child: FluidSurface(
        pressScale: 1,
        child: AnimatedScale(
          scale: pressed ? .97 : 1,
          duration: MotionTokens.duration(
            context,
            pressed ? const Duration(milliseconds: 120) : MotionTokens.panel,
          ),
          curve: MotionTokens.easeOut,
          child: _beamed(AnimatedContainer(
            duration: MotionTokens.duration(context, MotionTokens.fast),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              // Hover only tints the fill; the 1px border never changes.
              color: widget.selected
                  ? c.track
                  // A press only tints with a mouse: on touch the held
                  // card lifts as the same white card, no colour jump.
                  : hovered || (pressed && !isPhone(context))
                  ? c.hover
                  // Figma: rows are flat; only a highlighted new one keeps
                  // the card (a dragged or swiped row gets it from outside).
                  : widget.beam != null
                  ? c.card
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.beam != null ? c.border : Colors.transparent,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onOpen,
                onHighlightChanged: (on) => setState(() => pressed = on),
                onSecondaryTapUp: widget.onMenu == null
                    ? null
                    : (d) => widget.onMenu!(d.globalPosition),
                onLongPress: widget.onMenu == null || !widget.longPressMenu
                    ? null
                    : () {
                        final box = context.findRenderObject() as RenderBox;
                        widget.onMenu!(
                          box.localToGlobal(box.size.center(Offset.zero)),
                        );
                      },
                hoverColor: Colors.transparent,
                focusColor: c.track,
                child: _lit(ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 66),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4),
                    child: Row(
                      children: [
                        Semantics(
                          checked: task.completed,
                          label: task.isEvent
                              ? 'Убрать событие'
                              : task.completed
                              ? 'Вернуть задачу'
                              : 'Выполнить задачу',
                          child: FluidSurface(
                            sound: null,
                            pressScale: .86,
                            child: Tooltip(
                              message: task.isEvent
                                  ? 'Убрать'
                                  : task.completed
                                  ? 'Вернуть'
                                  : 'Выполнить',
                              child: InkResponse(
                                onTap: widget.onToggle,
                                radius: 20,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                    child: task.isEvent
                                        ? const EventDot()
                                        : CheckCircle(checked: task.completed),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Strikethrough(
                                  done: task.completed,
                                  color: c.text,
                                  child: Text(
                                    task.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge!.copyWith(
                                      color: c.text,
                                    ),
                                  ),
                                ),
                                if (meta.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: meta,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                )),
              ),
            ),
          )),
        ),
      ),
    );
  }
}

/// Figma «Событие»: a coloured dot where a task has its check.
class EventDot extends StatelessWidget {
  const EventDot({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: const BoxDecoration(
      color: Color(0xffff6b57),
      shape: BoxShape.circle,
    ),
  );
}

/// Parses «#RRGGBB»; the neutral list colour when it is not one.
Color listColor(TaskList list) {
  final hex = list.tint.replaceFirst('#', '');
  final value = int.tryParse(hex, radix: 16);
  return hex.length == 6 && value != null
      ? Color(0xff000000 | value)
      : const Color(0xff8c9b7a);
}

/// Figma «Метка списка»: the list's name on a tint of its own colour.
class ListPill extends StatelessWidget {
  final TaskList list;
  const ListPill(this.list, {super.key});
  @override
  Widget build(BuildContext context) {
    final base = listColor(list);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      // Figma «Метка списка»: 8/2, radius 10, Medium 12 on a 14 line.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: dark ? .18 : .14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        list.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          fontSize: 12,
          height: 14 / 12,
          fontWeight: FontWeight.w500,
          color: Color.lerp(base, dark ? Colors.white : Colors.black, .3),
        ),
      ),
    );
  }
}

/// Circle that fills from the centre and then draws its tick, with a small
/// overshoot so completing an item feels like pressing a real button.
class CheckCircle extends StatefulWidget {
  final bool checked;
  final double size;
  const CheckCircle({super.key, required this.checked, this.size = 22});
  @override
  State<CheckCircle> createState() => _CheckCircleState();
}

class _CheckCircleState extends State<CheckCircle>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: MotionTokens.strike,
    value: widget.checked ? 1 : 0,
  );
  @override
  void didUpdateWidget(CheckCircle old) {
    super.didUpdateWidget(old);
    if (old.checked == widget.checked) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = widget.checked ? 1 : 0;
    } else if (widget.checked) {
      controller.forward(from: 0);
    } else {
      controller.reverse();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        final bump = controller.status == AnimationStatus.forward
            ? math.sin(t * math.pi) * .14
            : 0.0;
        return Transform.scale(
          scale: 1 + bump,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _CheckPainter(
              t: t,
              ring: c.icon,
              fill: c.accent,
              tick: c.onAccent,
            ),
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double t;
  final Color ring, fill, tick;
  _CheckPainter({
    required this.t,
    required this.ring,
    required this.fill,
    required this.tick,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), r = size.width / 2;
    final grow = Curves.easeOutCubic.transform((t / .55).clamp(0, 1));
    canvas.drawCircle(
      center,
      r - .9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Color.lerp(ring, fill, grow)!,
    );
    if (grow > 0) {
      canvas.drawCircle(center, r * grow, Paint()..color = fill);
    }
    final draw = Curves.easeOutCubic.transform(((t - .3) / .7).clamp(0, 1));
    if (draw <= 0) return;
    final s = size.width;
    final path = Path()
      ..moveTo(s * .29, s * .52)
      ..lineTo(s * .44, s * .66)
      ..lineTo(s * .72, s * .37);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * draw),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = tick,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.t != t || old.ring != ring || old.fill != fill || old.tick != tick;
}

/// A line drawn across the title from left to right.
class Strikethrough extends StatelessWidget {
  final bool done;
  final Color color;
  final Widget child;
  const Strikethrough({
    super.key,
    required this.done,
    required this.color,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: done ? 1 : 0),
    duration: MotionTokens.duration(context, MotionTokens.strike),
    curve: MotionTokens.easeOut,
    child: child,
    builder: (context, t, child) =>
        CustomPaint(foregroundPainter: _LinePainter(t, color), child: child),
  );
}

class _LinePainter extends CustomPainter {
  final double t;
  final Color color;
  _LinePainter(this.t, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final y = size.height * .54;
    canvas.drawLine(
      Offset(0, y),
      Offset(ui.lerpDouble(0, size.width, t)!, y),
      Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.t != t || old.color != color;
}
