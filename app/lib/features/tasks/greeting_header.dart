import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A FLOW preset: four stops and the drift speed from the gradient export.
@immutable
class FlowPalette {
  final List<Color> stops;
  final double speed;

  /// The export's "type": soft FLOW blobs, aurora ribbons or a sky.
  final bool aurora, sky;
  const FlowPalette(
    this.stops, {
    this.speed = 26,
    this.aurora = false,
    this.sky = false,
  });
  static const roseGold = FlowPalette([
    Color(0xfffff4e8),
    Color(0xfffbc9ac),
    Color(0xffe79ba7),
    Color(0xff8e5a74),
  ]);

  /// «Blue sky», sky type: deep blue above, misted at the horizon.
  static const blueSky = FlowPalette(
    [
      Color(0xffe6f2ff),
      Color(0xffb3d9ff),
      Color(0xff80b3ff),
      Color(0xff6699e6),
    ],
    speed: 22,
    sky: true,
  );

  /// «Northern lights», aurora type.
  static const night = FlowPalette(
    [
      Color(0xffeafff4),
      Color(0xff4be8a0),
      Color(0xff2e6e80),
      Color(0xff16224d),
    ],
    speed: 26,
    aurora: true,
  );

  /// Morning 04–12 Rose gold, day 12–19 Blue sky, night 19–04.
  static FlowPalette forHour(int hour) => hour >= 4 && hour < 12
      ? roseGold
      : hour >= 12 && hour < 19
      ? blueSky
      : night;
}

class RoseGoldField extends StatefulWidget {
  final FlowPalette palette;
  const RoseGoldField({super.key, this.palette = FlowPalette.roseGold});
  static Future<ui.FragmentProgram>? _program;
  static Future<ui.FragmentProgram> load() =>
      _program ??= ui.FragmentProgram.fromAsset('shaders/rose_gold.frag');
  @override
  State<RoseGoldField> createState() => _RoseGoldFieldState();
}

class _RoseGoldFieldState extends State<RoseGoldField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker ticker = createTicker(frame);
  final clock = ValueNotifier<double>(43.11694856000138);
  ui.FragmentShader? shader;
  Duration? previous;
  bool reduced = true, tickerEnabled = true, foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RoseGoldField.load().then(
      (program) {
        if (mounted) {
          setState(() => shader = program.fragmentShader());
          sync();
        }
      },
      onError: (Object error) {
        /* The provided CSS fallback stays visible if shaders are unavailable. */
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    tickerEnabled = TickerMode.valuesOf(context).enabled;
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    sync();
  }

  void sync() {
    final run = !reduced && tickerEnabled && foreground && shader != null;
    if (run && !ticker.isActive) {
      previous = null;
      ticker.start();
    }
    if (!run && ticker.isActive) {
      ticker.stop();
      previous = null;
    }
  }

  void frame(Duration elapsed) {
    final before = previous;
    if (before == null) {
      previous = elapsed;
      return;
    }
    final delta = elapsed - before;
    if (delta.inMicroseconds < 33333) return;
    previous = elapsed;
    // Same speed mapping as the user's engine: speed / 100 * 1.2.
    clock.value +=
        delta.inMicroseconds.clamp(0, 100000) /
        1000000 *
        widget.palette.speed /
        100 *
        1.2;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    shader?.dispose();
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _RoseGoldPainter(shader, clock, widget.palette),
      child: const SizedBox.expand(),
    ),
  );
}

class _RoseGoldPainter extends CustomPainter {
  final ui.FragmentShader? shader;
  final ValueNotifier<double> clock;
  final FlowPalette palette;
  _RoseGoldPainter(this.shader, this.clock, this.palette)
    : super(repaint: clock);
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size, program = shader;
    if (program != null) {
      program.setFloat(0, size.width);
      program.setFloat(1, size.height);
      program.setFloat(2, clock.value);
      var i = 3;
      for (final c in palette.stops) {
        program
          ..setFloat(i++, c.r)
          ..setFloat(i++, c.g)
          ..setFloat(i++, c.b);
      }
      program.setFloat(
        i,
        palette.aurora
            ? 1
            : palette.sky
            ? 2
            : 0,
      );
      canvas.drawRect(rect, Paint()..shader = program);
    } else {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: palette.stops,
            stops: const [.125, .375, .625, .875],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_RoseGoldPainter old) =>
      old.shader != shader || old.clock != clock || old.palette != palette;
}
