import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'events.dart';

/// Result of [ZiroVision.prepare].
class PrepareResult {
  const PrepareResult({required this.modelVersion, this.faceModelVersion});

  /// Palm model version, for example `palm-0` (stub) or `palm-1`.
  final String modelVersion;

  /// Face model version when a face detector is bundled, else null.
  final String? faceModelVersion;
}

/// Result of [ZiroVision.deviceKeyCreate]. Exactly one of [android] / [ios]
/// is set, matching the platform.
class DeviceKeyResult {
  const DeviceKeyResult({required this.publicKey, this.android, this.ios});

  /// SEC1 uncompressed P-256 public key (65 bytes), base64.
  final String publicKey;

  /// `{"key_attestation_chain": [b64 DER, …]}`.
  final Map<String, Object?>? android;

  /// `{"key_id", "attestation_object", "client_data_hash"}` (all base64).
  final Map<String, Object?>? ios;

  /// `{"device_pk", "platform", "android"?, "ios"?}` for `POST /devices`.
  Map<String, Object?> toRegisterJson() => {
        'device_pk': publicKey,
        'platform': android != null ? 'android' : 'ios',
        if (android != null) 'android': android,
        if (ios != null) 'ios': ios,
      };
}

/// Result of [ZiroVision.integrityToken].
class IntegrityResult {
  const IntegrityResult({this.token, this.assertion, this.clientDataHash});

  /// Android Play Integrity standard token.
  final String? token;

  /// iOS App Attest assertion (base64) and the client data hash it covers.
  final String? assertion;
  final String? clientDataHash;

  /// The `integrity` object of the /v1/scan payload (contracts.md §2.2).
  Map<String, Object?> toScanJson() => token != null
      ? {'platform': 'android', 'token': token}
      : {
          'platform': 'ios',
          'assertion': assertion,
          'client_data_hash': clientDataHash,
        };
}

/// Camera preview texture description (plugin extension, not in §6).
class PreviewInfo {
  const PreviewInfo({
    required this.textureId,
    required this.width,
    required this.height,
    required this.quarterTurns,
    required this.mirror,
  });

  final int textureId;

  /// Size of the texture buffer before [quarterTurns].
  final int width;
  final int height;

  /// Clockwise quarter turns Dart must apply.
  final int quarterTurns;

  /// Whether Dart must mirror horizontally (after rotating).
  final bool mirror;

  /// Aspect ratio of the displayed (rotated) preview.
  double get displayAspectRatio =>
      quarterTurns.isOdd ? height / width : width / height;
}

/// Dart side of the `ziro_vision` plugin (contracts.md §6).
///
/// Raw camera frames never cross this channel; only templates, small flash
/// crops and guide events do.
class ZiroVision {
  ZiroVision({MethodChannel? methodChannel, EventChannel? eventChannel})
      : _method = methodChannel ?? const MethodChannel(methodChannelName),
        _events = eventChannel ?? const EventChannel(eventChannelName);

  static const String methodChannelName = 'zend/ziro_vision';
  static const String eventChannelName = 'zend/ziro_vision/events';

  final MethodChannel _method;
  final EventChannel _events;
  Stream<ZiroVisionEvent>? _stream;

  /// Typed events. Unknown event types are dropped. Platform stream errors
  /// are delivered as [ErrorEvent] with [ErrorCode.unknown] or the code given.
  Stream<ZiroVisionEvent> get events => _stream ??= _events
      .receiveBroadcastStream()
      .transform(StreamTransformer<dynamic, ZiroVisionEvent>.fromHandlers(
        handleData: (raw, sink) {
          final e = ZiroVisionEvent.fromMap(raw);
          if (e != null) sink.add(e);
        },
        handleError: (error, stack, sink) {
          final code = error is PlatformException ? error.code : '';
          sink.add(ErrorEvent(ErrorCode.parse(code), rawCode: code));
        },
      ))
      .asBroadcastStream();

