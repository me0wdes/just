import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../platform/feedback_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/controls.dart';
import '../../theme/day_icon.dart';
import '../../theme/day_sound.dart';
import '../../theme/fluid_surface.dart';
import '../../theme/blur_text.dart';
import '../../theme/motion_tokens.dart';
import 'greeting_header.dart' show FlowPalette, RoseGoldField;
import 'task_controller.dart';

const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];
const _weekdays = [
  'Понедельник',
  'Вторник',
  'Среда',
  'Четверг',
  'Пятница',
  'Суббота',
  'Воскресенье',
];

String _plural(int n, String one, String few, String many) {
  final d = n % 10, h = n % 100;
  if (d == 1 && h != 11) return one;
  if (d >= 2 && d <= 4 && (h < 12 || h > 14)) return few;
  return many;
}

/// «Сегодня», «Завтра», «Вчера» or the weekday, for the island.
String dayName(LocalDate day, LocalDate today) =>
    switch (day.utc.difference(today.utc).inDays) {
      0 => 'Сегодня',
      1 => 'Завтра',
      -1 => 'Вчера',
      _ => _weekdays[day.utc.weekday - 1],
    };

LocalDate _plus(LocalDate d, int days) => LocalDate.parse(
  d.utc.add(Duration(days: days)).toIso8601String().substring(0, 10),
);

LocalDate _monday(LocalDate d) => _plus(d, 1 - d.utc.weekday);

/// Figma «Новые секции»: the live field with a week calendar. «Сегодня»
/// shows an island with the picked day over the week, «+N» opens the next
/// one; other views show their total next to three weeks.
class WeekHeader extends StatefulWidget {
  final TaskController controller;
  final bool phone;
  final Widget? top;
  const WeekHeader({
    super.key,
    required this.controller,
    this.phone = false,
    this.top,
  });
  FlowPalette get palette => FlowPalette.forHour(controller.clock().hour);
  @override
  State<WeekHeader> createState() => _WeekHeaderState();
}

class _WeekHeaderState extends State<WeekHeader> {
  bool nextWeek = false;
  TaskController get c => widget.controller;

  void pick(LocalDate day) {
    DaySound.play(context, UiSound.nav);
    c.selectDay(day);
  }

