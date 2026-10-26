import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/feedback_service.dart';
import 'app_theme.dart';
import 'day_icon.dart';
import 'day_sound.dart';
import 'fluid_surface.dart';
import 'motion_tokens.dart';

/// Controls after Fluid Functionalism: one 36px control height, surfaces
/// that shrink 1px per side when pressed (a scale would warp wide buttons),
/// presses that land in 80ms and release over 180ms.
enum DayButtonKind { primary, secondary, ghost }

const _release = Duration(milliseconds: 180),
    _press = Duration(milliseconds: 80);
const _releaseCurve = Cubic(.23, 1, .32, 1);
const controlHeight = 36.0;

/// Surface tints relative to the theme: hover and selected overlays.
Color overlay(BuildContext context, double light, double dark) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return (isDark ? Colors.white : Colors.black).withValues(
    alpha: isDark ? dark : light,
  );
}

class DayButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget? icon;
  final Widget? label;
  final DayButtonKind kind;
  final bool destructive, expand, active;
  final UiSound? sound;
  final String? tooltip;

  /// Side padding override, e.g. 10 to line up with a select trigger.
  final double? padding;
  const DayButton({
    super.key,
    required this.onPressed,
    this.icon,
    this.label,
    this.kind = DayButtonKind.primary,
    this.destructive = false,
    this.expand = false,
    this.active = false,
    this.sound = UiSound.tap,
    this.tooltip,
    this.padding,
  });
  const DayButton.icon({
    super.key,
    required this.onPressed,
    required Widget this.icon,
    this.tooltip,
    this.kind = DayButtonKind.ghost,
    this.sound = UiSound.tap,
  }) : label = null,
       padding = null,
       destructive = false,
       expand = false,
       active = false;
  @override
  State<DayButton> createState() => _DayButtonState();
}

class _DayButtonState extends State<DayButton> {
  bool hovered = false, pressed = false, focused = false;
  bool get enabled => widget.onPressed != null;

