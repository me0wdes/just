import 'dart:async';

import 'package:flutter/widgets.dart';

import '../platform/feedback_service.dart';

/// Gives every route access to the interface tones without threading them
/// through each widget constructor.
class DaySound extends InheritedWidget {
  final CompletionFeedback feedback;
  const DaySound({super.key, required this.feedback, required super.child});
  static void play(BuildContext context, UiSound sound) {
    final feedback = context
        .getInheritedWidgetOfExactType<DaySound>()
        ?.feedback;
    if (feedback != null) {
      unawaited(feedback.play(sound).catchError((Object _) {}));
    }
  }

  @override
  bool updateShouldNotify(DaySound old) => feedback != old.feedback;
}
