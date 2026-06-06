import 'signing_policy_service.dart';
import 'wallet_service.dart';
import 'wallet_session_cache.dart';

/// Legacy compatibility shim — delegates to [SigningPolicyService].
///
/// New code should use [SigningPolicyService] directly.
/// This class is kept so that existing call sites don't break while
/// the migration to [SigningPolicyService] is in progress.
class PinPerPaymentService {
  final _policy = SigningPolicyService();

  /// Returns true if PIN-per-payment is currently enabled.
  Future<bool> isEnabled() => _policy.pinPerPaymentEnabled;

  /// Enables or disables the PIN-per-payment requirement.
  Future<void> setEnabled(bool enabled) => _policy.setPinPerPayment(enabled);

  /// Verifies [pin] against the cached keypair without a server round-trip.
  ///
  /// Re-decrypts the local keypair using [pin] and compares the result byte-
  /// for-byte to [WalletSessionCache.instance.keypair].
  ///
  /// Returns true if the PIN is correct, false otherwise.
  Future<bool> verifyPin(String pin, WalletService wallet) async {
    try {
      final decrypted = await wallet.decryptLocalKeypair(pin);
      try {
        final cached = WalletSessionCache.instance.keypair;
        if (cached == null || decrypted.length != cached.length) return false;
        var match = true;
        for (var i = 0; i < decrypted.length; i++) {
          if (decrypted[i] != cached[i]) {
            match = false;
            break;
          }
        }
        return match;
      } finally {
        for (var i = 0; i < decrypted.length; i++) {
          decrypted[i] = 0;
        }
      }
    } catch (_) {
      return false;
    }
  }
}
