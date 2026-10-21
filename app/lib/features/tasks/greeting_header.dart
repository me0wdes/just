import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion_tokens.dart';

/// A FLOW preset: four stops and the drift speed from the gradient export.
@immutable
class FlowPalette {
  final List<Color> stops;
  final double speed;

  /// The export's "type": soft FLOW blobs or aurora ribbons.
  final bool aurora;
  const FlowPalette(this.stops, {this.speed = 26, this.aurora = false});
  static const roseGold = FlowPalette([
    Color(0xfffff4e8),
    Color(0xfffbc9ac),
    Color(0xffe79ba7),
    Color(0xff8e5a74),
  ]);
  static const solarFlare = FlowPalette([
    Color(0xfffff6de),
    Color(0xffffc24b),
    Color(0xfff4664d),
    Color(0xff8a2e5e),
  ], speed: 28);

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

  /// Morning 04–12 Rose gold, day 12–19 Solar flare, night 19–04.
  static FlowPalette forHour(int hour) => hour >= 4 && hour < 12
      ? roseGold
      : hour >= 12 && hour < 19
      ? solarFlare
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
      program.setFloat(i, palette.aurora ? 1 : 0);
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

/// The strip across the top of the window, like Unity Hub's announcement
/// banner: the live Rose gold field, the greeting in bold and a quiet line
/// about the day.
/// Figma «Шапка экрана»: the clean live field, with the title and date on
/// a small card (screen colour, radius 12, padding 20).
class ScreenHeader extends StatelessWidget {
  final String title, subtitle;
  final Widget? top;
  final bool phone;
  final DateTime? now;
  const ScreenHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.top,
    this.phone = false,
    this.now,
  });
  FlowPalette get palette => FlowPalette.forHour((now ?? DateTime.now()).hour);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DayColors.of(context);
    final card = _Entrance(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.screen,
          borderRadius: BorderRadius.circular(12),
        ),
        // AnimatedSize with a zero duration re-dirties its own layout in
        // Flutter, so reduced motion skips it altogether.
        child: _maybeAnimatedSize(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: MotionTokens.duration(context, MotionTokens.moderate),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, .15),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.bottomLeft,
                  children: [...previous, ?current],
                ),
                child: Text(
                  title,
                  key: ValueKey(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge!.copyWith(
                    color: colors.text,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(child: RoseGoldField(palette: palette)),
          ),
          Padding(
            // On a phone the field runs under the status bar.
            padding: phone
                ? EdgeInsets.fromLTRB(
                    20,
                    (top == null ? 20 : 10) + MediaQuery.paddingOf(context).top,
                    20,
                    20,
                  )
                // Figma: header 162, card 40 from the top and 34 from the bottom.
                : const EdgeInsets.fromLTRB(40, 40, 40, 34),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: double.infinity,
                minHeight: 0,
              ),
              // Figma: the card hugs on desktop and fills the width on a phone.
              child: Column(
                crossAxisAlignment: phone
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The bar is 48px for touch; its icons stay where the
                  // 28px row in Figma put them, and the card does too.
                  if (top != null) ...[top!, const SizedBox(height: 6)],
                  Flexible(child: card),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Copy rises into place once, when the window opens.
Widget _maybeAnimatedSize(BuildContext context, Widget child) =>
    MediaQuery.disableAnimationsOf(context)
    ? child
    : AnimatedSize(
        duration: MotionTokens.moderate,
        curve: MotionTokens.easeOut,
        alignment: Alignment.topLeft,
        child: child,
      );

class _Entrance extends StatelessWidget {
  final Widget child;
  const _Entrance({required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MotionTokens.duration(context, const Duration(milliseconds: 520)),
    curve: MotionTokens.easeOut,
    child: child,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child),
    ),
  );
}
