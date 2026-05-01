import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the Zend success chime on transfer completion.
///
/// Uses AudioPool for low-latency, reliable playback on Android.
/// AudioPool pre-loads the sound into a SoundPool (Android native)
/// which avoids the MediaPlayer lifecycle issues.
class SoundService {
  static AudioPool? _pool;
  static bool _initialized = false;

  /// Pre-load the sound into a native SoundPool for instant playback.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      _pool = await AudioPool.createFromAsset(
        path: 'sounds/zent_success.wav',
        maxPlayers: 2,
      );
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService.init failed: $e');
    }
  }

  /// Play the "Zent It!" success chime. Fire and forget, never throws.
  static Future<void> playZentSuccess() async {
    try {
      if (_pool == null) await init();
      await _pool?.start(volume: 0.85);
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService.playZentSuccess failed: $e');
    }
  }
}