  @override
  Widget build(BuildContext context) {
    final today = c.today();
    final monday = _monday(today);
    final dayView = c.query.view == TaskView.today;
    final picked = c.day;
    // A day picked in the next week keeps it open.
    final showNext = nextWeek || picked.utc.difference(monday.utc).inDays >= 7;
    final nextCount = [for (var i = 7; i < 14; i++) c.countOn(_plus(monday, i))]
        .fold(0, (a, b) => a + b);
    final phone = widget.phone;
    final filter = c.query.day;
    final totalLabel = filter != null
        ? '${dayName(filter, today)}, ${filter.utc.day} ${_months[filter.utc.month - 1]}'
        : c.query.view == TaskView.all
        ? 'Всего'
        : c.heading;
    Widget strip(LocalDate start, {VoidCallback? onClose, int rows = 1}) =>
        _Strip(
          days: [for (var i = 0; i < 7 * rows; i++) _plus(start, i)],
          today: today,
          picked: dayView ? picked : c.query.day,
          count: c.countOn,
          onPick: pick,
          onClose: onClose,
          attached: !dayView && !phone,
          phone: phone,
        );
    void fold() => setState(() {
      nextWeek = false;
      if (picked.utc.difference(monday.utc).inDays >= 7) c.selectDay(today);
    });
    void open() {
      DaySound.play(context, UiSound.open);
      setState(() => nextWeek = true);
    }

    // Figma «Новые секции · телефон»: weeks stack, a chip opens or folds
    // the next one; «Все задачи» is the total over the current week.
    final body = phone
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!dayView) ...[
                _Total(
                  label: totalLabel,
                  count: c.tasks.where((t) => !t.completed).length,
                  phone: true,
                ),
                const SizedBox(height: 10),
              ],
              strip(monday),
              if (dayView && showNext) ...[
                const SizedBox(height: 8),
                strip(_plus(monday, 7)),
              ],
              if (dayView && (showNext || nextCount > 0)) ...[
                const SizedBox(height: 10),
                _Chip(
                  label: showNext
                      ? 'Свернуть'
                      : '+$nextCount на следующей неделе',
                  onTap: showNext ? fold : open,
                ),
              ],
            ],
          )
        : dayView
        ? Wrap(
            alignment: WrapAlignment.center,
            runSpacing: 7,
            children: [
              strip(monday),
              // The next week slides out sideways from behind «+N» and
              // slides back in on ×; the week beside it eases over.
              AnimatedSwitcher(
                duration: MotionTokens.duration(context, MotionTokens.panel),
                switchInCurve: MotionTokens.easeOut,
                // Played backwards on ×, so flipped: it starts at once and settles.
                switchOutCurve: MotionTokens.easeOut.flipped,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                // The week keeps its round end while it slides; «+N» only
                // shows once the week is nearly out of the way.
                transitionBuilder: (child, animation) =>
                    child.key == const ValueKey('next')
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: SizeTransition(
                          axis: Axis.horizontal,
                          alignment: Alignment.centerLeft,
                          sizeFactor: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(-.25, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                      )
                    // «+N» keeps its own oval, so no clip of the week's.
                    : SizeTransition(
                        axis: Axis.horizontal,
                        alignment: Alignment.centerLeft,
                        sizeFactor: animation,
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: const Interval(.6, 1),
                          ),
                          child: child,
                        ),
                      ),
                child: Padding(
                  key: ValueKey(showNext ? 'next' : nextCount > 0),
                  // The gap lives inside, so it folds away with the week.
                  padding: EdgeInsets.only(
                    left: showNext || nextCount > 0 ? 7 : 0,
                  ),
                  child: showNext
                      ? strip(_plus(monday, 7), onClose: fold)
                      : nextCount > 0
                      ? _MorePill(count: nextCount, onTap: open)
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Figma: 524 wide; narrower windows shrink it, the weeks stay.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 524),
                  child: _Total(
                    label: totalLabel,
                    count: c.tasks.where((t) => !t.completed).length,
                    phone: false,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              strip(monday, rows: 3),
            ],
          );
    // Figma «Телефон · верх шапки»: 12 under the status bar.
    final topInset = widget.phone
        ? MediaQuery.paddingOf(context).top + 12
        : 0.0;
    return Semantics(
      container: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: RoseGoldField(palette: widget.palette),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.phone ? 20 : 40,
              topInset,
              widget.phone ? 20 : 40,
              widget.phone ? 20 : 28,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: double.infinity,
                minHeight: widget.phone ? 0 : 212,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.top != null || dayView)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: widget.phone ? 48 : 44,
                      ),
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          if (widget.top != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: widget.top,
                            ),
                          if (dayView)
                            _Island(
                              day: picked,
                              today: today,
                              phone: widget.phone,
                            ),
                        ],
                      ),
                    ),
                  SizedBox(
                    height: widget.phone
                        ? (dayView ? 16 : 8)
                        : (dayView ? 91 : 0),
                  ),
                  body,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The island at the top edge: the picked day, growing and shrinking
/// smoothly with its text.
class _Island extends StatelessWidget {
  final LocalDate day, today;
  final bool phone;
  const _Island({required this.day, required this.today, this.phone = false});
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final style = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 15, height: 20 / 15);
    final d = day.utc;
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: dayName(day, today),
            style: style.copyWith(color: c.text),
          ),
          TextSpan(
            text: ', ${d.day} ${_months[d.month - 1]}',
            style: style.copyWith(color: c.muted),
          ),
        ],
      ),
      key: ValueKey(day),
      maxLines: 1,
    );
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Container(
      // On a phone it sits under the status bar, so it rounds all over.
      padding: EdgeInsets.symmetric(horizontal: phone ? 20 : 24, vertical: 12),
      decoration: BoxDecoration(
        color: c.screen,
        borderRadius: phone
            ? BorderRadius.circular(22)
            : const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      // The width follows the new day while the text swaps through a blur.
      // AnimatedSize with a zero duration re-dirties its own layout, so
      // reduced motion skips it.
      child: reduce
          ? text
          : AnimatedSize(
              duration: const Duration(milliseconds: 680),
              curve: const Cubic(.22, 1, .36, 1),
              child: BlurSwap(swapKey: day, child: text),
            ),
    );
  }
}

