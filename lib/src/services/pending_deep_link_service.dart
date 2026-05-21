import '../models/qr_payment_intent.dart';

/// Stores a pending [QrPaymentIntent] when a deep link arrives while the app
/// is locked or unauthenticated. The intent is consumed after the user
/// authenticates or unlocks the app.
///
/// Uses a static nullable field — no persistence. If the app is killed before
/// the user authenticates, the pending intent is lost (acceptable: the user
/// can re-tap the link).
class PendingDeepLinkService {
  PendingDeepLinkService._();

  static QrPaymentIntent? _pending;

  /// Stores [intent] as the pending deep link intent.
  /// Overwrites any previously stored intent.
  static void store(QrPaymentIntent intent) => _pending = intent;

  /// Returns and clears the pending intent, or null if none is stored.
  static QrPaymentIntent? consume() {
    final intent = _pending;
    _pending = null;
    return intent;
  }

  /// Returns true if there is a pending intent waiting to be consumed.
  static bool get hasPending => _pending != null;
}
