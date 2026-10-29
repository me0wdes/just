import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
const _monthNames = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
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
/// one. Other views (Figma «Шапка · все задачи · 12») show their total in
/// the island, which drops the month down, and the week's progress.
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
  // The month the island drops down over the screen, phone and computer
  // alike.
  final monthDrop = OverlayPortalController();
  final anchor = LayerLink();
  final monthFocus = FocusNode(debugLabel: 'Календарь месяца');
  DateTime month = DateTime.utc(2000);

  @override
  void dispose() {
    monthFocus.dispose();
    super.dispose();
  }

  TaskController get c => widget.controller;

  void pick(LocalDate day) {
    DaySound.play(context, UiSound.nav);
    c.selectDay(day);
  }

  void toggleMonth() {
    if (monthDrop.isShowing) return closeMonth();
    DaySound.play(context, UiSound.open);
    final from = (c.query.day ?? c.today()).utc;
    setState(() {
      month = DateTime.utc(from.year, from.month);
      monthDrop.show();
    });
    // The screen already holds focus, so Esc needs it handed over.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => monthFocus.requestFocus(),
    );
  }

  void closeMonth() {
    if (!monthDrop.isShowing) return;
    DaySound.play(context, UiSound.close);
    setState(monthDrop.hide);
  }

  /// Figma «Календарь · выпадающее окно»: the month on the day pill, under
  /// the island; a tap outside or Esc folds it, a picked day too.
  Widget monthDropdown(BuildContext context) {
    final first = LocalDate.parse(month.toIso8601String().substring(0, 10));
    final length = DateUtils.getDaysInMonth(month.year, month.month);
    final rows = ((first.utc.weekday - 1 + length) / 7).ceil();
    final start = _monday(first);
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: anchor,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomCenter,
        followerAnchor: Alignment.topCenter,
        offset: const Offset(0, 8),
        child: TapRegion(
          groupId: anchor,
          onTapOutside: (_) => closeMonth(),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): closeMonth,
            },
            child: Focus(
              focusNode: monthFocus,
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  // Figma: 360 on a computer, the phone's width less 20 a side.
                  width: math.min(MediaQuery.sizeOf(context).width - 40, 360),
                  // It lies over the list in the screen colour, so in the
                  // dark theme only an edge and a shadow set it apart.
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.phone ? 26 : 28),
                    border: Border.all(color: DayColors.of(context).border),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.phone ? 26 : 28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => _Strip(
                      days: [
                        for (var i = 0; i < 7 * rows; i++) _plus(start, i),
                      ],
                      today: c.today(),
                      picked: c.query.day,
                      count: c.countOn,
                      onPick: (day) {
                        setState(monthDrop.hide);
                        pick(day);
                      },
                      onClose: null,
                      phone: widget.phone,
                      month: month,
                      onShift: (by) => setState(
                        () =>
                            month = DateTime.utc(month.year, month.month + by),
                      ),
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
    final progress = c.weekProgress();
    final openCount = c.tasks.where((t) => !t.completed).length;
    final count =
        '$openCount ${_plural(openCount, 'задача', 'задачи', 'задач')}';
    // «Сегодня, 28 октября»; «Всего 6 задач», «Работа · 6 задач»; true
    // marks the muted part.
    final island = dayView
        ? [
            (dayName(picked, today), false),
            (', ${picked.utc.day} ${_months[picked.utc.month - 1]}', true),
          ]
        : [
            (totalLabel + (totalLabel == 'Всего' ? ' ' : ' · '), true),
            (count, false),
          ];
    Widget strip(LocalDate start, {VoidCallback? onClose, bool bare = false}) =>
        _Strip(
          days: [for (var i = 0; i < 7; i++) _plus(start, i)],
          today: today,
          picked: picked,
          count: c.countOn,
          onPick: pick,
          onClose: onClose,
          phone: phone,
          bare: bare,
        );
    // One pill for every view: the week in «Сегодня» flows into the
    // week's progress elsewhere and back. No tasks this week, no pill.
    final hidePill = !dayView && progress.total == 0;
    final pill = _Morph(
      swapKey: dayView ? 'week' : (hidePill ? 'none' : 'progress'),
      phone: phone,
      hidden: hidePill,
      child: dayView
          ? strip(monday, bare: true)
          : hidePill
          ? const SizedBox.shrink()
          : _Progress(done: progress.done, total: progress.total, phone: phone),
    );
    void fold() => setState(() {
      nextWeek = false;
      if (picked.utc.difference(monday.utc).inDays >= 7) c.selectDay(today);
    });
    void open() {
      DaySound.play(context, UiSound.open);
      setState(() => nextWeek = true);
    }

    // Opening and folding the next week: unhurried and soft, the same on
    // a phone (down) and a computer (sideways); folding plays it backwards.
    final weekMotion = MotionTokens.duration(
      context,
      const Duration(milliseconds: 380),
    );
    const weekCurve = Curves.easeOutCubic;

    // Figma «Новые секции · телефон»: weeks stack, a chip opens or folds
    // the next one.
    final body = phone
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              pill,
              if (dayView)
                // The next week unfolds downwards and the header grows with it.
                AnimatedSwitcher(
                  duration: weekMotion,
                  switchInCurve: weekCurve,
                  switchOutCurve: weekCurve.flipped,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) => SizeTransition(
                    alignment: Alignment.topCenter,
                    sizeFactor: animation,
                    child: FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, -.15),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                  ),
                  child: showNext
                      ? Padding(
                          key: const ValueKey('next'),
                          padding: const EdgeInsets.only(top: 8),
                          child: strip(_plus(monday, 7)),
                        )
                      : const SizedBox(
                          key: ValueKey('none'),
                          width: double.infinity,
                        ),
                ),
              if (dayView && (showNext || nextCount > 0)) ...[
                const SizedBox(height: 10),
                _Chip(
                  motion: weekMotion,
                  label: showNext
                      ? 'Свернуть'
                      : '+$nextCount на следующей неделе',
                  onTap: showNext ? fold : open,
                ),
              ],
            ],
          )
        : Wrap(
            alignment: WrapAlignment.center,
            runSpacing: 7,
            children: [
              pill,
              // The next week slides out sideways from behind «+N» and
              // slides back in on ×; the week beside it eases over.
              if (dayView)
                AnimatedSwitcher(
                  duration: weekMotion,
                  switchInCurve: weekCurve,
                  // Played backwards on ×, so flipped: it starts at once and settles.
                  switchOutCurve: weekCurve.flipped,
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
                // A computer keeps the pill at the bottom of the field.
                mainAxisAlignment: phone
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.spaceBetween,
                children: [
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
                        // One island for every view, so switching them
                        // eases its width and blurs the words over.
                        CompositedTransformTarget(
                          link: anchor,
                          child: OverlayPortal(
                            controller: monthDrop,
                            overlayChildBuilder: monthDropdown,
                            child: TapRegion(
                              groupId: anchor,
                              child: _Island(
                                parts: island,
                                swapKey: dayView
                                    ? picked
                                    : '$totalLabel$openCount',
                                open: monthDrop.isShowing,
                                phone: widget.phone,
                                onTap: dayView ? null : toggleMonth,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: widget.phone ? 16 : 7),
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

/// The island at the top edge: the picked day in «Сегодня», the total
/// elsewhere, where a tap drops the month down. It grows and shrinks
/// smoothly with its words.
class _Island extends StatefulWidget {
  final List<(String, bool)> parts;
  final Object swapKey;
  final bool open, phone;
  final VoidCallback? onTap;
  const _Island({
    required this.parts,
    required this.swapKey,
    required this.open,
    required this.phone,
    required this.onTap,
  });
  @override
  State<_Island> createState() => _IslandState();
}

class _IslandState extends State<_Island> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final style = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 15, height: 20 / 15);
    final tap = widget.onTap;
    final words = widget.parts.map((p) => p.$1).join();
    final reduce = MediaQuery.disableAnimationsOf(context);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: BlurSwap(
            swapKey: widget.swapKey,
            child: Text.rich(
              TextSpan(
                children: [
                  for (final (text, muted) in widget.parts)
                    TextSpan(
                      text: text,
                      style: style.copyWith(color: muted ? c.muted : c.text),
                    ),
                ],
              ),
              key: ValueKey(widget.swapKey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (tap != null) ...[
          const SizedBox(width: 8),
          AnimatedRotation(
            turns: widget.open ? .5 : 0,
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: DayIcon(DayGlyph.down, size: 16, color: c.muted),
          ),
        ],
      ],
    );
    return FocusableActionDetector(
      enabled: tap != null,
      mouseCursor: tap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onShowFocusHighlight: (v) => setState(() => focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            tap?.call();
            return null;
          },
        ),
      },
      child: Semantics(
        button: tap != null,
        expanded: tap == null ? null : widget.open,
        label: tap == null ? words : '$words, календарь месяца',
        excludeSemantics: true,
        child: FluidSurface(
          enabled: tap != null,
          sound: null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: Container(
              // A long list name ends in «…» rather than under the menu.
              constraints: BoxConstraints(maxWidth: widget.phone ? 240 : 520),
              // On a phone it sits under the status bar, so it rounds all over.
              padding: EdgeInsets.symmetric(
                horizontal: widget.phone ? 20 : 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: c.screen,
                borderRadius: widget.phone
                    ? BorderRadius.circular(22)
                    : const BorderRadius.vertical(bottom: Radius.circular(24)),
                border: focused && tap != null
                    ? Border.all(color: c.muted, width: 1.5)
                    : null,
              ),
              // The width follows the new words while they swap through a
              // blur. AnimatedSize with a zero duration re-dirties its own
              // layout, so reduced motion skips it.
              child: reduce
                  ? content
                  : AnimatedSize(
                      duration: const Duration(milliseconds: 680),
                      curve: const Cubic(.22, 1, .36, 1),
                      child: content,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A week of days on a pill; with [month] the whole month under its name,
/// arrows and weekdays, the days of other months faded.
class _Strip extends StatelessWidget {
  final List<LocalDate> days;
  final LocalDate today;
  final LocalDate? picked;
  final int Function(LocalDate) count;
  final ValueChanged<LocalDate> onPick;
  final VoidCallback? onClose;
  final bool phone;
  final DateTime? month;
  final ValueChanged<int>? onShift;

  /// Inside [_Morph], which draws the pill itself.
  final bool bare;
  const _Strip({
    this.bare = false,
    this.phone = false,
    required this.days,
    required this.today,
    required this.picked,
    required this.count,
    required this.onPick,
    required this.onClose,
    this.month,
    this.onShift,
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
        final month = this.month,
            text = Theme.of(context).textTheme.bodyMedium!;
        Widget arrow(int by, String tip) => DayButton.icon(
          tooltip: tip,
          onPressed: () => onShift!(by),
          icon: RotatedBox(
            quarterTurns: by < 0 ? 1 : 3,
            child: DayIcon(DayGlyph.down, size: 16, color: c.muted),
          ),
        );
        return Container(
          padding: EdgeInsets.all(pad),
          decoration: bare
              ? null
              : BoxDecoration(
                  color: c.screen,
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: month == null
                      ? null
                      : const [
                          BoxShadow(
                            color: Color(0x1f000000),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (month != null) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_monthNames[month.month - 1]} ${month.year}',
                          style: text.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: c.text,
                          ),
                        ),
                      ),
                      arrow(-1, 'Прошлый месяц'),
                      arrow(1, 'Следующий месяц'),
                    ],
                  ),
                ),
                SizedBox(height: gap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (k, w) in const [
                      'Пн',
                      'Вт',
                      'Ср',
                      'Чт',
                      'Пт',
                      'Сб',
                      'Вс',
                    ].indexed) ...[
                      if (k > 0) SizedBox(width: gap),
                      SizedBox(
                        width: cell,
                        height: 20,
                        child: Center(
                          child: Text(
                            w,
                            style: text.copyWith(
                              fontSize: 13,
                              height: 18 / 13,
                              color: c.muted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: gap),
              ],
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
                          outside:
                              month != null && day.utc.month != month.month,
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

/// Figma «День» (40×57): the date and up to two dots for its tasks, a
/// «+» after them when there are more.
class _Day extends StatelessWidget {
  final LocalDate day;
  final double width;
  final bool picked, today, outside;
  final int tasks;
  final VoidCallback onTap;
  const _Day({
    required this.day,
    required this.width,
    required this.picked,
    required this.today,
    this.outside = false,
    required this.tasks,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    // Figma: another month's day at 35 %.
    final ink = picked
        ? c.screen
        : outside
        ? c.text.withValues(alpha: .35)
        : c.text;
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
            // Figma «dots»: one, two, or two and a plus for more.
            for (var i = 0; i < tasks.clamp(0, 2); i++) ...[
              if (i > 0) const SizedBox(width: 2),
              dot,
            ],
            if (tasks > 2) ...[
              const SizedBox(width: 2),
              // Figma «dots / больше 2»: a 5 px plus, 1.4 thick, muted.
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

/// The pill under the island: one dark shape for every view that eases to
/// its new size while the week and the progress cross-fade inside, so
/// switching views flows instead of building a new pill.
class _Morph extends StatelessWidget {
  final Object swapKey;
  final bool phone, hidden;
  final Widget child;
  const _Morph({
    required this.swapKey,
    required this.phone,
    required this.hidden,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final motion = MotionTokens.duration(
      context,
      const Duration(milliseconds: 380),
    );
    final content = KeyedSubtree(key: ValueKey(swapKey), child: child);
    return LayoutBuilder(
      builder: (context, box) => AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: motion,
        child: Container(
          key: const Key('header-pill'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.screen,
            borderRadius: BorderRadius.circular(phone ? 26 : 28),
          ),
          // AnimatedSize with a zero duration re-dirties its own layout,
          // so reduced motion skips it.
          child: motion == Duration.zero
              ? content
              : AnimatedSize(
                  duration: motion,
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: motion,
                    // The old content is gone in the first 40 %, the new
                    // one settles in as the shape does.
                    // The new content comes in early, so its rise is seen.
                    switchInCurve: const Interval(
                      .15,
                      1,
                      curve: Curves.easeOut,
                    ),
                    switchOutCurve: const Interval(.6, 1, curve: Curves.easeIn),
                    // Only the new content sizes the pill; the old one keeps
                    // its own size underneath and is clipped by the shape.
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.center,
                      children: [
                        for (final p in previous)
                          Positioned.fill(
                            child: OverflowBox(
                              minWidth: 0,
                              minHeight: 0,
                              maxWidth: box.maxWidth,
                              maxHeight: double.infinity,
                              child: p,
                            ),
                          ),
                        ?current,
                      ],
                    ),
                    child: content,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Figma «Прогресс недели»: done this week of all this week's tasks, with
/// a thin bar. The week's size, so the pill keeps its shape between views:
/// 360×77 on a computer, the full width and 73 tall on a phone.
class _Progress extends StatelessWidget {
  final int done, total;
  final bool phone;
  const _Progress({
    required this.done,
    required this.total,
    required this.phone,
  });
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!;
    final all = done == total;
    // The border colour for the rest of the week: faint next to the bright
    // done part in both themes, so the share reads at a glance.
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 6,
        color: c.border,
        alignment: Alignment.centerLeft,
        // Fills from empty as the progress appears, then eases to new
        // values as tasks get done.
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: done / total),
          duration: MotionTokens.duration(
            context,
            const Duration(milliseconds: 600),
          ),
          curve: Curves.easeOutCubic,
          builder: (context, share, _) => FractionallySizedBox(
            widthFactor: share,
            child: Container(color: c.text),
          ),
        ),
      ),
    );
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rises in like the week's days: the words, the bar, the count.
        FadeUp(
          index: 0,
          child: Text(
            all ? 'Всё сделано за неделю' : 'Сделано на этой неделе',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.copyWith(fontSize: 15, height: 20 / 15, color: c.muted),
          ),
        ),
        const SizedBox(height: 10),
        FadeUp(index: 2, child: bar),
      ],
    );
    return Semantics(
      container: true,
      label:
          '${all ? 'Всё сделано за неделю' : 'Сделано на этой неделе'}: '
          '$done из $total',
      excludeSemantics: true,
      child: Container(
        // Like the week: 7 days of 40 with 10 gaps and 10 a side; the
        // height grows with large text instead of clipping.
        width: phone ? null : 360,
        constraints: BoxConstraints(minHeight: phone ? 73 : 77),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        child: Row(
          children: [
            Expanded(child: label),
            const SizedBox(width: 20),
            FadeUp(
              index: 4,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$done',
                      style: text.copyWith(
                        fontSize: 32,
                        height: 38 / 32,
                        color: c.text,
                      ),
                    ),
                    TextSpan(
                      text: ' из $total',
                      style: text.copyWith(fontSize: 20, color: c.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Phone: «+N на следующей неделе» under the week, «Свернуть» once open.
class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Duration motion;
  const _Chip({
    required this.label,
    required this.onTap,
    this.motion = Duration.zero,
  });
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final text = Text(
      label,
      key: ValueKey(label),
      style: Theme.of(context).textTheme.bodyMedium!
          .copyWith(fontSize: 13, height: 18 / 13, color: c.text),
    );
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
          // «+N на следующей неделе» ↔ «Свернуть»: the chip eases to the
          // new width while the words cross-fade. AnimatedSize with a zero
          // duration re-dirties its own layout, so reduced motion skips it.
          child: motion == Duration.zero
              ? text
              : AnimatedSize(
                  duration: motion,
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: motion,
                    // One after the other, never both at once: the old words
                    // are gone in the first 40 %, the new ones come in after.
                    switchInCurve: const Interval(.4, 1, curve: Curves.easeOut),
                    switchOutCurve: const Interval(.6, 1, curve: Curves.easeIn),
                    child: text,
                  ),
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