  /// Loads and warms models. Throws [PlatformException] with code
  /// `model_failed` when a required model is missing or invalid.
  Future<PrepareResult> prepare() async {
    final r = await _method.invokeMapMethod<String, Object?>('prepare');
    return PrepareResult(
      modelVersion: r?['model_version'] as String? ?? 'palm-0',
      faceModelVersion: r?['face_model_version'] as String?,
    );
  }

  /// Starts a capture session. In `pay` mode the first acceptable hand from
  /// [hands] is captured and the flash sequence follows; in `enroll` mode
  /// every hand in [hands] is captured in order, with `hand_done` between.
  Future<void> startCapture({
    required CaptureMode mode,
    List<Hand> hands = const [Hand.left, Hand.right],
    bool face = false,
    List<String> colours = const [],
    int colourMs = 120,
    Duration? timeout,
  }) {
    for (final c in colours) {
      if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(c)) {
        throw ArgumentError.value(c, 'colours', 'must be #RRGGBB');
      }
    }
    return _method.invokeMethod<void>('startCapture', {
      'mode': mode.name,
      'hands': [for (final h in hands) h.name],
      'face': face,
      'colours': colours,
      'colour_ms': colourMs,
      if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
    });
  }

  /// Call right after painting colour [index] (`-1` = neutral white).
  Future<void> flashShown(int index) =>
      _method.invokeMethod<void>('flashShown', {'index': index});

  Future<void> stopCapture() => _method.invokeMethod<void>('stopCapture');

  /// Creates (or replaces) the hardware P-256 device key under [alias].
  /// [challenge] (the 32-byte registration challenge from core) goes into the
  /// Android key attestation, or is used as the iOS App Attest client data
  /// hash as-is. Use alias `ziro_device`: iOS integrity assertions use it.
  Future<DeviceKeyResult> deviceKeyCreate({
    required String alias,
    required Uint8List challenge,
  }) async {
    final r = await _method.invokeMapMethod<String, Object?>('deviceKeyCreate', {
      'alias': alias,
      'challenge': base64.encode(challenge),
    });
    if (r == null) {
      throw PlatformException(code: 'key_failed', message: 'no result');
    }
    Map<String, Object?>? sub(Object? v) =>
        v is Map ? v.cast<String, Object?>() : null;
    return DeviceKeyResult(
      publicKey: r['public_key'] as String,
      android: sub(r['android']),
      ios: sub(r['ios']),
    );
  }

  /// ECDSA P-256 over SHA-256([data]), ASN.1 DER.
  Future<Uint8List> deviceKeySign({
    required String alias,
    required Uint8List data,
  }) async {
    final r = await _method.invokeMapMethod<String, Object?>('deviceKeySign', {
      'alias': alias,
      'data': base64.encode(data),
    });
    final sig = r?['signature'] as String?;
    if (sig == null) {
      throw PlatformException(code: 'key_failed', message: 'no signature');
    }
    return base64.decode(sig);
  }

  /// Per-charge integrity over [requestHash] = sha256(challenge_id ‖ nonce).
  Future<IntegrityResult> integrityToken({required Uint8List requestHash}) async {
    final r = await _method.invokeMapMethod<String, Object?>('integrityToken', {
      'request_hash': base64.encode(requestHash),
    });
    return IntegrityResult(
      token: r?['token'] as String?,
      assertion: r?['assertion'] as String?,
      clientDataHash: r?['client_data_hash'] as String?,
    );
  }

  /// Opens the camera (if needed) and returns the preview texture.
  Future<PreviewInfo> openPreview() async {
    final r = await _method.invokeMapMethod<String, Object?>('openPreview');
    if (r == null) {
      throw PlatformException(code: 'camera_failed', message: 'no preview');
    }
    return PreviewInfo(
      textureId: (r['texture_id'] as num).toInt(),
      width: (r['width'] as num).toInt(),
      height: (r['height'] as num).toInt(),
      quarterTurns: (r['quarter_turns'] as num? ?? 0).toInt(),
      mirror: r['mirror'] as bool? ?? false,
    );
  }

  /// Releases the preview texture. The camera stays on while a capture runs.
  Future<void> closePreview() => _method.invokeMethod<void>('closePreview');
}
