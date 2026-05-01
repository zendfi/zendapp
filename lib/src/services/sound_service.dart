import 'package:audioplayers/audioplayers.dart';

/// Plays the Zend success chime on transfer completion.
///
/// Uses a single shared [AudioPlayer] instance — calling [playZentSuccess]
/// while it's already playing will restart from the beginning, which is the
/// right behaviour (user tapped send twice quickly).
class SoundService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _initialized = false;

  /// Pre-warm the audio engine so the first play has no latency.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Mix with other audio (don't duck music/podcasts)
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      ),
    );

    // Pre-load the asset so first play is instant
    await _player.setSource(AssetSource('sounds/zent_success.wav'));
  }

  /// Play the "Zent It!" success chime.
  /// Non-blocking — fire and forget.
  static Future<void> playZentSuccess() async {
    try {
      await _player.stop();
      await _player.play(
        AssetSource('sounds/zent_success.wav'),
        volume: 0.85,
      );
    } catch (_) {
      // Audio is non-critical — never let it crash the app
    }
  }
}
