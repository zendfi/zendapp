import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'wallet_service.dart';
import 'wallet_session_cache.dart';

/// Manages the signing policy for payment transactions.
///
/// There are three modes that work in layered priority:
///
///   1. Session signing (default, enabled): after app unlock, all sends use
///      [WalletSessionCache.keypair] directly — no PIN dialog shown.
///
///   2. Pin-per-payment (user opt-in): disables session signing; every send
///      requires PIN entry regardless of amount.
///
///   3. Amount threshold (user opt-in, works on top of session signing):
///      even in session mode, sends at or above [pinThresholdAmount] require
///      PIN entry. Below the threshold, session signing is used.
///
/// Decision tree in [requiresPinForAmount]:
///   - If session cache is empty → PIN always required (caller must handle)
///   - If [pinPerPaymentEnabled] → PIN required
///   - If [pinThresholdEnabled] && amount >= [pinThresholdAmount] → PIN required
///   - Otherwise → session signing (no PIN)
class SigningPolicyService {
  static const _pinPerPaymentKey = 'zend_pin_per_payment';
  static const _pinThresholdEnabledKey = 'zend_pin_threshold_enabled';
  static const _pinThresholdAmountKey = 'zend_pin_threshold_amount';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // ── Pin-per-payment ────────────────────────────────────────────────────────

  /// Returns true if the user has enabled PIN on every payment.
  Future<bool> get pinPerPaymentEnabled async {
    final v = await _storage.read(key: _pinPerPaymentKey);
    return v == 'true';
  }

  /// Enables or disables PIN on every payment.
  Future<void> setPinPerPayment(bool enabled) async {
    await _storage.write(
      key: _pinPerPaymentKey,
      value: enabled ? 'true' : 'false',
    );
  }

  // ── Amount threshold ───────────────────────────────────────────────────────

  /// Returns true if the user has enabled PIN above a threshold amount.
  Future<bool> get pinThresholdEnabled async {
    final v = await _storage.read(key: _pinThresholdEnabledKey);
    return v == 'true';
  }

  /// Returns the configured threshold amount in USDC, or null if not set.
  Future<double?> get pinThresholdAmount async {
    final v = await _storage.read(key: _pinThresholdAmountKey);
    if (v == null) return null;
    return double.tryParse(v);
  }

  /// Enables the amount threshold with the given [amount] in USDC.
  Future<void> setPinThreshold({required double amount}) async {
    await _storage.write(key: _pinThresholdEnabledKey, value: 'true');
    await _storage.write(
        key: _pinThresholdAmountKey, value: amount.toString());
  }

  /// Disables the amount threshold.
  Future<void> disablePinThreshold() async {
    await _storage.write(key: _pinThresholdEnabledKey, value: 'false');
  }

  // ── Core decision ──────────────────────────────────────────────────────────

  /// Returns true if a PIN prompt is required for [amount] USDC.
  ///
  /// Does NOT check whether the session cache is populated — the caller must
  /// additionally verify [WalletSessionCache.instance.hasKeypair] and fall
  /// back to PIN if the cache is empty.
  Future<bool> requiresPinForAmount(double amount) async {
    // 1. Pin-per-payment overrides everything
    if (await pinPerPaymentEnabled) return true;

    // 2. Amount threshold
    if (await pinThresholdEnabled) {
      final threshold = await pinThresholdAmount;
      if (threshold != null && amount >= threshold) return true;
    }

    // 3. Session signing — no PIN needed
    return false;
  }

  // ── Snapshot ───────────────────────────────────────────────────────────────

  /// Reads all settings in a single pass for use in Settings UI.
  Future<SigningPolicySnapshot> snapshot() async {
    final values = await Future.wait([
      _storage.read(key: _pinPerPaymentKey),
      _storage.read(key: _pinThresholdEnabledKey),
      _storage.read(key: _pinThresholdAmountKey),
    ]);
    return SigningPolicySnapshot(
      pinPerPaymentEnabled: values[0] == 'true',
      pinThresholdEnabled: values[1] == 'true',
      pinThresholdAmount: values[2] != null ? double.tryParse(values[2]!) : null,
    );
  }

  // ── PIN verification ───────────────────────────────────────────────────────

  /// Verifies [pin] against [WalletSessionCache] without a server round-trip.
  ///
  /// Re-decrypts the local keypair using [pin] and compares byte-for-byte
  /// to the cached session keypair. Returns true if the PIN is correct.
  Future<bool> verifyPinAgainstCache(String pin, WalletService wallet) async {
    try {
      final decrypted = await wallet.decryptLocalKeypair(pin);
      try {
        final cached = WalletSessionCache.instance.keypair;
        if (cached == null || decrypted.length != cached.length) return false;
        var match = true;
        for (var i = 0; i < decrypted.length; i++) {
          if (decrypted[i] != cached[i]) { match = false; break; }
        }
        return match;
      } finally {
        for (var i = 0; i < decrypted.length; i++) { decrypted[i] = 0; }
      }
    } catch (_) {
      return false;
    }
  }
}

/// Immutable snapshot of the current signing policy for use in the UI.
class SigningPolicySnapshot {
  const SigningPolicySnapshot({
    required this.pinPerPaymentEnabled,
    required this.pinThresholdEnabled,
    required this.pinThresholdAmount,
  });

  final bool pinPerPaymentEnabled;
  final bool pinThresholdEnabled;
  final double? pinThresholdAmount;
}
