import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'greeting_header.dart' show FlowPalette;

/// What marks a new task among overdue ones: a thin gradient edge in the
/// header's palette and a soft comet that slowly circles it. [index] shifts
/// the comet so two cards never move in step.
@immutable
class BeamStyle {
  final FlowPalette palette;
  final int index;
  const BeamStyle(this.palette, this.index);
}

/// The comet and the hairline, painted over the card's own 1px border.
class BeamBorder extends StatefulWidget {
  final BeamStyle style;
  final Widget child;
  const BeamBorder({super.key, required this.style, required this.child});
  @override
  State<BeamBorder> createState() => _BeamBorderState();
}

class _BeamBorderState extends State<BeamBorder>
    with SingleTickerProviderStateMixin {
  // One turn takes 13 seconds: slow enough to stay in the background.
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 13),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
    } else if (!controller.isAnimating) {
      controller.repeat();
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      foregroundPainter: _BeamPainter(
        controller,
        widget.style.palette.stops,
        c.border,
        dark,
        widget.style.index.isOdd ? .5 : 0,
      ),
      child: widget.child,
    );
  }
}

class _BeamPainter extends CustomPainter {
  final Animation<double> turn;
  final List<Color> stops;
  final Color border;
  final bool dark;
  final double phase;
  _BeamPainter(this.turn, this.stops, this.border, this.dark, this.phase)
    : super(repaint: turn);

  static const radius = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final edge = RRect.fromRectAndRadius(
      rect.deflate(.5),
      const Radius.circular(radius - .5),
    );
    final g2 = stops[1], g3 = stops[2], g4 = stops[3];
    Color clear(Color c) => c.withValues(alpha: 0);

    // The edge itself: bright in the top left corner, gone by the bottom
    // right, so the card keeps its ordinary 1px border.
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            g2,
            Color.lerp(border, g3, .45)!,
            border,
            Color.lerp(border, g2, .4)!,
          ],
          stops: const [0, .38, .7, 1],
        ).createShader(rect),
    );

    // The comet. On white a pale head would vanish, so the light theme ends
    // it in the palette's deep colour; the dark theme keeps a white head.
    final angle = (turn.value + phase) * 2 * math.pi - math.pi / 2;
    final colors = dark
        ? [
            clear(g2),
            clear(g2),
            g2.withValues(alpha: .55 * .6),
            g3.withValues(alpha: .6),
            Colors.white.withValues(alpha: .6),
            clear(Colors.white),
            clear(Colors.white),
          ]
        : [
            clear(g2),
            clear(g2),
            g2.withValues(alpha: .7),
            g3,
            g4,
            clear(g4),
            clear(g4),
          ];
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = SweepGradient(
          colors: colors,
          stops: dark
              ? const [0, .66, .86, .91, .93, .95, 1]
              : const [0, .62, .82, .90, .94, .96, 1],
          transform: GradientRotation(angle),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_BeamPainter old) =>
      old.stops != stops ||
      old.border != border ||
      old.dark != dark ||
      old.phase != phase;
}

/// Soft light in the card's top left corner, under the text.
class BeamGlow extends StatelessWidget {
  final FlowPalette palette;
  const BeamGlow({super.key, required this.palette});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(painter: _GlowPainter(palette.stops[1], dark));
  }
}

class _GlowPainter extends CustomPainter {
  final Color color;
  final bool dark;
  const _GlowPainter(this.color, this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    // An ellipse 60% of the width wide and 70px tall, fading out at 70%.
    canvas.save();
    canvas.scale(size.width * .6, 70);
    final alpha = dark ? .38 : .27;
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()
        ..blendMode = dark ? BlendMode.screen : BlendMode.srcOver
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .7],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.color != color || old.dark != dark;
}
