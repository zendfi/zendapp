import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the Zend success chime on transfer completion.
class SoundService {
  static AudioPlayer? _player;
  static bool _initialized = false;

  /// Pre-warm the audio engine so the first play has no latency.
  /// Completely non-fatal — any error is swallowed silently.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      _player = AudioPlayer();

      // Set audio context to mix with other audio (don't duck music)
      // Only configure Android — iOS ambient category can throw on some setups
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );

      // Pre-load the asset
      await _player!.setSource(AssetSource('sounds/zent_success.wav'));
      _initialized = true;
    } catch (e) {
      // Audio is non-critical — log and continue
      if (kDebugMode) debugPrint('SoundService.init failed: $e');
      _initialized = false;
      _player = null;
    }
  }

  /// Play the "Zent It!" success chime. Fire and forget, never throws.
  static Future<void> playZentSuccess() async {
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.play(
        AssetSource('sounds/zent_success.wav'),
        volume: 0.85,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService.playZentSuccess failed: $e');
    }
  }
}
