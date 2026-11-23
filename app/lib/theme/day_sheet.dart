import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'controls.dart' show isPhone;

/// Figma «Шторка»: a panel that rises from the bottom edge of a phone,
/// 28px top corners, a grabber and a half-black backdrop. Use it where a
/// centred dialog would sit awkwardly under a thumb.
Future<T?> showDaySheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .5),
  builder: (context) => DaySheet(child: builder(context)),
);

class DaySheet extends StatelessWidget {
  final Widget child;
  const DaySheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.pill,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: c.text.withValues(alpha: .28),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// A centred dialog on a computer, a bottom sheet on a phone, same content.
Future<T?> showDayPanel<T>(BuildContext context, WidgetBuilder builder) =>
    isPhone(context)
    ? showDaySheet<T>(context, builder: builder)
    : showDialog<T>(context: context, builder: builder);

/// The shell for [showDayPanel] content: a [Dialog] on a computer, bare
/// content on a phone (the sheet already draws the panel).
class DayPanel extends StatelessWidget {
  final Widget child;
  final Clip clipBehavior;
  final EdgeInsets? insetPadding;
  const DayPanel({
    super.key,
    required this.child,
    this.clipBehavior = Clip.none,
    this.insetPadding,
  });
  @override
  Widget build(BuildContext context) => isPhone(context)
      ? Material(type: MaterialType.transparency, child: Center(child: child))
      : Dialog(
          clipBehavior: clipBehavior,
          insetPadding: insetPadding,
          child: child,
        );
}
