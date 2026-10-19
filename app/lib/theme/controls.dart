import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/feedback_service.dart';
import 'app_theme.dart';
import 'day_icon.dart';
import 'day_sound.dart';
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
            height: controlHeight,
            width: iconOnly ? controlHeight : null,
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
  const DaySelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.placeholder = 'Выбрать',
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label ?? widget.placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium!
                              .copyWith(
                                color: label == null ? c.muted : c.text,
                              ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: showing ? .5 : 0,
                        duration: MotionTokens.duration(
                          context,
                          MotionTokens.moderate,
                        ),
                        curve: MotionTokens.easeOut,
                        child: DayIcon(DayGlyph.down, size: 16, color: c.muted),
                      ),
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

/// FF Combobox, multiple mode: chips in the trigger, a popup with a search
/// field on top, checkbox rows that keep the popup open, contiguous checked
/// rows sharing one merged background, and a create row appended last once
/// the query matches nothing.
class DayCombobox extends StatefulWidget {
  final Set<String> selected;
  final List<DaySelectItem<String>> items;
  final ValueChanged<Set<String>> onChanged;
  final Future<String?> Function(String name)? onCreate;
  final String placeholder;
  const DayCombobox({
    super.key,
    required this.selected,
    required this.items,
    required this.onChanged,
    this.onCreate,
    this.placeholder = 'Без списка',
  });
  @override
  State<DayCombobox> createState() => _DayComboboxState();
}

