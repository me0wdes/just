import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../platform/feedback_service.dart';
import 'day_sound.dart';
import 'motion_tokens.dart';

/// Flutter adaptation of Fluid Functionalism's pill thumb and reversible spring.
/// Parent owns the value; taps, keyboard and drags produce exactly one change.
class FluidSwitchTile extends StatefulWidget {
  final Widget title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;
  const FluidSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.contentPadding = EdgeInsets.zero,
  });
  @override
  State<FluidSwitchTile> createState() => _FluidSwitchTileState();
}

class _FluidSwitchTileState extends State<FluidSwitchTile>
    with TickerProviderStateMixin {
  late final position = AnimationController.unbounded(
        vsync: this,
        value: widget.value ? 1 : 0,
      ),
      shape = AnimationController.unbounded(vsync: this);
  final focus = FocusNode();
  bool hover = false,
      pressed = false,
      focused = false,
      reduced = false,
      dragging = false;
  double dragPosition = 0;
  bool get enabled => widget.onChanged != null;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      position.stop();
      shape.stop();
      position.value = widget.value ? 1 : 0;
      shape.value = pressed
          ? 1
          : hover
          ? .5
          : 0.0;
    }
  }

  void spring(
    AnimationController c,
    double target,
    SpringDescription description,
  ) {
    if (reduced) {
      c.value = target;
      return;
    }
    c.animateWith(SpringSimulation(description, c.value, target, c.velocity));
  }

  void settle() {
    spring(position, widget.value ? 1 : 0, MotionTokens.moderateSpring);
  }

  void shapeTarget() {
    spring(
      shape,
      pressed
          ? 1
          : hover
          ? .5
          : 0.0,
      MotionTokens.fastSpring,
    );
  }

  @override
  void didUpdateWidget(FluidSwitchTile old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !dragging) settle();
    if (!enabled) {
      dragging = false;
      pressed = false;
      hover = false;
      shapeTarget();
      settle();
    }
  }

  void toggle() {
    if (enabled) {
      focus.requestFocus();
      DaySound.play(
        context,
        widget.value ? UiSound.toggleOff : UiSound.toggleOn,
      );
      widget.onChanged!(!widget.value);
    }
  }

  @override
  void dispose() {
    position.dispose();
    shape.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      onTap: enabled ? toggle : null,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: focus,
        onShowFocusHighlight: (v) => setState(() => focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              toggle();
              return null;
            },
          ),
        },
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: MouseRegion(
          onEnter: (event) {
            if (enabled && event.kind == PointerDeviceKind.mouse) {
              hover = true;
              shapeTarget();
            }
          },
          onExit: (_) {
            hover = false;
            shapeTarget();
          },
          child: Listener(
            onPointerDown: (event) {
              if (enabled && event.buttons == kPrimaryButton) {
                pressed = true;
                shapeTarget();
              }
            },
            onPointerUp: (_) {
              pressed = false;
              shapeTarget();
            },
            onPointerCancel: (_) {
              pressed = false;
              shapeTarget();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? toggle : null,
              onHorizontalDragStart: enabled
                  ? (_) {
                      dragging = true;
                      position.stop();
                      dragPosition = position.value;
                    }
                  : null,
              onHorizontalDragUpdate: enabled
                  ? (details) {
                      dragPosition =
                          (dragPosition +
                                  details.delta.dx * (rtl ? -1 : 1) / 14)
                              .clamp(0, 1);
                      position.value = dragPosition;
                    }
                  : null,
              onHorizontalDragEnd: enabled
                  ? (_) {
                      dragging = false;
                      final next = dragPosition > .5;
                      if (next != widget.value) {
                        DaySound.play(
                          context,
                          next ? UiSound.toggleOn : UiSound.toggleOff,
                        );
                        widget.onChanged!(next);
                      }
                      spring(
                        position,
                        next ? 1 : 0,
                        MotionTokens.moderateSpring,
                      );
                    }
                  : null,
              onHorizontalDragCancel: enabled
                  ? () {
                      dragging = false;
                      settle();
                    }
                  : null,
              child: Padding(
                padding: widget.contentPadding,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([position, shape]),
                    builder: (context, _) {
                      final x = position.value.clamp(0, 1).toDouble(),
                          s = reduced ? 0.0 : shape.value.clamp(0, 1),
                          extra = 4 * s;
                      return Opacity(
                        opacity: enabled ? 1 : .45,
                        child: Row(
                          children: [
                            Expanded(
                              child: DefaultTextStyle(
                                style: Theme.of(context).textTheme.bodyLarge!
                                    .copyWith(
                                      color: widget.value
                                          ? colors.onSurface
                                          : colors.onSurfaceVariant,
                                    ),
                                child: widget.title,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Container(
                              key: const Key('fluid-switch-track'),
                              // FF geometry: 34×20 track, 16px thumb, 2px inset.
                              width: 34,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Color.lerp(
                                  colors.onSurfaceVariant.withValues(
                                    alpha: .38,
                                  ),
                                  colors.primary,
                                  x,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: focused
                                    ? Border.all(
                                        color: colors.onSurface,
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Transform.translate(
                                  offset: Offset(
                                    2 +
                                        (rtl ? 1 - x : x) * (14 - extra) +
                                        extra / 2,
                                    0,
                                  ),
                                  child: Transform.scale(
                                    scaleX: 1 + extra / 16,
                                    scaleY: 1 - 4 * s / 16,
                                    child: Container(
                                      key: const Key('fluid-switch-thumb'),
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        // Paper on an ink track when on, so
                                        // the thumb stays visible in dark.
                                        color: Color.lerp(
                                          Colors.white,
                                          colors.surface,
                                          x,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x16000000),
                                            blurRadius: 2,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
