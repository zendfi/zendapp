import 'dart:typed_data';

import 'f16.dart';

/// Which hand a palm template belongs to.
enum Hand {
  left,
  right;

  static Hand? tryParse(Object? v) => switch (v) {
        'left' => Hand.left,
        'right' => Hand.right,
        _ => null,
      };
}

/// Capture mode (contracts.md §6 `startCapture.mode`).
enum CaptureMode { enroll, pay }

/// Guide codes (contracts.md §6). [unknown] covers codes added later.
enum GuideCode {
  showPalm('show_palm'),
  moveCloser('move_closer'),
  moveBack('move_back'),
  tooDark('too_dark'),
  tooBright('too_bright'),
  holdStill('hold_still'),
  otherHand('other_hand'),
  ok('ok'),
  unknown('');

  const GuideCode(this.wire);
  final String wire;

  static GuideCode parse(Object? v) =>
      GuideCode.values.firstWhere((c) => c.wire == v && c != unknown,
          orElse: () => GuideCode.unknown);
}

/// Error codes (contracts.md §6). [unknown] covers codes added later.
enum ErrorCode {
  cameraDenied('camera_denied'),
  cameraFailed('camera_failed'),
  modelFailed('model_failed'),
  timeout('timeout'),
  unknown('');

  const ErrorCode(this.wire);
  final String wire;

  static ErrorCode parse(Object? v) =>
      ErrorCode.values.firstWhere((c) => c.wire == v && c != unknown,
          orElse: () => ErrorCode.unknown);
}

/// One palm template: f16×256 base64, L2-normalised.
class PalmTemplate {
  const PalmTemplate({required this.hand, required this.embedding});

  final Hand hand;
  final String embedding;

  Float32List decode() => F16.decodeBase64(embedding, expectedLength: 256);

  Map<String, Object?> toJson() => {'hand': hand.name, 'embedding': embedding};
}

class FlashFrame {
  const FlashFrame({required this.tUs, required this.rgb});

  /// Monotonic microseconds, decimal string (contracts.md §2.2).
  final String tUs;

  /// base64 of 96×96×3 RGB bytes, row-major.
  final String rgb;

  Map<String, Object?> toJson() => {'t_us': tUs, 'rgb': rgb};
}

class FlashShown {
  const FlashShown({required this.index, required this.tUs});

  /// Colour index; -1 = neutral white.
  final int index;
  final String tUs;

  Map<String, Object?> toJson() => {'index': index, 't_us': tUs};
}

class LandmarkFrame {
  const LandmarkFrame({required this.tUs, required this.points});

  final String tUs;

  /// base64 f16×63: 21 points × (x, y, z), MediaPipe-normalised.
  final String points;

  Map<String, Object?> toJson() => {'t_us': tUs, 'points': points};
}

/// The `flash` object of the /v1/scan payload (contracts.md §2.2).
class FlashPayload {
  const FlashPayload({
    required this.neutral,
    required this.frames,
    required this.shown,
    required this.landmarks,
  });

  final List<String> neutral;
  final List<FlashFrame> frames;
  final List<FlashShown> shown;
  final List<LandmarkFrame> landmarks;

  Map<String, Object?> toJson() => {
        'neutral': neutral,
        'frames': [for (final f in frames) f.toJson()],
        'shown': [for (final s in shown) s.toJson()],
        'landmarks': [for (final l in landmarks) l.toJson()],
      };

  static FlashPayload fromMap(Map<Object?, Object?> m) => FlashPayload(
        neutral: [for (final n in _list(m['neutral'])) n as String],
        frames: [
          for (final f in _list(m['frames']))
            FlashFrame(
                tUs: _us(_map(f)['t_us']), rgb: _map(f)['rgb'] as String),
        ],
        shown: [
          for (final s in _list(m['shown']))
            FlashShown(
                index: (_map(s)['index'] as num).toInt(),
                tUs: _us(_map(s)['t_us'])),
        ],
        landmarks: [
          for (final l in _list(m['landmarks']))
            LandmarkFrame(
                tUs: _us(_map(l)['t_us']),
                points: _map(l)['points'] as String),
        ],
      );
}

