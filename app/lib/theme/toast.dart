import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'motion_tokens.dart';

/// Figma «Уведомление»: a dark pill with the message and an optional action.
/// On a phone it drops in under the status bar, where the keyboard and the
/// composer are not; on a computer it rises from the bottom with a margin
/// above the composer. One at a time; it leaves by itself.
class DayToast {
  static final _shown = <GlobalKey<_ToastState>>[];

  static void show(
    BuildContext context,
    String message, {
    String? action,
    VoidCallback? onAction,
    Duration duration = MotionTokens.toast,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    hide();
    final phone = MediaQuery.sizeOf(context).width < 600;
    final key = GlobalKey<_ToastState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Toast(
        key: key,
        message: message,
        action: action,
        onAction: onAction,
        top: phone,
        duration: duration,
        onGone: () {
          if (entry.mounted) entry.remove();
          _shown.remove(key);
        },
      ),
    );
    _shown.add(key);
    overlay.insert(entry);
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }

  /// Takes the current one away, e.g. before showing a newer one.
  static void hide() {
    for (final key in [..._shown]) {
      key.currentState?.close();
    }
  }
}

class _Toast extends StatefulWidget {
  final String message;
  final String? action;
  final VoidCallback? onAction;
  final bool top;
  final Duration duration;
  final VoidCallback onGone;
  const _Toast({
    super.key,
    required this.message,
    required this.action,
    required this.onAction,
    required this.top,
    required this.duration,
    required this.onGone,
  });
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  );
  Timer? timer;
  bool closing = false;

  @override
  void initState() {
    super.initState();
    c.forward();
    timer = Timer(widget.duration, close);
  }

  void close() {
    if (closing) return;
    closing = true;
    timer?.cancel();
    if (!mounted) return widget.onGone();
    c.reverse().whenComplete(widget.onGone);
  }

  @override
  void dispose() {
    timer?.cancel();
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduce = media.disableAnimations;
    final t = reduce
        ? c
        : CurvedAnimation(parent: c, curve: Curves.easeOutCubic);
    final card = Material(
      color: const Color(0xff2a2a2a),
      borderRadius: BorderRadius.circular(10),
      elevation: 6,
      shadowColor: const Color(0x33000000),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, widget.action == null ? 16 : 6, 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Color(0xffededed),
                      fontSize: 14,
                      fontFamily: 'Golos',
                    ),
                  ),
                ),
              ),
              if (widget.action != null)
                TextButton(
                  onPressed: () {
                    widget.onAction?.call();
                    close();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xff8cb8ff),
                    textStyle: const TextStyle(
                      fontFamily: 'Golos',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: Text(widget.action!),
                ),
            ],
          ),
        ),
      ),
    );
    return Positioned(
      left: 16,
      right: 16,
      top: widget.top ? media.padding.top + 12 : null,
      // Desktop: above the composer, not flush with the window edge.
      bottom: widget.top ? null : media.padding.bottom + 96,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Semantics(
              liveRegion: true,
              child: Dismissible(
                key: ObjectKey(this),
                direction: widget.top
                    ? DismissDirection.up
                    : DismissDirection.down,
                onDismissed: (_) {
                  closing = true;
                  timer?.cancel();
                  widget.onGone();
                },
                child: FadeTransition(
                  opacity: t,
                  child: SlideTransition(
                    position: Tween(
                      begin: Offset(0, widget.top ? -.6 : .6),
                      end: Offset.zero,
                    ).animate(t),
                    child: card,
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
