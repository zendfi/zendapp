import 'dart:async';

import 'package:flutter/foundation.dart';

import 'wallet_session_cache.dart';

/// Manages automatic app locking after a period of inactivity.
///
/// Design:
/// - Single source of truth for lock state — all UI listens to [isLocked]
/// - [recordActivity] resets the inactivity timer; call it on every user touch
/// - [lock] / [unlock] are called explicitly (on background / correct PIN)
/// - The timer only runs while the user is authenticated AND [pinIsAvailable] is true
/// - [pinIsAvailable] must be set to true before lock/timer activate; this
///   prevents the lock overlay from appearing before PIN setup is complete.
class AppLockService extends ChangeNotifier {
  static const Duration _inactivityTimeout = Duration(minutes: 5);

  bool _locked = false;
  bool _active = false; // true while authenticated + foregrounded

  /// Whether the user has a PIN set up. Lock/timer only activate when true.
  /// Must be set explicitly once [WalletService.hasPinSetup] returns true.
  bool pinIsAvailable = false;

  Timer? _timer;

  /// Whether the app is currently locked and requires PIN entry.
  bool get isLocked => _locked;

  /// Stop the inactivity timer. Call when the app goes to background
  /// or the user logs out.
  void stopTimer() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Reset the inactivity countdown. Call on every user interaction.
  void recordActivity() {
    if (!_active || _locked) return;
    _resetTimer();
  }

  /// Lock the app immediately (e.g. when backgrounded for too long).
  /// No-op if [pinIsAvailable] is false — can't lock without a PIN to unlock with.
  void lock() {
    if (!pinIsAvailable) return; // no PIN set yet — don't lock
    if (_locked) return;
    _timer?.cancel();
    _timer = null;
    _locked = true;
    WalletSessionCache.instance.clear();
    notifyListeners();
  }

  /// Start the inactivity timer. Call when the user authenticates or
  /// the app returns to the foreground.
  /// No-op if [pinIsAvailable] is false.
  void startTimer() {
    if (!pinIsAvailable) return;
    _active = true;
    if (_locked) return; // already locked — don't restart timer
    _resetTimer();
  }

  /// Unlock the app after successful PIN verification.
  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
    if (_active) _resetTimer();
  }

  /// Clear all state on logout.
  void reset() {
    stopTimer();
    _locked = false;
    pinIsAvailable = false;
    // No notifyListeners — caller handles navigation
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(_inactivityTimeout, _onTimeout);
  }

  void _onTimeout() {
    if (!_active) return;
    if (kDebugMode) debugPrint('AppLock: inactivity timeout — locking app');
    lock();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
