import 'package:flutter/foundation.dart';

/// Product events for the revamp's success metrics (time to first send,
/// send completion, emoji share, reactions, receipts opened).
///
/// Events are named here once so call sites can't drift. There is no
/// analytics backend yet: [sink] defaults to a debug log, and wiring a real
/// provider later is a one-line assignment in main.dart. Never put PII
/// (names, handles, emails) in [props].
enum ZendEvent {
  signInCompleted,
  sendStarted,
  sendCompleted,
  sendFailed,
  emojiAdded,
  reactionAdded,
  receiptOpened,
}

abstract final class ZendAnalytics {
  static void Function(ZendEvent event, Map<String, Object> props) sink =
      (e, p) {
        if (kDebugMode) debugPrint('[analytics] ${e.name} $p');
      };

  static void track(ZendEvent event, [Map<String, Object> props = const {}]) {
    try {
      sink(event, props);
    } catch (_) {
      // Analytics must never break a payment.
    }
  }
}