class _DayComboboxState extends State<DayCombobox>
    with SingleTickerProviderStateMixin {
  final portal = OverlayPortalController();
  final link = LayerLink();
  final triggerKey = GlobalKey();
  final query = TextEditingController();
  final field = FocusNode();
  late final popup = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    reverseDuration: const Duration(milliseconds: 60),
  );
  bool hovered = false, closing = false;
  int? highlight;
  late Set<String> picked = {...widget.selected};

  @override
  void didUpdateWidget(DayCombobox old) {
    super.didUpdateWidget(old);
    if (!portal.isShowing) picked = {...widget.selected};
  }

  @override
  void dispose() {
    popup.dispose();
    query.dispose();
    field.dispose();
    super.dispose();
  }

  List<DaySelectItem<String>> get visible {
    final q = query.text.trim().toLowerCase();
    return [
      for (final i in widget.items)
        if (q.isEmpty || i.label.toLowerCase().contains(q)) i,
    ];
  }

  bool get canCreate {
    final q = query.text.trim();
    return widget.onCreate != null &&
        q.isNotEmpty &&
        !widget.items.any((i) => i.label.toLowerCase() == q.toLowerCase());
  }

  void open() {
    if (portal.isShowing) {
      close();
      return;
    }
    DaySound.play(context, UiSound.open);
    picked = {...widget.selected};
    query.clear();
    highlight = 0;
    closing = false;
    portal.show();
    MediaQuery.disableAnimationsOf(context)
        ? popup.value = 1
        : popup.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => field.requestFocus());
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

  void toggle(String id) {
    DaySound.play(
      context,
      picked.contains(id) ? UiSound.toggleOff : UiSound.toggleOn,
    );
    setState(() => picked.contains(id) ? picked.remove(id) : picked.add(id));
    widget.onChanged({...picked});
  }

  Future<void> create() async {
    final name = query.text.trim();
    final id = await widget.onCreate?.call(name);
    if (id == null || !mounted) return;
    DaySound.play(context, UiSound.add);
    query.clear();
    setState(() => picked.add(id));
    widget.onChanged({...picked});
  }

  void choose(int index) {
    final rows = visible;
    if (index < rows.length) {
      toggle(rows[index].value);
    } else if (canCreate) {
      create();
    }
  }

  KeyEventResult onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || !portal.isShowing) return KeyEventResult.ignored;
    final n = visible.length + (canCreate ? 1 : 0);
    if (n == 0) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => highlight = ((highlight ?? -1) + 1) % n);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => highlight = ((highlight ?? n) - 1 + n) % n);
    } else if (e.logicalKey == LogicalKeyboardKey.enter) {
      if (highlight != null) choose(highlight!);
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
    final showing = portal.isShowing && !closing;
    final chosen = [
      for (final i in widget.items)
        if ((portal.isShowing ? picked : widget.selected).contains(i.value)) i,
    ];
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
                value: chosen.isEmpty
                    ? widget.placeholder
                    : chosen.map((i) => i.label).join(', '),
                child: AnimatedContainer(
                  duration: MotionTokens.duration(context, MotionTokens.fast),
                  constraints: const BoxConstraints(minHeight: controlHeight),
                  padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
                  decoration: BoxDecoration(
                    color: hovered || showing
                        ? overlay(context, .05, .07)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: chosen.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  widget.placeholder,
                                  style: Theme.of(context).textTheme.bodyMedium!
                                      .copyWith(color: c.muted),
                                ),
                              )
                            : Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  for (final i in chosen) _Chip(label: i.label),
                                ],
                              ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: showing ? .5 : 0,
                        duration: MotionTokens.duration(
                          context,
                          MotionTokens.moderate,
                        ),
                        curve: MotionTokens.easeOut,
                        child: DayIcon(DayGlyph.down, size: 16, color: c.muted),
                      ),
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
    final rows = visible;
    final create = canCreate;
    final count = rows.length + (create ? 1 : 0);
    const row = controlHeight;
    final fast = MotionTokens.duration(context, MotionTokens.fast);
    final moderate = MotionTokens.duration(context, MotionTokens.moderate);
    bool on(int i) =>
        i >= 0 && i < rows.length && picked.contains(rows[i].value);
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
                  width: 240,
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
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Search sits on top, its divider running edge to edge.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: TextField(
                          controller: query,
                          focusNode: field,
                          onChanged: (_) => setState(() => highlight = 0),
                          onSubmitted: (_) {
                            if (highlight != null) choose(highlight!);
                            field.requestFocus();
                          },
                          style: Theme.of(context).textTheme.bodyMedium!
                              .copyWith(color: c.text),
                          cursorColor: c.text,
                          decoration: InputDecoration(
                            isCollapsed: true,
                            filled: false,
                            hintText: 'Найти или создать',
                            hintStyle: TextStyle(color: c.muted),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      Divider(color: c.border, height: 1),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(4),
                          child: MouseRegion(
                            onExit: (_) => setState(() => highlight = null),
                            child: Stack(
                              children: [
                                // Checked runs share one merged background.
                                for (var i = 0; i < rows.length; i++)
                                  Positioned(
                                    top: i * row,
                                    left: 0,
                                    right: 0,
                                    height: row,
                                    child: AnimatedContainer(
                                      duration: moderate,
                                      curve: MotionTokens.easeOut,
                                      decoration: BoxDecoration(
                                        color: on(i)
                                            ? overlay(context, .07, .10)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(
                                            on(i - 1) ? 0 : 8,
                                          ),
                                          bottom: Radius.circular(
                                            on(i + 1) ? 0 : 8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                AnimatedPositioned(
                                  duration: fast,
                                  curve: Curves.easeOut,
                                  top: (highlight ?? 0).clamp(0, 999) * row,
                                  left: 0,
                                  right: 0,
                                  height: row,
                                  child: AnimatedOpacity(
                                    opacity:
                                        highlight == null || highlight! >= count
                                        ? 0
                                        : 1,
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
                                    for (var i = 0; i < count; i++)
                                      MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        onEnter: (_) =>
                                            setState(() => highlight = i),
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => choose(i),
                                          child: SizedBox(
                                            height: row,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              child: i < rows.length
                                                  ? Row(
                                                      children: [
                                                        _CheckBox(
                                                          checked: on(i),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            rows[i].label,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .textTheme
                                                                    .bodyMedium!
                                                                    .copyWith(
                                                                      color: c
                                                                          .text,
                                                                    ),
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  : Row(
                                                      children: [
                                                        DayIcon(
                                                          DayGlyph.add,
                                                          size: 16,
                                                          color: c.muted,
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            'Создать «${query.text.trim()}»',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .textTheme
                                                                    .bodyMedium!
                                                                    .copyWith(
                                                                      color: c
                                                                          .text,
                                                                    ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (count == 0)
                                      SizedBox(
                                        height: row,
                                        child: Center(
                                          child: Text(
                                            'Списков пока нет',
                                            style: TextStyle(color: c.muted),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
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
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: overlay(context, .06, .11),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Golos',
          fontSize: 14,
          height: 18 / 14,
          color: c.text,
        ),
      ),
    );
  }
}

/// FF CheckboxItem: a 16px outline with 5px corners that steps aside for
/// the tick alone when checked.
class _CheckBox extends StatelessWidget {
  final bool checked;
  const _CheckBox({required this.checked});
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final fast = MotionTokens.duration(context, MotionTokens.fast);
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        children: [
          AnimatedOpacity(
            opacity: checked ? 0 : 1,
            duration: fast,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: c.icon, width: 1.5),
              ),
            ),
          ),
          TickMark(shown: checked, color: c.text),
        ],
      ),
    );
  }
}