/// A week (or three) of days on a pill; [attached] hangs it from the top
/// edge as in the «Все задачи» header.
class _Strip extends StatelessWidget {
  final List<LocalDate> days;
  final LocalDate today;
  final LocalDate? picked;
  final int Function(LocalDate) count;
  final ValueChanged<LocalDate> onPick;
  final VoidCallback? onClose;
  final bool attached, phone;
  const _Strip({
    this.phone = false,
    required this.days,
    required this.today,
    required this.picked,
    required this.count,
    required this.onPick,
    required this.onClose,
    required this.attached,
  });
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final rows = [
      for (var r = 0; r < days.length; r += 7) days.sublist(r, r + 7),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        // 40 px days with 10 px gaps, narrower on a phone.
        // Phone: padding 8, gaps 6, radius 26 (332 px wide).
        final pad = phone ? 8.0 : 10.0, gap = phone ? 6.0 : 10.0;
        final extra = onClose != null ? 42.0 : 0.0;
        final room = box.maxWidth - 2 * pad - extra;
        // Figma «Телефон · текущая неделя»: on a phone the days share the
        // whole width; on a computer they stay 40 px.
        final cell = ((room - 6 * gap) / 7).clamp(30.0, phone ? 80.0 : 40.0);
        final radius = phone ? 26.0 : 28.0;
        return Container(
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: c.screen,
            borderRadius: attached
                ? BorderRadius.vertical(bottom: Radius.circular(radius))
                : BorderRadius.circular(radius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) SizedBox(height: gap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (k, day) in row.indexed) ...[
                      if (k > 0) SizedBox(width: gap),
                      FadeUp(
                        key: ValueKey(day),
                        index: i * 7 + k,
                        child: _Day(
                          day: day,
                          width: cell,
                          picked: day == picked,
                          today: day == today && day != picked,
                          tasks: count(day),
                          onTap: () => onPick(day),
                        ),
                      ),
                    ],
                    if (onClose != null) ...[
                      const SizedBox(width: 10),
                      DayButton.icon(
                        tooltip: 'Свернуть неделю',
                        onPressed: onClose,
                        icon: DayIcon(DayGlyph.close, size: 16, color: c.muted),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Figma «День» (40×57): the date and up to three dots for its tasks, a
/// fourth «+» when there are more.
class _Day extends StatelessWidget {
  final LocalDate day;
  final double width;
  final bool picked, today;
  final int tasks;
  final VoidCallback onTap;
  const _Day({
    required this.day,
    required this.width,
    required this.picked,
    required this.today,
    required this.tasks,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final ink = picked ? c.screen : c.text;
    return Semantics(
      button: true,
      selected: picked,
      label:
          '${day.utc.day} ${_months[day.utc.month - 1]}, '
          '$tasks ${_plural(tasks, 'задача', 'задачи', 'задач')}',
      child: FluidSurface(
        sound: null,
        pressScale: .92,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Builder(
            builder: (context) {
              final hover = FluidInteraction.of(context)?.hover ?? 0;
              return AnimatedContainer(
                duration: MotionTokens.duration(context, MotionTokens.fast),
                width: width,
                // 57 in Figma; grows with large text instead of clipping.
                constraints: const BoxConstraints(minHeight: 57),
                padding: const EdgeInsets.only(top: 19, bottom: 6),
                decoration: BoxDecoration(
                  color: picked
                      ? c.text
                      : Color.lerp(
                          Colors.transparent,
                          overlay(context, .05, .07),
                          hover,
                        ),
                  borderRadius: BorderRadius.circular(20),
                  border: today ? Border.all(color: c.muted) : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${day.utc.day}',
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontSize: 15,
                        height: 18 / 15,
                        fontWeight: picked ? FontWeight.w500 : FontWeight.w400,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _Dots(
                      tasks: tasks,
                      color: ink,
                      plus: picked ? c.screen : c.muted,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int tasks;
  final Color color, plus;
  const _Dots({required this.tasks, required this.color, required this.plus});
  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    // Scales down in a narrow phone day rather than overflowing.
    return SizedBox(
      height: 6,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tasks.clamp(0, 3); i++) ...[
              if (i > 0) const SizedBox(width: 2),
              dot,
            ],
            if (tasks > 3) ...[
              const SizedBox(width: 2),
              // Figma «dots / больше 3»: a 5 px plus, 1.4 thick, muted.
              CustomPaint(size: const Size.square(6), painter: _Plus(plus)),
            ],
          ],
        ),
      ),
    );
  }
}

/// «+N»: tasks next week; opens it.
/// Figma «Ещё +N»: default, hover, pressed and focus states; the fill
/// eases between them (Figma switch/off, pill/hover, pill/pressed).
class _MorePill extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  const _MorePill({required this.count, required this.onTap});
  @override
  State<_MorePill> createState() => _MorePillState();
}

class _MorePillState extends State<_MorePill> {
  bool hovered = false, pressed = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final c = DayColors.of(context);
    // Figma «Шапка · компьютер»: the screen colour at 60 %, so it reads on
    // any sky; hover and press firm it up.
    final opacity = pressed
        ? .9
        : hovered
        ? .75
        : .6;
    return Tooltip(
      message: 'Следующая неделя',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => hovered = true),
          onExit: (_) => setState(() => hovered = false),
          child: Semantics(
            button: true,
            label: '+${widget.count} на следующей неделе',
            excludeSemantics: true,
            child: FluidSurface(
              sound: null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => setState(() => pressed = true),
                onTapUp: (_) => setState(() => pressed = false),
                onTapCancel: () => setState(() => pressed = false),
                onTap: widget.onTap,
                child: AnimatedContainer(
                  key: const Key('more-pill'),
                  duration: reduce
                      ? Duration.zero
                      : Duration(milliseconds: pressed ? 100 : 150),
                  curve: Curves.easeOut,
                  width: 38,
                  height: 77,
                  padding: const EdgeInsets.only(top: 29),
                  alignment: Alignment.topCenter,
                  decoration: BoxDecoration(
                    color: c.screen.withValues(alpha: opacity),
                    // A true oval: the ends are half the width round.
                    borderRadius: BorderRadius.circular(19),
                    border: focused
                        ? Border.all(color: c.muted, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    '+${widget.count}',
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontSize: 15,
                      height: 18 / 15,
                      color: c.text.withValues(alpha: opacity),
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

/// «Всего · 14 задач» hanging from the top edge.
class _Total extends StatelessWidget {
  final String label;
  final int count;
  final bool phone;
  const _Total({required this.label, required this.count, required this.phone});
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!;
    final big = text.copyWith(
      fontSize: phone ? 36 : 48,
      height: phone ? 44 / 36 : 56 / 48,
      color: c.text,
    );
    return Container(
      width: double.infinity,
      padding: phone
          ? const EdgeInsets.symmetric(horizontal: 24, vertical: 20)
          : const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: c.screen,
        borderRadius: phone
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          BlurSwap(
            swapKey: label,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.copyWith(
                fontSize: 13,
                height: 18 / 13,
                color: c.muted,
              ),
            ),
          ),
          BlurSwap(
            swapKey: count,
            alignment: AlignmentDirectional.centerStart,
            delay: const Duration(milliseconds: 100),
            child: Text(
              '$count ${_plural(count, 'задача', 'задачи', 'задач')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: big,
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone: «+N на следующей неделе» under the week, «Свернуть» once open.
class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return FluidSurface(
      sound: null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: c.screen,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(fontSize: 13, height: 18 / 13, color: c.text),
          ),
        ),
      ),
    );
  }
}

class _Plus extends CustomPainter {
  final Color color;
  const _Plus(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(3, .5), const Offset(3, 5.5), p);
    canvas.drawLine(const Offset(.5, 3), const Offset(5.5, 3), p);
  }

  @override
  bool shouldRepaint(_Plus old) => old.color != color;
}
