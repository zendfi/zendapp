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

/// Plays pool-specific sounds for the Mission Room.
///
/// - Contribution chime: played when a pool_contribution SSE event arrives.
/// - Message notification: played when a pool_message arrives for a pool
///   the user is NOT currently viewing.
///
/// Both sounds respect device silent mode via the audioplayers package.
class PoolSoundService {
  static AudioPool? _contributionPool;
  static AudioPool? _messagePool;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      _contributionPool = await AudioPool.createFromAsset(
        path: 'sounds/pool_contribution.wav',
        maxPlayers: 2,
      );
      _messagePool = await AudioPool.createFromAsset(
        path: 'sounds/pool_message.wav',
        maxPlayers: 2,
      );
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('PoolSoundService.init failed: $e');
    }
  }

  /// Play the contribution chime (gentle, under 1 second).
  static Future<void> playContributionChime() async {
    try {
      if (!_initialized) await init();
      await _contributionPool?.start(volume: 0.7);
    } catch (e) {
      if (kDebugMode) debugPrint('PoolSoundService.playContributionChime failed: $e');
    }
  }

  /// Play the message notification sound (subtle, distinct from contribution chime).
  static Future<void> playMessageNotification() async {
    try {
      if (!_initialized) await init();
      await _messagePool?.start(volume: 0.5);
    } catch (e) {
      if (kDebugMode) debugPrint('PoolSoundService.playMessageNotification failed: $e');
    }
  }
}
