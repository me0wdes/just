import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sync/sync_engine.dart';
import 'app_theme.dart';
import 'day_icon.dart';

/// Figma «Статус синхронизации»: done, busy or error.
enum SyncMark { done, busy, error }

SyncMark syncMark(SyncState state) => switch (state) {
  SyncState.synced => SyncMark.done,
  SyncState.syncing || SyncState.localSaved => SyncMark.busy,
  _ => SyncMark.error,
};

Color syncTone(BuildContext context, SyncMark mark) {
  final c = DayColors.of(context);
  return switch (mark) {
    SyncMark.done => c.done,
    SyncMark.busy => c.muted,
    SyncMark.error => c.overdue,
  };
}

/// A check that draws itself in (400 ms), an arc that spins (900 ms a turn)
/// or a cross that strokes in (300 ms). Still when animations are off.
class SyncStatusIcon extends StatefulWidget {
  final SyncMark mark;
  final double size;
  final Color? color;
  const SyncStatusIcon(this.mark, {super.key, this.size = 16, this.color});
  @override
  State<SyncStatusIcon> createState() => _SyncStatusIconState();
}

class _SyncStatusIconState extends State<SyncStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  @override
  void didUpdateWidget(SyncStatusIcon old) {
    super.didUpdateWidget(old);
    if (old.mark != widget.mark) _run();
  }

  void _run() {
    if (MediaQuery.disableAnimationsOf(context)) {
      c.stop();
      c.value = 1;
      return;
    }
    switch (widget.mark) {
      case SyncMark.busy:
        c.duration = const Duration(milliseconds: 900);
        c.repeat();
      case SyncMark.done:
        c.duration = const Duration(milliseconds: 400);
        c.forward(from: 0);
      case SyncMark.error:
        c.duration = const Duration(milliseconds: 300);
        c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    excludeSemantics: true,
    child: AnimatedBuilder(
      animation: c,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _MarkPainter(
          widget.mark,
          widget.mark == SyncMark.busy
              ? c.value
              : Curves.easeOutCubic.transform(c.value),
          widget.color ?? syncTone(context, widget.mark),
        ),
      ),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  final SyncMark mark;
  final double t;
  final Color color;
  const _MarkPainter(this.mark, this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 16;
    canvas.scale(k);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // Seen as 2 px in the small cut-out, 1.5 px at full size.
      ..strokeWidth = (size.width <= 12 ? 2 : 1.5) / k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (mark) {
      case SyncMark.busy:
        canvas.drawCircle(
          const Offset(8, 8),
          6,
          Paint()
            ..color = color.withValues(alpha: color.a * .25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = pen.strokeWidth,
        );
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(8, 8), radius: 6),
          -math.pi / 2 + t * 2 * math.pi,
          math.pi / 2,
          false,
          pen,
        );
      case SyncMark.done:
        _partial(
          canvas,
          Path()
            ..moveTo(3, 8.5)
            ..lineTo(6.5, 12)
            ..lineTo(13, 4.5),
          t,
          pen,
        );
      case SyncMark.error:
        _partial(
          canvas,
          Path()
            ..moveTo(4, 4)
            ..lineTo(12, 12),
          (t * 2).clamp(0, 1),
          pen,
        );
        _partial(
          canvas,
          Path()
            ..moveTo(12, 4)
            ..lineTo(4, 12),
          (t * 2 - 1).clamp(0, 1),
          pen,
        );
    }
  }

  void _partial(Canvas canvas, Path path, double t, Paint pen) {
    if (t <= 0) return;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * t), pen);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.mark != mark || old.t != t || old.color != color;
}

/// Figma «Синхронизация · значок»: the cloud with the status in a small
/// cut-out at its corner. [cutout] is the colour behind it.
class SyncCloud extends StatelessWidget {
  final SyncMark mark;
  final Color cutout;
  const SyncCloud(this.mark, {super.key, required this.cutout});
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return SizedBox.square(
      dimension: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DayIcon(DayGlyph.cloud, size: 20, color: c.muted),
          Positioned(
            left: 10,
            top: 9,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: cutout, shape: BoxShape.circle),
              child: SyncStatusIcon(mark, size: 12),
            ),
          ),
        ],
      ),
    );
  }
}
