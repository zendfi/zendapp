import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Handles incoming deep links for ZendApp.
///
/// Supported patterns:
///   https://zdfi.me/u/@{zendtag}                  → PWYW send flow
///   https://zdfi.me/u/@{zendtag}/{request_id}      → Fixed-amount send flow
///   zendapp://pay?zendtag=...&amount=...&request_id=...&note=...
///
/// Usage:
///   1. Call [DeepLinkHandler.init] once in main.dart
///   2. Listen to [DeepLinkHandler.stream] for incoming links
///   3. Each event is a [DeepLinkPayload] with the parsed parameters
class DeepLinkHandler {
  DeepLinkHandler._();

  static final _controller = StreamController<DeepLinkPayload>.broadcast();

  /// Stream of incoming deep link payloads.
  static Stream<DeepLinkPayload> get stream => _controller.stream;

  /// The initial link that launched the app (if any).
  static DeepLinkPayload? _initialLink;
  static DeepLinkPayload? get initialLink => _initialLink;

  static const _channel = MethodChannel('com.zendfi.zendapp/deep_links');

  static Future<void> init() async {
    // Listen for links while app is running
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final url = call.arguments as String?;
        if (url != null) {
          final payload = _parse(url);
          if (payload != null) _controller.add(payload);
        }
      }
    });

    // Check for initial link (app launched from a link)
    try {
      final initialUrl = await _channel.invokeMethod<String>('getInitialLink');
      if (initialUrl != null) {
        _initialLink = _parse(initialUrl);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('DeepLinkHandler: failed to get initial link: $e');
    }
  }

  static DeepLinkPayload? _parse(String url) {
    try {
      final uri = Uri.parse(url);

      // https://zdfi.me/u/@john_o
      // https://zdfi.me/u/@john_o/abc123
      if (uri.host == 'zdfi.me' && uri.pathSegments.isNotEmpty) {
        final segments = uri.pathSegments;
        if (segments.length >= 2 && segments[0] == 'u') {
          final rawTag = segments[1]; // '@john_o'
          final zendtag = rawTag.startsWith('@') ? rawTag.substring(1) : rawTag;
          final requestId = segments.length >= 3 ? segments[2] : null;
          final amount = uri.queryParameters['amount'] != null
              ? double.tryParse(uri.queryParameters['amount']!)
              : null;
          return DeepLinkPayload(
            zendtag: zendtag,
            requestId: requestId,
            amountUsdc: amount,
            note: uri.queryParameters['note'],
          );
        }
      }

      // zendapp://pay?zendtag=john_o&amount=10&request_id=abc123&note=...
      if (uri.scheme == 'zendapp' && uri.host == 'pay') {
        final zendtag = uri.queryParameters['zendtag'];
        if (zendtag == null || zendtag.isEmpty) return null;
        return DeepLinkPayload(
          zendtag: zendtag,
          requestId: uri.queryParameters['request_id'],
          amountUsdc: uri.queryParameters['amount'] != null
              ? double.tryParse(uri.queryParameters['amount']!)
              : null,
          note: uri.queryParameters['note'],
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('DeepLinkHandler: failed to parse "$url": $e');
    }
    return null;
  }

  static void dispose() {
    _controller.close();
  }
}

class DeepLinkPayload {
  final String zendtag;
  final String? requestId;
  final double? amountUsdc;
  final String? note;

  const DeepLinkPayload({
    required this.zendtag,
    this.requestId,
    this.amountUsdc,
    this.note,
  });

  @override
  String toString() =>
      'DeepLinkPayload(zendtag: $zendtag, requestId: $requestId, '
      'amountUsdc: $amountUsdc, note: $note)';
}
