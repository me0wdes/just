import 'package:flutter/material.dart';

import 'controls.dart';

import '../platform/feedback_service.dart';
import 'app_theme.dart';
import 'fluid_surface.dart';
import 'motion_tokens.dart';

/// Figma «Фильтры»: a grey track with equal tabs; the white pill slides to
/// the chosen tab.
class DaySegments extends StatelessWidget {
  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  const DaySegments({
    super.key,
    required this.index,
    required this.labels,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final colors = DayColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      // Phone: a 44 px tap target, like the other controls there.
      height: isPhone(context) ? 44 : 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.track,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              alignment: Alignment(
                labels.length == 1 ? 0 : -1 + 2 * index / (labels.length - 1),
                0,
              ),
              duration: MotionTokens.duration(
                context,
                const Duration(milliseconds: 260),
              ),
              curve: const Cubic(.2, 1.1, .3, 1),
              child: FractionallySizedBox(
                widthFactor: 1 / labels.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.pill,
                    // Concentric corners: track radius minus its padding.
                    borderRadius: BorderRadius.circular(12 - 4),
                    boxShadow: dark
                        ? null
                        : const [
                            BoxShadow(
                              color: Color(0x0f000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: FluidSurface(
                    sound: i == index ? null : UiSound.nav,
                    pressScale: .97,
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: MotionTokens.duration(
                                context,
                                MotionTokens.moderate,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Golos',
                                fontSize: 15,
                                height: 20 / 15,
                                fontWeight: FontWeight.w500,
                                color: i == index ? colors.text : colors.muted,
                              ),
                              child: Text(labels[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
