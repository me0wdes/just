import 'package:flutter/material.dart';

abstract final class MotionTokens {
  // Fluid Functionalism tiers, translated to Flutter's physical springs.
  static const fast = Duration(milliseconds: 80),
      moderate = Duration(milliseconds: 160),
      slow = Duration(milliseconds: 240);
  static const fastExit = Duration(milliseconds: 60),
      moderateExit = Duration(milliseconds: 120),
      slowExit = Duration(milliseconds: 160);
  static final fastSpring = SpringDescription.withDurationAndBounce(
        duration: fast,
      ),
      moderateSpring = SpringDescription.withDurationAndBounce(
        duration: moderate,
      ),
      slowSpring = SpringDescription.withDurationAndBounce(
        duration: slow,
        bounce: .12,
      );
  static const check = Duration(milliseconds: 140),
      strike = Duration(milliseconds: 180),
      reflow = Duration(milliseconds: 220),
      panel = Duration(milliseconds: 240);
  static const easeOut = Cubic(.23, 1, .32, 1);

  /// Toasts, undo ones included, leave on their own after 3 s.
  static const toast = Duration(seconds: 3);
  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}