  void fire() {
    if (!enabled) return;
    if (widget.sound != null) DaySound.play(context, widget.sound!);
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final hot = hovered || widget.active;
    final fg = switch (widget.kind) {
      DayButtonKind.primary => c.screen,
      _ => widget.destructive ? c.overdue : c.text,
    };
    final bg = switch (widget.kind) {
      DayButtonKind.primary =>
        hot ? Color.lerp(c.text, c.screen, .14)! : c.text,
      DayButtonKind.secondary =>
        hot ? overlay(context, .09, .16) : overlay(context, .06, .11),
      DayButtonKind.ghost =>
        hot
            ? (widget.destructive
                  ? c.overdue.withValues(alpha: .08)
                  : overlay(context, .05, .07))
            : Colors.transparent,
    };
    final iconOnly = widget.label == null;
    // Phones get 44 px touch targets; computers keep the 36 px grid.
    final size = MediaQuery.sizeOf(context).width < 600 ? 44.0 : controlHeight;
    final inset = pressed && !reduce ? 1.0 : 0.0;
    Widget body = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null)
          IconTheme.merge(
            data: IconThemeData(color: fg, size: 18),
            child: widget.icon!,
          ),
        if (widget.icon != null && !iconOnly) const SizedBox(width: 6),
        if (!iconOnly)
          Flexible(
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontFamily: 'Golos',
                fontSize: 15,
                height: 20 / 15,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: widget.label!,
            ),
          ),
      ],
    );
    Widget button = FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => hovered = v),
      onShowFocusHighlight: (v) => setState(() => focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            fire();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => pressed = true) : null,
        onTapCancel: () => setState(() => pressed = false),
        onTapUp: (_) => setState(() => pressed = false),
        onTap: enabled ? fire : null,
        child: Semantics(
          button: true,
          enabled: enabled,
          child: SizedBox(
            height: size,
            width: iconOnly ? size : null,
            child: AnimatedContainer(
              duration: reduce ? Duration.zero : (pressed ? _press : _release),
              curve: pressed ? Curves.easeOut : _releaseCurve,
              margin: EdgeInsets.all(inset),
              padding: EdgeInsets.symmetric(
                horizontal: iconOnly
                    ? 0
                    : (widget.padding ?? (widget.icon != null ? 12 : 16)) -
                          inset,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10 - inset),
                border: focused ? Border.all(color: c.muted, width: 1.5) : null,
              ),
              child: Opacity(opacity: enabled ? 1 : .45, child: body),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// Field chrome after FF InputGroup: transparent at rest, a faint tint
/// while hovered, a card fill with a hairline ring while focused.
class DayField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final TextStyle? style;
  final int minLines, maxLines;
  final int? maxLength;
  final Key? fieldKey;
  const DayField({
    super.key,
    required this.controller,
    required this.hint,
    this.style,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.fieldKey,
  });
  @override
  State<DayField> createState() => _DayFieldState();
}

class _DayFieldState extends State<DayField> {
  final focus = FocusNode();
  bool hovered = false;
  @override
  void initState() {
    super.initState();
    focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final style =
        widget.style ??
        Theme.of(context).textTheme.bodyMedium!.copyWith(color: c.text);
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: focus.requestFocus,
        child: AnimatedContainer(
          duration: MotionTokens.duration(context, MotionTokens.fast),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: focus.hasFocus
                ? c.card
                : hovered
                ? overlay(context, .035, .05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: focus.hasFocus ? c.border : Colors.transparent,
            ),
          ),
          child: TextField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: focus,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            maxLength: widget.maxLength,
            style: style,
            cursorColor: c.text,
            // The chrome is the container above; the field draws nothing.
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              hintText: widget.hint,
              hintStyle: style.copyWith(color: c.muted),
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}

class DaySelectItem<T> {
  final T value;
  final String label;
  const DaySelectItem(this.value, this.label);
}

/// FF Select: a quiet trigger with a chevron, a popup that grows from the
/// trigger (opacity, scaleY .96, 4px slide; 80ms in, 60ms out), one hover
/// highlight that travels between rows, a selection marker that springs to
/// the pick, a check that draws itself, and a 300ms hold after a pick so
/// the acknowledgement is seen.
class DaySelect<T> extends StatefulWidget {
  final T? value;
  final List<DaySelectItem<T>> items;
  final ValueChanged<T> onChanged;
  final String placeholder;

  /// The value that means «nothing chosen» (e.g. «Без повтора»); it is
  /// shown in the muted colour, as Figma «Выбор / Пусто=Да».
  final T? emptyValue;

  /// Figma «Значение» rows (e.g. Список) look like plain values: no chevron.
  final bool arrow;
  const DaySelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.placeholder = 'Выбрать',
    this.emptyValue,
    this.arrow = true,
  });
  @override
  State<DaySelect<T>> createState() => _DaySelectState<T>();
}

