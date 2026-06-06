import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

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
}
