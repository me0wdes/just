import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/platform/feedback_service.dart';
import 'package:day_planner/features/settings/settings_controller.dart';
import 'package:day_planner/data/app_database.dart';

class Audio implements CompletionAudio {
  final played = <String>[];
  final volumes = <double>[];
  @override
  Future<void> play(String asset, double volume) async {
    played.add(asset);
    volumes.add(volume);
  }
}

class Policy implements SoundPolicy {
  bool enabled = true;
  @override
  Future<bool> mayPlay() async => enabled;
}

void main() {
  test('unavailable haptics do not suppress completion sound', () async {
    final db = AppDatabase.memory(workspaceId: 'local');
    try {
      final settings = SettingsController(db);
      await settings.load();
      final audio = Audio();
      final feedback = LocalCompletionFeedback(
        settings: settings,
        audio: audio,
        policy: Policy(),
        haptic: () async => throw UnsupportedError('No haptics'),
      );
      await feedback.onUserCompletion(undo: false);
      expect(audio.played, ['sounds/complete.wav']);
    } finally {
      await db.close();
    }
  });
  test('completion sound obeys device setting and system policy', () async {
    final db = AppDatabase.memory(workspaceId: 'local');
    try {
      final s = SettingsController(db);
      await s.load();
      final audio = Audio(), policy = Policy();
      final feedback = LocalCompletionFeedback(
        settings: s,
        audio: audio,
        policy: policy,
      );
      await feedback.onUserCompletion(undo: false);
      expect(audio.played, ['sounds/complete.wav']);
      await s.setSound(false);
      await feedback.onUserCompletion(undo: false);
      expect(audio.played.length, 1);
      await s.setSound(true);
      policy.enabled = false;
      await feedback.onUserCompletion(undo: true);
      expect(audio.played.length, 1);
      policy.enabled = true;
      await feedback.onUserCompletion(undo: true);
      expect(audio.played.last, 'sounds/undo.wav');
    } finally {
      await db.close();
    }
  });
  test(
    'interface tones share the sound switch and keep taps quieter',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local');
      try {
        final s = SettingsController(db);
        await s.load();
        final audio = Audio();
        final feedback = LocalCompletionFeedback(
          settings: s,
          audio: audio,
          policy: Policy(),
        );
        await feedback.play(UiSound.add);
        await feedback.play(UiSound.tap);
        await feedback.play(UiSound.toggleOn);
        expect(audio.played, [
          'sounds/add.wav',
          'sounds/tap.wav',
          'sounds/toggle_on.wav',
        ]);
        expect(audio.volumes[1], lessThan(audio.volumes[0]));
        await s.setSound(false);
        await feedback.play(UiSound.delete);
        expect(audio.played.length, 3);
      } finally {
        await db.close();
      }
    },
  );
}
