import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Alpha threshold: blurred letters with alpha above ~0.45 turn solid, so
/// overlapping blur sticks together into ink drops. [amp] 1 and [off] 0 is
/// the identity. Flutter's offsets are in 0–255.
ui.ColorFilter _threshold(double amp, double off) => ui.ColorFilter.matrix([
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, amp, off * 255,
]);

double _smooth(double v) {
  v = v.clamp(0.0, 1.0);
  return v * v * (3 - 2 * v);
}

/// Text from meowdes.tech, two effects in one:
/// * `goo-text-reveal` on first show: the line condenses out of ink blots
///   (blur 0.55em → 0 over 1.2 s, the threshold lifts in the last 35%);
/// * `goo-word-morph` when [swapKey] changes: the old text melts into drops
///   and the new one rises out of them (680 ms, the new one starts first).
class GooText extends StatefulWidget {
  final Widget child;
  final Object swapKey;
  final double fontSize;
  final Duration delay;
  const GooText({
    super.key,
    required this.child,
    required this.swapKey,
    required this.fontSize,
    this.delay = const Duration(milliseconds: 200),
  });
  @override
  State<GooText> createState() => _GooTextState();
}

class _GooTextState extends State<GooText> with TickerProviderStateMixin {
  static const _reveal = Duration(milliseconds: 1200),
      _morph = Duration(milliseconds: 680);
  static const _ease = Cubic(.25, 1, .5, 1);
  late final AnimationController reveal = AnimationController(
    vsync: this,
    duration: _reveal,
  );
  late final AnimationController morph = AnimationController(
    vsync: this,
    duration: _morph,
  );
  Widget? old;
  bool reduce = false;

  @override
  void initState() {
    super.initState();
    reveal.addListener(() => setState(() {}));
    morph.addListener(() => setState(() {}));
    morph.addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() => old = null);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      reveal.value = 1;
    } else if (!reveal.isAnimating && reveal.value == 0) {
      Future<void>.delayed(widget.delay, () {
        if (mounted) reveal.forward();
      });
    }
  }

  @override
  void didUpdateWidget(GooText previous) {
    super.didUpdateWidget(previous);
    if (previous.swapKey != widget.swapKey && !reduce) {
      old = previous.child;
      morph.forward(from: 0);
    }
  }

  @override
  void dispose() {
    reveal.dispose();
    morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // First show: blots condense into the line.
    if (reveal.value < 1) {
      final p = reveal.value;
      if (p == 0) return Opacity(opacity: 0, child: widget.child);
      final blur = widget.fontSize * .55 * (1 - _ease.transform(p));
      final goo = p < .65 ? 1.0 : (1 - p) / .35;
      return ImageFiltered(
        imageFilter: ui.ImageFilter.compose(
          outer: _threshold(1 + 19 * goo, -8 * goo),
          inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        ),
        child: widget.child,
      );
    }
    final previous = old;
    if (previous == null) return widget.child;
    // Morph: both layers on one spot under the threshold, so they flow.
    final p = morph.value, max = math.max(3.0, widget.fontSize * .3);
    final inc = _smooth(p / .82), out = _smooth((p - .18) / .82);
    Widget layer(Widget child, double opacity, double blur, double scale) =>
        Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
    return ImageFiltered(
      imageFilter: _threshold(18, -18 * .46),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The old one only shapes the drops; layout follows the new text.
          Positioned.fill(
            child: OverflowBox(
              maxWidth: double.infinity,
              child: layer(
                previous,
                math.pow(1 - out, .55).toDouble(),
                max * out,
                1 - out * .012,
              ),
            ),
          ),
          layer(
            widget.child,
            math.pow(inc, .55).toDouble(),
            max * (1 - inc),
            .988 + inc * .012,
          ),
        ],
      ),
    );
  }
}

/// `rolling-digits` from meowdes.tech: each digit is a drum that rolls to
/// the new value with a light spring; the window fades at top and bottom.
class RollingNumber extends StatelessWidget {
  final int value;
  final TextStyle style;
  const RollingNumber({super.key, required this.value, required this.style});
  @override
  Widget build(BuildContext context) {
    final digits = '$value'.split('');
    final height = (style.fontSize ?? 14) * (style.height ?? 1.2);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '$value',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          // A digit count change rebuilds the drums without rolling.
          key: ValueKey(digits.length),
          children: [
            for (final (i, d) in digits.indexed)
              TweenAnimationBuilder<double>(
                key: ValueKey(i),
                tween: Tween(end: double.parse(d)),
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 900),
                curve: const Cubic(.22, 1.2, .36, 1),
                builder: (context, at, _) => ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0xff000000),
                      Color(0xff000000),
                      Color(0x00000000),
                    ],
                    stops: [0, .14, .86, 1],
                  ).createShader(r),
                  child: SizedBox(
                    height: height,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        maxHeight: height * 10,
                        child: Transform.translate(
                          offset: Offset(0, -at * height),
                          child: Column(
                            children: [
                              for (var n = 0; n < 10; n++)
                                SizedBox(
                                  height: height,
                                  child: Text(
                                    '$n',
                                    style: style.copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `word-fade-up` from meowdes.tech: rises 10 px and fades in, [index]
/// times 30 ms after the first.
class FadeUp extends StatefulWidget {
  final int index;
  final Widget child;
  const FadeUp({super.key, required this.index, required this.child});
  @override
  State<FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<FadeUp> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      c.value = 1;
    } else if (c.value == 0 && !c.isAnimating) {
      Future<void>.delayed(Duration(milliseconds: 30 * widget.index), () {
        if (mounted) c.forward();
      });
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    child: widget.child,
    builder: (context, child) {
      final t = const Cubic(.2, .8, .2, 1).transform(c.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      );
    },
  );
}