/// Events on `zend/ziro_vision/events`, discriminated by `type`.
sealed class ZiroVisionEvent {
  const ZiroVisionEvent();

  /// Parses one event map. Returns null for unknown `type` values.
  static ZiroVisionEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<Object?, Object?>();
    switch (m['type']) {
      case 'guide':
        return GuideEvent(GuideCode.parse(m['code']), rawCode: '${m['code']}');
      case 'ready_for_flash':
        return const ReadyForFlashEvent();
      case 'hand_done':
        final hand = Hand.tryParse(m['hand']);
        if (hand == null) return null;
        return HandDoneEvent(hand);
      case 'captured':
        return CapturedEvent.fromMap(m);
      case 'error':
        return ErrorEvent(ErrorCode.parse(m['code']), rawCode: '${m['code']}');
      default:
        return null;
    }
  }
}

class GuideEvent extends ZiroVisionEvent {
  const GuideEvent(this.code, {this.rawCode = ''});

  final GuideCode code;
  final String rawCode;

  @override
  String toString() => 'GuideEvent(${code.wire.isEmpty ? rawCode : code.wire})';
}

/// Dart paints neutral white (calls `flashShown(-1)`), then each colour for
/// `colourMs`, calling `flashShown(i)` right after each paint.
class ReadyForFlashEvent extends ZiroVisionEvent {
  const ReadyForFlashEvent();
}

class HandDoneEvent extends ZiroVisionEvent {
  const HandDoneEvent(this.hand);

  final Hand hand;
}

class CapturedEvent extends ZiroVisionEvent {
  const CapturedEvent({
    required this.modelVersion,
    required this.palms,
    required this.geometry,
    required this.face,
    required this.flash,
  });

  final String modelVersion;
  final List<PalmTemplate> palms;

  /// base64 f16×24, not normalised.
  final String geometry;

  /// base64 f16×512 or null.
  final String? face;

  /// Present only in pay mode.
  final FlashPayload? flash;

  static CapturedEvent fromMap(Map<Object?, Object?> m) {
    final palms = <PalmTemplate>[];
    for (final p in _list(m['palms'])) {
      final pm = _map(p);
      final hand = Hand.tryParse(pm['hand']);
      if (hand == null) {
        throw FormatException('bad hand: ${pm['hand']}');
      }
      palms.add(PalmTemplate(hand: hand, embedding: pm['embedding'] as String));
    }
    final flash = m['flash'];
    return CapturedEvent(
      modelVersion: m['model_version'] as String,
      palms: palms,
      geometry: m['geometry'] as String,
      face: m['face'] as String?,
      flash: flash is Map ? FlashPayload.fromMap(flash.cast()) : null,
    );
  }

  /// The template fields of the /v1/scan and /v1/enroll payloads
  /// (contracts.md §2.2): `model_version`, `palms`, `geometry`, `face`, and
  /// `flash` when present. Add `integrity` (scan) or `pin` (enroll).
  Map<String, Object?> toPayloadJson() => {
        'model_version': modelVersion,
        'palms': [for (final p in palms) p.toJson()],
        'geometry': geometry,
        'face': face,
        if (flash != null) 'flash': flash!.toJson(),
      };
}

class ErrorEvent extends ZiroVisionEvent {
  const ErrorEvent(this.code, {this.rawCode = ''});

  final ErrorCode code;
  final String rawCode;

  @override
  String toString() => 'ErrorEvent(${code.wire.isEmpty ? rawCode : code.wire})';
}

List<Object?> _list(Object? v) => v is List ? v : const [];

Map<Object?, Object?> _map(Object? v) =>
    v is Map ? v.cast<Object?, Object?>() : const {};

/// `t_us` values are decimal strings on the wire; ints are accepted too.
String _us(Object? v) => switch (v) {
      String s => s,
      int i => '$i',
      num n => '${n.toInt()}',
      _ => throw FormatException('bad t_us: $v'),
    };
