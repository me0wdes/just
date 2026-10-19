import 'package:flutter/material.dart';

import '../platform/feedback_service.dart';
import 'controls.dart';

/// Button shorthands over [DayButton]: primary, secondary (tonal) and ghost
/// (text). Kept so existing call sites read the same.
class FluidButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final DayButtonKind kind;
  final UiSound? sound;
  const FluidButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.sound = UiSound.tap,
  }) : kind = DayButtonKind.primary,
       icon = null;
  const FluidButton.tonal({
    super.key,
    required this.onPressed,
    required this.child,
    this.sound = UiSound.tap,
  }) : kind = DayButtonKind.secondary,
       icon = null;
  const FluidButton.text({
    super.key,
    required this.onPressed,
    required this.child,
    this.sound = UiSound.tap,
  }) : kind = DayButtonKind.ghost,
       icon = null;
  const FluidButton.textIcon({
    super.key,
    required this.onPressed,
    required Widget this.icon,
    required Widget label,
    this.sound = UiSound.tap,
  }) : kind = DayButtonKind.ghost,
       child = label;
  @override
  Widget build(BuildContext context) => DayButton(
    onPressed: onPressed,
    kind: kind,
    icon: icon,
    label: child,
    sound: sound,
  );
}

class FluidIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? tooltip;
  final Widget icon;
  final UiSound? sound;
  const FluidIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.sound = UiSound.tap,
  });
  @override
  Widget build(BuildContext context) => DayButton.icon(
    onPressed: onPressed,
    icon: icon,
    tooltip: tooltip,
    sound: sound,
  );
}
