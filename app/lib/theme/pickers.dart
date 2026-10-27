import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../platform/feedback_service.dart';
import 'app_theme.dart';
import 'controls.dart';
import 'day_icon.dart';
import 'day_sound.dart';
import 'fluid_surface.dart';

const _months = [
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

/// Figma «Выбор даты»: a month with arrows, weekdays and a grid of
/// «День» cells; «Отмена» on the left, «Готово» on the right.
Future<DateTime?> showDayDatePicker(
  BuildContext context, {
  required DateTime initial,
}) => showDialog<DateTime>(
  context: context,
  builder: (_) => _DatePicker(initial),
);

class _DatePicker extends StatefulWidget {
  final DateTime initial;
  const _DatePicker(this.initial);
  @override
  State<_DatePicker> createState() => _DatePickerState();
}

class _DatePickerState extends State<_DatePicker> {
  late DateTime selected = DateUtils.dateOnly(widget.initial);
  late DateTime month = DateTime(selected.year, selected.month);

  void shift(int by) => setState(() {
    month = DateTime(month.year, month.month + by);
  });

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!;
    final today = DateUtils.dateOnly(DateTime.now());
    final offset = month.weekday - 1;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final rows = ((offset + days) / 7).ceil();
    Widget arrow(int by, String tip) => DayButton.icon(
      tooltip: tip,
      onPressed: () => shift(by),
      icon: RotatedBox(
        quarterTurns: by < 0 ? 1 : 3,
        child: DayIcon(DayGlyph.down, size: 18, color: c.text),
      ),
    );
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 7 * 40 + 32,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 7 * 40,
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '${_months[month.month - 1]} ${month.year}',
                          style: text.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: c.text,
                          ),
                        ),
                      ),
                    ),
                    arrow(-1, 'Прошлый месяц'),
                    arrow(1, 'Следующий месяц'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final w in const [
                    'Пн',
                    'Вт',
                    'Ср',
                    'Чт',
                    'Пт',
                    'Сб',
                    'Вс',
                  ])
                    SizedBox(
                      width: 40,
                      height: 28,
                      child: Center(
                        child: Text(
                          w,
                          style: text.copyWith(fontSize: 13, color: c.muted),
                        ),
                      ),
                    ),
                ],
              ),
              for (var r = 0; r < rows; r++)
                Row(
                  children: [
                    for (var k = 0; k < 7; k++)
                      () {
                        final day = r * 7 + k - offset + 1;
                        if (day < 1 || day > days) {
                          return const SizedBox(width: 40, height: 40);
                        }
                        final date = DateTime(month.year, month.month, day);
                        return _DayCell(
                          day: day,
                          selected: date == selected,
                          today: date == today,
                          onTap: () => setState(() => selected = date),
                        );
                      }(),
                  ],
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: 7 * 40,
                child: _Actions(
                  cancel: DayButton(
                    kind: DayButtonKind.ghost,
                    onPressed: () => Navigator.pop(context),
                    label: const Text('Отмена'),
                  ),
                  done: DayButton(
                    onPressed: () => Navigator.pop(context, selected),
                    label: const Text('Готово'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma «День»: plain, today (1 px ring), selected (filled) and hover.
class _DayCell extends StatelessWidget {
  final int day;
  final bool selected, today;
  final VoidCallback onTap;
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return FluidSurface(
      pressScale: .92,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Builder(
          builder: (context) {
            final hover = FluidInteraction.of(context)?.hover ?? 0;
            return Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? c.text
                    : Color.lerp(
                        Colors.transparent,
                        overlay(context, .05, .07),
                        hover,
                      ),
                border: today && !selected ? Border.all(color: c.muted) : null,
              ),
              child: Text(
                '$day',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? c.screen : c.text,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Figma «Выбор времени»: hour and minute boxes over a 24-hour dial (outer
/// ring 00–11, inner 12–23; minutes by five). [cancelText] on the left
/// returns null, which the due date reads as «only the date».
Future<TimeOfDay?> showDayTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
  String title = 'Время',
  String cancelText = 'Отмена',
}) => showDialog<TimeOfDay>(
  context: context,
  builder: (_) => _TimePicker(initial, title, cancelText),
);

class _TimePicker extends StatefulWidget {
  final TimeOfDay initial;
  final String title, cancelText;
  const _TimePicker(this.initial, this.title, this.cancelText);
  @override
  State<_TimePicker> createState() => _TimePickerState();
}

class _TimePickerState extends State<_TimePicker> {
  late int hour = widget.initial.hour, minute = widget.initial.minute;
  bool minutes = false;

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!;
    Widget box(int value, bool active, VoidCallback onTap) => Expanded(
      child: FluidSurface(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? c.pill : c.input,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? c.text : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Text(
              value.toString().padLeft(2, '0'),
              style: text.copyWith(
                fontSize: 40,
                height: 1.2,
                color: c.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 328,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: text.copyWith(fontSize: 13, color: c.muted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  box(hour, !minutes, () => setState(() => minutes = false)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      ':',
                      style: text.copyWith(fontSize: 40, color: c.muted),
                    ),
                  ),
                  box(minute, minutes, () => setState(() => minutes = true)),
                ],
              ),
              const SizedBox(height: 16),
              _Dial(
                value: minutes ? minute : hour,
                minutes: minutes,
                onChanged: (v) => setState(() {
                  if (minutes) {
                    minute = v;
                  } else {
                    hour = v;
                  }
                }),
                onDone: () {
                  DaySound.play(context, UiSound.tap);
                  // Picking the hour moves on to minutes, as on the dial.
                  if (!minutes) setState(() => minutes = true);
                },
              ),
              const SizedBox(height: 16),
              _Actions(
                cancel: DayButton(
                  kind: DayButtonKind.ghost,
                  onPressed: () => Navigator.pop(context),
                  label: Text(widget.cancelText),
                ),
                done: DayButton(
                  onPressed: () => Navigator.pop(
                    context,
                    TimeOfDay(hour: hour, minute: minute),
                  ),
                  label: const Text('Готово'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dial extends StatelessWidget {
  static const size = 256.0, outer = 104.0, inner = 68.0;
  final int value;
  final bool minutes;
  final ValueChanged<int> onChanged;
  final VoidCallback onDone;
  const _Dial({
    required this.value,
    required this.minutes,
    required this.onChanged,
    required this.onDone,
  });

  void pick(Offset local) {
    final d = local - const Offset(size / 2, size / 2);
    var angle = math.atan2(d.dx, -d.dy);
    if (angle < 0) angle += 2 * math.pi;
    if (minutes) {
      onChanged((angle / (2 * math.pi) * 60).round() % 60);
    } else {
      final step = (angle / (2 * math.pi) * 12).round() % 12;
      onChanged(d.distance < (outer + inner) / 2 ? step + 12 : step);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanDown: (e) => pick(e.localPosition),
    onPanUpdate: (e) => pick(e.localPosition),
    onPanEnd: (_) => onDone(),
    onTapUp: (_) => onDone(),
    child: CustomPaint(
      size: const Size.square(size),
      painter: _DialPainter(
        value: value,
        minutes: minutes,
        colors: DayColors.of(context),
        style: Theme.of(context).textTheme.bodyMedium!,
      ),
    ),
  );
}

class _DialPainter extends CustomPainter {
  final int value;
  final bool minutes;
  final DayColors colors;
  final TextStyle style;
  _DialPainter({
    required this.value,
    required this.minutes,
    required this.colors,
    required this.style,
  });

  Offset at(double turns, double radius) {
    final a = turns * 2 * math.pi;
    return Offset(
      _Dial.size / 2 + radius * math.sin(a),
      _Dial.size / 2 - radius * math.cos(a),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas.drawCircle(centre, size.width / 2, Paint()..color = colors.input);
    final knob = minutes
        ? at(value / 60, _Dial.outer)
        : at((value % 12) / 12, value >= 12 ? _Dial.inner : _Dial.outer);
    final ink = Paint()..color = colors.text;
    canvas.drawLine(centre, knob, ink..strokeWidth = 2);
    canvas.drawCircle(centre, 4, ink);
    canvas.drawCircle(knob, 18, ink);
    void label(String text, Offset where, double fontSize, Color color) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(fontSize: fontSize, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        where - Offset(painter.width / 2, painter.height / 2),
      );
    }

    if (minutes) {
      for (var m = 0; m < 60; m += 5) {
        label(
          m.toString().padLeft(2, '0'),
          at(m / 60, _Dial.outer),
          15,
          m == value ? colors.screen : colors.text,
        );
      }
      // Between the fives the knob carries a dot instead of a number.
      if (value % 5 != 0) {
        canvas.drawCircle(knob, 3, Paint()..color = colors.screen);
      }
      return;
    }
    for (var h = 0; h < 24; h++) {
      final innerRing = h >= 12;
      label(
        h == 0 ? '00' : '$h',
        at((h % 12) / 12, innerRing ? _Dial.inner : _Dial.outer),
        innerRing ? 13 : 15,
        h == value
            ? colors.screen
            : innerRing
            ? colors.muted
            : colors.text,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.value != value || old.minutes != minutes || old.colors != colors;
}

/// Cancel on the left, done on the right; a phone splits the width between
/// them so both are wide thumb targets.
class _Actions extends StatelessWidget {
  final Widget cancel, done;
  const _Actions({required this.cancel, required this.done});
  @override
  Widget build(BuildContext context) => MediaQuery.sizeOf(context).width < 600
      ? Row(
          children: [
            Expanded(child: cancel),
            const SizedBox(width: 8),
            Expanded(child: done),
          ],
        )
      : Row(children: [cancel, const Spacer(), done]);
}
