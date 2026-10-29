import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../features/settings/settings_controller.dart';

/// Short interface tones; each maps to `assets/sounds/<name>.wav`.
enum UiSound {
  tap,
  nav,
  add,
  complete,
  undo,
  delete,
  open,
  close,
  toggleOn('toggle_on'),
  toggleOff('toggle_off'),
  error;

  final String? _file;
  const UiSound([this._file]);
  String get asset => 'sounds/${_file ?? name}.wav';
}

abstract class CompletionFeedback {
  Future<void> onUserCompletion({required bool undo});

  /// Explicit user actions only; remote changes never call this.
  Future<void> play(UiSound sound);
}

class SilentCompletionFeedback implements CompletionFeedback {
  const SilentCompletionFeedback();
  @override
  Future<void> onUserCompletion({required bool undo}) async {}
  @override
  Future<void> play(UiSound sound) async {}
}

abstract interface class CompletionAudio {
  Future<void> play(String asset, double volume);
}

abstract interface class SoundPolicy {
  Future<bool> mayPlay();
}

class NativeSoundPolicy implements SoundPolicy {
  static const channel = MethodChannel('day/platform');
  @override
  Future<bool> mayPlay() async {
    try {
      return await channel.invokeMethod<bool>('feedbackAllowed') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// A few players per tone, used in turn so quick taps overlap instead of
/// cutting off; each one rewinds before it plays.
class AssetCompletionAudio implements CompletionAudio {
  static const _voices = 3;
  final _players = <String, List<AudioPlayer>>{};
  final _next = <String, int>{};

  List<AudioPlayer> _for(String asset) => _players[asset] ??= [
    for (var i = 0; i < _voices; i++)
      AudioPlayer()..setReleaseMode(ReleaseMode.stop),
  ];

  /// Copies every tone into the audio cache up front, so the first tap
  /// does not wait for it.
  void preload() {
    // Android: interface tones sound like a game's, on the media volume,
    // in vibrate mode too, and without pausing the music someone listens to.
    if (Platform.isAndroid) {
      AudioPlayer.global
          .setAudioContext(
            AudioContext(
              android: const AudioContextAndroid(
                contentType: AndroidContentType.sonification,
                usageType: AndroidUsageType.game,
                audioFocus: AndroidAudioFocus.none,
              ),
            ),
          )
          .ignore();
    }
    AudioCache.instance.loadAll([
      for (final s in UiSound.values) s.asset,
    ]).ignore();
  }

  /// Bluetooth headsets, USB DACs and many laptop codecs power down a moment
  /// after the last sound and swallow the start of the next one, which is
  /// all of a 30 ms tap: slow clicks went silent while quick bursts played.
  /// A looped silent clip keeps the output awake while Just is in front.
  AudioPlayer? _awake;
  Future<void> keepAwake(bool on) async {
    if (!(Platform.isWindows || Platform.isMacOS)) return;
    try {
      if (on) {
        final player = _awake ??= AudioPlayer()
          ..setReleaseMode(ReleaseMode.loop);
        if (player.state != PlayerState.playing) {
          await player.play(AssetSource('sounds/silence.wav'));
        }
      } else {
        await _awake?.pause();
      }
    } catch (_) {
      /* Taps still play; only the wake-up guard is missing. */
    }
  }

  @override
  Future<void> play(String asset, double volume) async {
    unawaited(keepAwake(true));
    final players = _for(asset);
    final i = _next[asset] ?? 0;
    _next[asset] = (i + 1) % players.length;
    final player = players[i];
    await player.stop();
    await player.play(AssetSource(asset), volume: volume);
  }

  Future<void> close() async {
    await _awake?.dispose();
    for (final players in _players.values) {
      for (final player in players) {
        await player.dispose();
      }
    }
  }
}

class LocalCompletionFeedback implements CompletionFeedback {
  final SettingsController settings;
  final CompletionAudio audio;
  final SoundPolicy policy;
  final Future<void> Function()? haptic;
  LocalCompletionFeedback({
    required this.settings,
    required this.audio,
    required this.policy,
    this.haptic,
  });
  DateTime? _checked;
  bool _allowed = false;

  // The platform check is a method channel call; taps are frequent, so reuse it briefly.
  Future<bool> _mayPlay() async {
    final now = DateTime.now();
    if (_checked == null || now.difference(_checked!).inMilliseconds > 1500) {
      _allowed = await policy.mayPlay();
      _checked = now;
    }
    return _allowed;
  }

  @override
  Future<void> play(UiSound sound) async {
    if (!settings.completionSoundEnabled || settings.volume <= 0) return;
    if (!await _mayPlay()) return;
    // Taps sit under the action tones so a busy session stays quiet.
    final quiet = sound == UiSound.tap || sound == UiSound.nav;
    await audio.play(sound.asset, settings.volume * (quiet ? .6 : 1));
  }

  @override
  Future<void> onUserCompletion({required bool undo}) async {
    if (!settings.completionSoundEnabled && !settings.hapticsEnabled) return;
    if (!await policy.mayPlay()) return;
    if (settings.hapticsEnabled && haptic != null) {
      try {
        await haptic!();
      } catch (_) {
        /* Sound remains independent of unavailable haptics. */
      }
    }
    if (settings.completionSoundEnabled && settings.volume > 0) {
      await audio.play(
        (undo ? UiSound.undo : UiSound.complete).asset,
        settings.volume,
      );
    }
  }
}
