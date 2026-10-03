import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Gene - Oct 3, 2026: Audio and haptic alert service for new work dispatches and assignments.
class SoundService {
  /// The shared instance. Not final so tests can install a mock or no-op instance.
  static SoundService instance = SoundService();

  AudioPlayer? _player;
  bool isEnabled = true;

  SoundService({AudioPlayer? player}) : _player = player;

  static bool get isRunningInTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  AudioPlayer get player => _player ??= AudioPlayer();

  /// Plays the distinct dispatch chime and triggers heavy haptic vibration.
  Future<void> playAlertSound() async {
    if (!isEnabled) return;
    try {
      // 1. Play haptic feedback
      HapticFeedback.heavyImpact().catchError((_) {});

      // 2. Play high-quality bundled alert chime
      if (isRunningInTest && _player == null) {
        // Skip instantiating un-mocked AudioPlayer platform channels in headless test runs
        return;
      }

      final p = player;
      try {
        await p.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.duckOthers,
            },
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ));
      } catch (_) {
        // AudioContext setup might not be supported in mock or desktop environments
      }

      await p.stop();
      await p.play(AssetSource('sounds/dispatch_alert.wav'));
    } catch (_) {
      // Gracefully fall back to system sound if audio engine encounters an issue
      try {
        SystemSound.play(SystemSoundType.alert).catchError((_) {});
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
