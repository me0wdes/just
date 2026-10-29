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
/// Padding 12/16, radius 14, 1px border; done titles are struck through.
class TaskRow extends StatefulWidget {
  final TaskItem task;
  final VoidCallback onToggle, onOpen;

  /// Right click: the menu that replaced the row's «…».
  final void Function(Offset globalPosition)? onMenu;

  /// Opens [onMenu] on a long press (touch, when no drag owns it).
  final bool longPressMenu;
  final bool selected;
  final LocalDate? today;
  const TaskRow({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onOpen,
    this.onMenu,
    this.longPressMenu = false,
    this.selected = false,
    this.today,
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
      if (task.recurrenceRuleId != null) ...[
        if (task.dueDate != null) const SizedBox(width: 10),
        DayIcon(DayGlyph.repeat, size: 14, color: c.muted),
      ],
      if (task.reminderAtUtc != null) ...[
        const SizedBox(width: 10),
        DayIcon(DayGlyph.bell, size: 14, color: c.muted),
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
          child: AnimatedContainer(
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
                  : c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border),
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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 68),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4),
                    child: Row(
                      children: [
                        Semantics(
                          checked: task.completed,
                          label: task.completed
                              ? 'Вернуть задачу'
                              : 'Выполнить задачу',
                          child: FluidSurface(
                            sound: null,
                            pressScale: .86,
                            child: Tooltip(
                              message: task.completed ? 'Вернуть' : 'Выполнить',
                              child: InkResponse(
                                onTap: widget.onToggle,
                                radius: 20,
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                    child: CheckCircle(checked: task.completed),
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
                                    child: Row(children: meta),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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
