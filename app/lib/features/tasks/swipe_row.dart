import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/day_icon.dart';
import '../../theme/motion_tokens.dart';

/// Figma «Свайп влево»: on a phone the card slides left and opens three
/// flat actions: edit, change list, delete. Past half of the way it
/// settles open, a long swipe to the far edge deletes at once (the toast
/// offers undo). A tap on the open card closes it.
class SwipeRow extends StatefulWidget {
  final Widget child;
  final VoidCallback onEdit, onMove, onDelete;
  const SwipeRow({
    super.key,
    required this.child,
    required this.onEdit,
    required this.onMove,
    required this.onDelete,
  });
  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow>
    with SingleTickerProviderStateMixin {
  /// Figma «Свайп влево»: the card moves 272, the actions hug their text
  /// (14 each side) with a 1x24 divider in an 8px gap between them.
  static const revealed = 272.0;

  /// How far the card has moved left, in pixels.
  late final shift = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 4000,
    value: 0,
  );
  bool _past = false;

  @override
  void dispose() {
    shift.dispose();
    super.dispose();
  }

  double get _width => (context.size?.width ?? 360);

  void _go(double to) => shift.animateTo(
    to,
    duration: MotionTokens.duration(context, MotionTokens.panel),
    curve: MotionTokens.easeOut,
  );

  void _close() => _go(0);

  void _update(DragUpdateDetails d) {
    shift.stop();
    shift.value = (shift.value - d.delta.dx).clamp(0.0, _width);
    final past = shift.value > _width * .62;
    if (past != _past) {
      _past = past;
      HapticFeedback.selectionClick();
    }
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (shift.value > _width * .62 || (v < -1800 && shift.value > revealed)) {
      _go(_width);
      widget.onDelete();
      return;
    }
    _go(shift.value > revealed / 2 && v < 600 ? revealed : 0);
    _past = false;
  }

  Widget _action(
    BuildContext context,
    String label,
    DayGlyph glyph,
    VoidCallback tap, {
    Color? color,
  }) {
    final c = DayColors.of(context);
    final tint = color ?? c.text;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _close();
          tap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              DayIcon(glyph, size: 22, color: tint),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontSize: 12,
                  height: 14 / 12,
                  color: tint,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return GestureDetector(
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: shift,
          builder: (context, child) {
            final x = shift.value;
            return Stack(
              fit: StackFit.passthrough,
              children: [
                if (x > 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      // The card never covers more of the row than its
                      // own width, so the actions keep a fixed size.
                      child: SizedBox(
                        width: revealed,
                        height: double.infinity,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _action(
                                context,
                                'Изменить',
                                DayGlyph.note,
                                widget.onEdit,
                              ),
                              _divider(c),
                              _action(
                                context,
                                'Список',
                                DayGlyph.listStack,
                                widget.onMove,
                              ),
                              _divider(c),
                              _action(
                                context,
                                'Удалить',
                                DayGlyph.delete,
                                widget.onDelete,
                                color: c.overdue,
                              ),
                            ],
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(-x, 0),
                  // Flat rows turn into a card once they slide.
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      DecoratedBox(
                        position: DecorationPosition.background,
                        decoration: x > 0
                            ? BoxDecoration(
                                color: c.card,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: c.border),
                              )
                            : const BoxDecoration(),
                        child: child!,
                      ),
                      // An open card only closes on a tap.
                      if (x > 8)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _close,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
          child: widget.child,
        ),
      ),
    );
  }

  Widget _divider(DayColors c) => SizedBox(
    width: 8,
    child: Center(child: Container(width: 1, height: 24, color: c.border)),
  );
}
