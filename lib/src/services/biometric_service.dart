import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages biometric unlock for the Zend! wallet.
///
/// The user's PIN is stored in the iOS Keychain / Android Keystore under a
/// passcode-gated access policy ([KeychainAccessibility.passcode]).
/// When biometric auth succeeds, the PIN is retrieved and used to decrypt
/// the wallet keypair — the PIN is never displayed on screen.
///
/// [KeychainAccessibility.passcode]:
///   - Requires device passcode to be set (which is always the case for
///     biometric-capable devices).
///   - Items do NOT migrate to new devices, matching the intended UX that
///     biometric re-enrolment is required on a new device.
///   - Available in flutter_secure_storage 9.x.
///
/// Mobile only — zendonline and simulators without enrolled biometrics should
/// call [isAvailable] and hide the biometric option if it returns false.
class BiometricService {
  static const _pinKey = 'zend_biometric_pin';

  // iOS keychain options — passcode-gated, non-migrating.
  static const _iOptions = IOSOptions(
    accessibility: KeychainAccessibility.passcode,
  );

  final LocalAuthentication _auth = LocalAuthentication();

  /// Returns true if the device supports and has enrolled biometrics.
  Future<bool> isAvailable() async {
    final canCheck = await _auth.canCheckBiometrics;
    final isDeviceSupported = await _auth.isDeviceSupported();
    return canCheck && isDeviceSupported;
  }

  /// Returns the list of enrolled biometric types on this device.
  Future<List<BiometricType>> availableBiometrics() =>
      _auth.getAvailableBiometrics();

  /// Enables biometric unlock by storing [pin] in the Secure Enclave,
  /// gated by passcode (which is a prerequisite for biometric enrolment).
  Future<void> enable(String pin) async {
    const storage = FlutterSecureStorage(iOptions: _iOptions);
    await storage.write(key: _pinKey, value: pin);
  }

  /// Presents the platform biometric prompt. On success, retrieves and returns
  /// the stored PIN. Returns null if authentication fails or the PIN is not stored.
  Future<String?> authenticateAndGetPin() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Unlock your Zend! wallet',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!authenticated) return null;
    } catch (_) {
      return null;
    }

    const storage = FlutterSecureStorage(iOptions: _iOptions);
    return storage.read(key: _pinKey);
  }

  /// Deletes the stored PIN from the Secure Enclave, disabling biometric unlock.
  Future<void> disable() async {
    const storage = FlutterSecureStorage(iOptions: _iOptions);
    await storage.delete(key: _pinKey);
  }

  /// Returns true if a PIN is currently stored for biometric unlock.
  Future<bool> isEnabled() async {
    const storage = FlutterSecureStorage(iOptions: _iOptions);
    final value = await storage.read(key: _pinKey);
    return value != null && value.isNotEmpty;
  }

  // ── App lock for accounts with no PIN ────────────────────────────────────
  //
  // A zkLogin account has no local private key and therefore no PIN, so the
  // methods above have nothing to store or retrieve. Its app lock is a pure
  // presence check instead: the OS confirms the person holding the device.
  //
  // Worth being clear about what this does and does not protect. It keeps a
  // passer-by out of balances, activity and chats. It is not custody protection:
  // anyone who can reach the device's Google session could sign in again from
  // scratch. Protection for large transfers comes from re-authenticating with
  // Google server-side, not from this toggle.

  static const _appLockKey = 'zend_app_lock_biometric';

  /// Whether the user has switched on biometric app lock.
  Future<bool> isAppLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_appLockKey) ?? false;
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appLockKey, enabled);
  }

  /// Presents the platform prompt and reports only whether it succeeded.
  ///
  /// Unlike [authenticateAndGetPin] this retrieves nothing, because there is no
  /// PIN to retrieve. `biometricOnly` is deliberately false so the OS offers the
  /// device passcode as a fallback — otherwise a failed fingerprint sensor or a
  /// re-enrolled face would lock the user out of their own account with no way
  /// back in, and the account holds money.
  Future<bool> authenticateOnly({
    String reason = 'Unlock Zend!',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