class _DaySelectState<T> extends State<DaySelect<T>>
    with SingleTickerProviderStateMixin {
  final portal = OverlayPortalController();
  final link = LayerLink();
  final triggerKey = GlobalKey();
  late final popup = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    reverseDuration: const Duration(milliseconds: 60),
  );
  bool hovered = false, closing = false;
  int? highlight;
  T? picked;

  T? get current => picked ?? widget.value;
  int get checked => widget.items.indexWhere((i) => i.value == current);

  @override
  void didUpdateWidget(DaySelect<T> old) {
    super.didUpdateWidget(old);
    if (!portal.isShowing) picked = null;
  }

  @override
  void dispose() {
    popup.dispose();
    super.dispose();
  }

  void open() {
    if (portal.isShowing) {
      close();
      return;
    }
    DaySound.play(context, UiSound.open);
    picked = null;
    highlight = checked < 0 ? 0 : checked;
    closing = false;
    portal.show();
    MediaQuery.disableAnimationsOf(context)
        ? popup.value = 1
        : popup.forward(from: 0);
    setState(() {});
  }

  Future<void> close() async {
    if (!portal.isShowing || closing) return;
    closing = true;
    if (!MediaQuery.disableAnimationsOf(context)) await popup.reverse();
    if (!mounted) return;
    portal.hide();
    setState(() => closing = false);
  }

  Future<void> pick(int index) async {
    final item = widget.items[index];
    DaySound.play(context, UiSound.tap);
    setState(() => picked = item.value);
    widget.onChanged(item.value);
    // Hold so the check and the marker are seen landing.
    await Future<void>.delayed(
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
    );
    if (mounted) await close();
  }

  KeyEventResult onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || !portal.isShowing) return KeyEventResult.ignored;
    final n = widget.items.length;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => highlight = ((highlight ?? -1) + 1) % n);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => highlight = ((highlight ?? n) - 1 + n) % n);
    } else if (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.space) {
      if (highlight != null) pick(highlight!);
    } else if (e.logicalKey == LogicalKeyboardKey.escape) {
      close();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final label = checked < 0 ? null : widget.items[checked].label;
    final showing = portal.isShowing && !closing;
    return Focus(
      onKeyEvent: onKey,
      child: OverlayPortal(
        controller: portal,
        overlayChildBuilder: (_) => _popup(context),
        child: CompositedTransformTarget(
          link: link,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => hovered = true),
            onExit: (_) => setState(() => hovered = false),
            child: GestureDetector(
              key: triggerKey,
              behavior: HitTestBehavior.opaque,
              onTap: open,
              child: Semantics(
                button: true,
                value: label,
                child: AnimatedContainer(
                  duration: MotionTokens.duration(context, MotionTokens.fast),
                  height: controlHeight,
                  padding: const EdgeInsets.only(left: 10, right: 8),
                  decoration: BoxDecoration(
                    color: hovered || showing
                        ? overlay(context, .05, .07)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // Figma «Выбор» fills the row; the chevron sits at its end.
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label ?? widget.placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium!
                              .copyWith(
                                color:
                                    label == null ||
                                        (widget.emptyValue != null &&
                                            current == widget.emptyValue)
                                    ? c.muted
                                    : c.text,
                              ),
                        ),
                      ),
                      if (widget.arrow) ...[
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: showing ? .5 : 0,
                          duration: MotionTokens.duration(
                            context,
                            MotionTokens.moderate,
                          ),
                          curve: MotionTokens.easeOut,
                          child: DayIcon(
                            DayGlyph.down,
                            size: 16,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _popup(BuildContext context) {
    final c = DayColors.of(context);
    final box = triggerKey.currentContext?.findRenderObject() as RenderBox?;
    final width = (box?.size.width ?? 160).clamp(180.0, 320.0);
    const row = controlHeight;
    final moderate = MotionTokens.duration(context, MotionTokens.moderate);
    final fast = MotionTokens.duration(context, MotionTokens.fast);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: close,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomLeft,
          offset: const Offset(0, 4),
          child: Align(
            alignment: Alignment.topLeft,
            child: AnimatedBuilder(
              animation: popup,
              builder: (context, child) {
                final t = Curves.easeOut.transform(popup.value);
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, -4 * (1 - t)),
                    child: Transform(
                      alignment: Alignment.topCenter,
                      transform: Matrix4.diagonal3Values(1, .96 + .04 * t, 1),
                      child: child,
                    ),
                  ),
                );
              },
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  width: width,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: c.screen,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1f000000),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  // The overlay child rebuilds with this state, so setState
                  // is enough to move the highlight.
                  child: Builder(
                    builder: (context) {
                      void lit(int? i) => setState(() => highlight = i);

                      return MouseRegion(
                        onExit: (_) => lit(null),
                        child: Stack(
                          children: [
                            // Selection marker springs to the picked row.
                            if (checked >= 0)
                              AnimatedPositioned(
                                duration: moderate,
                                curve: MotionTokens.easeOut,
                                top: checked * row,
                                left: 0,
                                right: 0,
                                height: row,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: overlay(context, .07, .10),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            // One hover highlight travels between rows.
                            AnimatedPositioned(
                              duration: fast,
                              curve: Curves.easeOut,
                              top: (highlight ?? 0) * row,
                              left: 0,
                              right: 0,
                              height: row,
                              child: AnimatedOpacity(
                                opacity: highlight == null ? 0 : 1,
                                duration: fast,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: overlay(context, .04, .06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < widget.items.length; i++)
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    onEnter: (_) => lit(i),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => pick(i),
                                      child: SizedBox(
                                        height: row,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  widget.items[i].label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium!
                                                      .copyWith(
                                                        color: c.text,
                                                        fontWeight: i == checked
                                                            ? FontWeight.w600
                                                            : FontWeight.w400,
                                                      ),
                                                ),
                                              ),
                                              // Fixed slot: a check landing never
                                              // resizes the row.
                                              SizedBox(
                                                width: 16,
                                                child: TickMark(
                                                  shown: i == checked,
                                                  color: c.text,
                                                ),
                                              ),
                                            ],
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
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A tick that draws itself in (80ms easeOut) and erases faster (40ms).
class TickMark extends StatelessWidget {
  final bool shown;
  final Color color;
  const TickMark({super.key, required this.shown, required this.color});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: shown ? 1 : 0),
    duration: MotionTokens.duration(
      context,
      shown ? MotionTokens.fast : const Duration(milliseconds: 40),
    ),
    curve: shown ? Curves.easeOut : Curves.easeIn,
    builder: (context, t, _) =>
        CustomPaint(size: const Size(16, 16), painter: _TickPainter(t, color)),
  );
}

class _TickPainter extends CustomPainter {
  final double t;
  final Color color;
  _TickPainter(this.t, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final s = size.width;
    final path = Path()
      ..moveTo(s * .2, s * .52)
      ..lineTo(s * .42, s * .72)
      ..lineTo(s * .82, s * .3);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.t != t || old.color != color;
}

class DayMenuItem {
  final String label;
  final DayGlyph icon;
  final VoidCallback onTap;
  final bool destructive;
  const DayMenuItem(
    this.label,
    this.icon,
    this.onTap, {
    this.destructive = false,
  });
}

/// Context menu at the pointer, in the select popup's skin: grows in on
/// the fast tier, one hover highlight travels between rows.
Future<void> showDayMenu(
  BuildContext context,
  Offset position,
  List<DayMenuItem> items,
) {
  DaySound.play(context, UiSound.open);
  return Navigator.of(context).push(_MenuRoute(position, items));
}

class _MenuRoute extends PopupRoute<void> {
  final Offset position;
  final List<DayMenuItem> items;
  _MenuRoute(this.position, this.items);
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Закрыть меню';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 80);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 60);

  @override
  Widget buildPage(context, animation, secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    const width = 200.0;
    final height = items.length * controlHeight + 10;
    // Keep the panel on screen; flip left/up near the edges.
    final left = position.dx + width > size.width - 8
        ? position.dx - width
        : position.dx;
    final top = position.dy + height > size.height - 8
        ? position.dy - height
        : position.dy;
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: _MenuPanel(items: items, close: () => Navigator.pop(context)),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(context, animation, secondaryAnimation, child) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final t = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        child: child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, -4 * (1 - t.value)),
          child: Transform(
            alignment: Alignment.topLeft,
            transform: Matrix4.diagonal3Values(1, .96 + .04 * t.value, 1),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _MenuPanel extends StatefulWidget {
  final List<DayMenuItem> items;
  final VoidCallback close;
  const _MenuPanel({required this.items, required this.close});
  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> {
  int? highlight;
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final fast = MotionTokens.duration(context, MotionTokens.fast);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.screen,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1f000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: MouseRegion(
          onExit: (_) => setState(() => highlight = null),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: fast,
                curve: Curves.easeOut,
                top: (highlight ?? 0) * controlHeight,
                left: 0,
                right: 0,
                height: controlHeight,
                child: AnimatedOpacity(
                  opacity: highlight == null ? 0 : 1,
                  duration: fast,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: overlay(context, .05, .07),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.items.length; i++)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setState(() => highlight = i),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final item = widget.items[i];
                          if (!item.destructive) {
                            DaySound.play(context, UiSound.tap);
                          }
                          widget.close();
                          item.onTap();
                        },
                        child: SizedBox(
                          height: controlHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                DayIcon(
                                  widget.items[i].icon,
                                  size: 16,
                                  color: widget.items[i].destructive
                                      ? c.overdue
                                      : c.muted,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    widget.items[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium!
                                        .copyWith(
                                          color: widget.items[i].destructive
                                              ? c.overdue
                                              : c.text,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// FF-style grid of list icons: 36px cells, a hover tint and a selected
/// background; each icon plays its hover gesture under the pointer.
class DayIconGrid extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onPick;
  const DayIconGrid({super.key, required this.selected, required this.onPick});
  @override
  // As many 36 px cells per row as fit (Figma «Новый список»: nine), the
  // spare width shared between them; a popup with no width of its own
  // gets six per row with 4 px gaps.
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const compact = 6 * controlHeight + 5 * 4;
      final width = box.hasBoundedWidth ? box.maxWidth : compact;
      final perRow = math.max(1, ((width + 4) / (controlHeight + 4)).floor());
      final gap = perRow == 1
          ? 0.0
          // A hair under the exact share, so rounding never wraps a cell.
          : (width - perRow * controlHeight) / (perRow - 1) - .01;
      return SizedBox(
        width: width,
        child: Wrap(
          spacing: gap,
          runSpacing: 4,
          children: [
            for (final key in listIconKeys)
              _IconCell(
                key: ValueKey('list-icon-$key'),
                glyph: listGlyph(key),
                selected: key == selected,
                onTap: () => onPick(key),
              ),
          ],
        ),
      );
    },
  );
}

class _IconCell extends StatefulWidget {
  final DayGlyph glyph;
  final bool selected;
  final VoidCallback onTap;
  const _IconCell({
    super.key,
    required this.glyph,
    required this.selected,
    required this.onTap,
  });
  @override
  State<_IconCell> createState() => _IconCellState();
}

class _IconCellState extends State<_IconCell> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: FluidSurface(
          sound: UiSound.tap,
          pressScale: .9,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: MotionTokens.duration(context, MotionTokens.fast),
              width: controlHeight,
              height: controlHeight,
              decoration: BoxDecoration(
                color: widget.selected
                    ? overlay(context, .07, .10)
                    : hovered
                    ? overlay(context, .05, .07)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: DayIcon(
                  widget.glyph,
                  size: 20,
                  color: widget.selected || hovered ? c.text : c.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The icon picker as a popup at the pointer, in the menu skin.
Future<String?> showDayIconPicker(
  BuildContext context,
  Offset position,
  String current,
) {
  DaySound.play(context, UiSound.open);
  return Navigator.of(context).push(_IconPickerRoute(position, current));
}

class _IconPickerRoute extends PopupRoute<String> {
  final Offset position;
  final String current;
  _IconPickerRoute(this.position, this.current);
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Закрыть выбор иконки';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 80);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 60);
  @override
  Widget buildPage(context, animation, secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    const width = 6 * controlHeight + 5 * 4 + 16, height = 3 * 40 + 44.0;
    final left = (position.dx + width > size.width - 8)
        ? position.dx - width
        : position.dx;
    final top = (position.dy + height > size.height - 8)
        ? position.dy - height
        : position.dy;
    final c = DayColors.of(context);
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              decoration: BoxDecoration(
                color: c.screen,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1f000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 8),
                    child: Text(
                      'Иконка списка',
                      style: Theme.of(context).textTheme.bodySmall!
                          .copyWith(color: c.muted),
                    ),
                  ),
                  DayIconGrid(
                    selected: current,
                    onPick: (key) => Navigator.pop(context, key),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(context, animation, secondaryAnimation, child) {
    final t = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        child: child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, -4 * (1 - t.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Figma «Диалог»: a title, muted text and actions. The first action sits
/// on the left and the rest on the right; a lone action goes right.
class DayDialog extends StatelessWidget {
  final Widget title;
  final Widget? content;
  final List<Widget> actions;
  final double width;
  const DayDialog({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
    this.width = 400,
  });
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final text = Theme.of(context).textTheme;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DefaultTextStyle(
                style: text.titleMedium!.copyWith(
                  fontSize: 17,
                  height: 22 / 17,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
                child: title,
              ),
              if (content != null) ...[
                const SizedBox(height: 12),
                Flexible(
                  child: DefaultTextStyle(
                    style: text.bodyMedium!.copyWith(
                      fontSize: 15,
                      height: 21 / 15,
                      color: c.muted,
                    ),
                    child: content!,
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                // In a row when they fit (first left, the rest right); on a
                // narrow phone they stack, the main action on top.
                OverflowBar(
                  alignment: actions.length == 1
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.spaceBetween,
                  spacing: 8,
                  overflowSpacing: 8,
                  overflowAlignment: OverflowBarAlignment.end,
                  overflowDirection: VerticalDirection.up,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
