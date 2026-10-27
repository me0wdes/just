import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Text that changes through a soft blur: the old one blurs out and fades,
/// the new one comes into focus (500 ms). On first show it focuses in the
/// same way. Plain blur only, light enough for any GPU.
class BlurSwap extends StatelessWidget {
  final Widget child;
  final Object swapKey;
  final Duration delay;

  /// Where the old and new text line up while both are on screen.
  final AlignmentGeometry alignment;
  const BlurSwap({
    super.key,
    required this.child,
    required this.swapKey,
    this.delay = Duration.zero,
    this.alignment = Alignment.center,
  });
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return _Intro(
      delay: delay,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) =>
            Stack(alignment: alignment, children: [...previous, ?current]),
        transitionBuilder: (child, animation) =>
            _Blur(animation: animation, child: child),
        child: KeyedSubtree(key: ValueKey(swapKey), child: child),
      ),
    );
  }
}

class _Blur extends AnimatedWidget {
  final Widget child;
  const _Blur({required Animation<double> animation, required this.child})
    : super(listenable: animation);
  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value.clamp(0.0, 1.0);
    final sigma = 6 * (1 - t);
    return Opacity(
      opacity: t,
      child: sigma < .05
          ? child
          : ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: child,
            ),
    );
  }
}

/// First show: the same focus-in, once.
class _Intro extends StatefulWidget {
  final Duration delay;
  final Widget child;
  const _Intro({required this.delay, required this.child});
  @override
  State<_Intro> createState() => _IntroState();
}

class _IntroState extends State<_Intro> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Blur(
    animation: CurvedAnimation(parent: c, curve: Curves.easeOut),
    child: widget.child,
  );
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
