import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../platform/feedback_service.dart';
import 'day_sound.dart';
import 'motion_tokens.dart';

class FluidInteraction extends InheritedWidget {
  final double hover, press;
  const FluidInteraction({
    super.key,
    required this.hover,
    required this.press,
    required super.child,
  });
  static FluidInteraction? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FluidInteraction>();
  @override
  bool updateShouldNotify(FluidInteraction old) =>
      hover != old.hover || press != old.press;
}

/// Native controls retain their semantics, focus and keyboard behavior.
/// Only pointer feedback is animated; keyboard activation stays immediate.
class FluidSurface extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double pressScale;

  /// Played when a press is released over the surface; null stays silent
  /// for controls whose action has its own tone.
  final UiSound? sound;
  const FluidSurface({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressScale = .975,
    this.sound = UiSound.tap,
  });
  @override
  State<FluidSurface> createState() => _FluidSurfaceState();
}

class _FluidSurfaceState extends State<FluidSurface>
    with TickerProviderStateMixin {
  late final hover = AnimationController.unbounded(vsync: this),
      press = AnimationController.unbounded(vsync: this);
  bool hovered = false, pressed = false, reduce = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      hover.stop();
      press.stop();
      hover.value = hovered ? 1 : 0;
      press.value = pressed ? 1 : 0;
    }
  }

  void target(AnimationController controller, double value) {
    if (reduce) {
      controller.value = value;
      return;
    }
    controller.animateWith(
      SpringSimulation(
        MotionTokens.fastSpring,
        controller.value,
        value,
        controller.velocity,
      ),
    );
  }

  void reset() {
    hovered = false;
    pressed = false;
    target(hover, 0);
    target(press, 0);
  }

  @override
  void didUpdateWidget(FluidSurface old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) reset();
  }

  @override
  void dispose() {
    hover.dispose();
    press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (event) {
      if (widget.enabled && event.kind == PointerDeviceKind.mouse) {
        hovered = true;
        target(hover, 1);
      }
    },
    onExit: (_) {
      hovered = false;
      target(hover, 0);
    },
    child: Listener(
      onPointerDown: (event) {
        if (widget.enabled && event.buttons == kPrimaryButton) {
          pressed = true;
          target(press, 1);
        }
      },
      onPointerUp: (event) {
        final size = context.size;
        if (pressed &&
            widget.enabled &&
            widget.sound != null &&
            size != null &&
            (Offset.zero & size).contains(event.localPosition)) {
          DaySound.play(context, widget.sound!);
        }
        pressed = false;
        target(press, 0);
      },
      onPointerCancel: (_) {
        pressed = false;
        target(press, 0);
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([hover, press]),
        child: widget.child,
        builder: (context, child) => FluidInteraction(
          hover: hover.value.clamp(0, 1),
          press: press.value.clamp(0, 1),
          child: Transform.scale(
            scale: reduce
                ? 1
                : 1 - (1 - widget.pressScale) * press.value.clamp(0, 1),
            child: child,
          ),
        ),
      ),
    ),
  );
}
