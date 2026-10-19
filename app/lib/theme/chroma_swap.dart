import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Changes content under a chromatic haze: a soft diagonal band sweeps
/// across, and the new child takes over beneath its densest part.
/// Port of the user's "chroma blur" reference; same timings.
class ChromaSwap extends StatefulWidget {
  final Object swapKey;
  final Widget child;

  /// Band colour, second colour inside the band, light fringe.
  final List<Color> colors;
  const ChromaSwap({
    super.key,
    required this.swapKey,
    required this.child,
    required this.colors,
  });
  static Future<ui.FragmentProgram>? _program;
  static Future<ui.FragmentProgram> load() =>
      _program ??= ui.FragmentProgram.fromAsset('shaders/chroma_blur.frag');
  @override
  State<ChromaSwap> createState() => _ChromaSwapState();
}

class _ChromaSwapState extends State<ChromaSwap>
    with SingleTickerProviderStateMixin {
  static const sweep = 1040, fade = 90;
  late final controller =
      AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: sweep + fade),
        )
        ..addListener(_tick)
        ..addStatusListener((_) {
          if (mounted) setState(() {});
        });
  ui.FragmentShader? shader;
  late Object shownKey = widget.swapKey;
  late Widget shown = widget.child;
  bool swapped = true;

  @override
  void initState() {
    super.initState();
    ChromaSwap.load().then((program) {
      if (mounted) setState(() => shader = program.fragmentShader());
    }, onError: (Object _) {});
  }

  double get elapsed => controller.value * (sweep + fade);
  double get progress =>
      1 - math.pow(1 - (elapsed / sweep).clamp(0.0, 1.0), 4).toDouble();
  double get alpha {
    final t = ((elapsed - sweep) / fade).clamp(0.0, 1.0);
    final eased = t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
    return 1 - eased;
  }

  void _tick() {
    // Swap when the band reaches the middle of the panel.
    if (!swapped && progress >= .5) {
      setState(() {
        swapped = true;
        shownKey = widget.swapKey;
        shown = widget.child;
      });
    }
  }

  @override
  void didUpdateWidget(ChromaSwap old) {
    super.didUpdateWidget(old);
    if (widget.swapKey == shownKey && swapped) {
      shown = widget.child;
      return;
    }
    if (widget.swapKey == old.swapKey) return;
    if (shader == null || MediaQuery.disableAnimationsOf(context)) {
      shownKey = widget.swapKey;
      shown = widget.child;
      swapped = true;
      return;
    }
    swapped = false;
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    controller.dispose();
    shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      KeyedSubtree(key: ValueKey(shownKey), child: shown),
      if (controller.isAnimating && shader != null)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CustomPaint(
                painter: _ChromaPainter(
                  shader!,
                  time: elapsed / 1000,
                  progress: progress,
                  alpha: alpha,
                  colors: widget.colors,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _ChromaPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time, progress, alpha;
  final List<Color> colors;
  _ChromaPainter(
    this.shader, {
    required this.time,
    required this.progress,
    required this.alpha,
    required this.colors,
  });
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, progress)
      ..setFloat(4, alpha)
      ..setFloat(5, .86)
      ..setFloat(6, 34);
    var i = 7;
    for (final c in colors.take(3)) {
      shader
        ..setFloat(i++, c.r)
        ..setFloat(i++, c.g)
        ..setFloat(i++, c.b);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ChromaPainter old) => true;
}
