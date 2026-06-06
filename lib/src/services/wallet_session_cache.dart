import 'package:flutter/foundation.dart';
/// In-memory keypair cache for the duration of an authenticated session.
///
/// The keypair is NEVER persisted to disk, [SharedPreferences], or any platform
/// storage mechanism. It is zeroed and cleared when:
/// - [AppLockService.lock] fires (inactivity timeout or explicit lock)
/// - The app is force-closed (Dart heap GC)
///
/// Design: singleton [ChangeNotifier] so any widget or service can listen
/// for lock/unlock events by observing [hasKeypair].
class WalletSessionCache extends ChangeNotifier {
  WalletSessionCache._();

  /// The single shared instance. Do not create additional instances.
  static final instance = WalletSessionCache._();

  Uint8List? _keypair;

  /// Whether a decrypted keypair is currently held in memory.
  bool get hasKeypair => _keypair != null;

  /// Stores an independent copy of the decrypted 64-byte keypair in memory.
  /// The caller may zero their own copy after calling this.
  void store(Uint8List keypair) {
    _keypair = Uint8List.fromList(keypair);
    notifyListeners();
  }

  /// Returns an independent copy of the cached keypair, or null if locked.
  /// Callers are responsible for zeroing the returned bytes after use.
  Uint8List? get keypair =>
      _keypair != null ? Uint8List.fromList(_keypair!) : null;

  /// Zeros all keypair bytes in memory and clears the cached value.
  /// Safe to call multiple times.
  void clear() {
    if (_keypair != null) {
      for (var i = 0; i < _keypair!.length; i++) {
        _keypair![i] = 0;
      }
      _keypair = null;
    }
    notifyListeners();
  }
}
