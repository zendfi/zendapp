import 'dart:async';

import 'package:flutter/foundation.dart';

/// Manages automatic app locking after a period of inactivity.
///
/// Design:
/// - Single source of truth for lock state — all UI listens to [isLocked]
/// - [recordActivity] resets the inactivity timer; call it on every user touch
/// - [lock] / [unlock] are called explicitly (on background / correct PIN)
/// - The timer only runs while the user is authenticated and the app is active
class AppLockService extends ChangeNotifier {
  static const Duration _inactivityTimeout = Duration(minutes: 5);

  bool _locked = false;
  bool _active = false; // true while authenticated + foregrounded
  Timer? _timer;

  /// Whether the app is currently locked and requires PIN entry.
  bool get isLocked => _locked;

  /// Start the inactivity timer. Call when the user authenticates or
  /// the app returns to the foreground.
  void startTimer() {
    _active = true;
    if (_locked) return; // already locked — don't restart timer
    _resetTimer();
  }

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
  void lock() {
    if (_locked) return;
    _timer?.cancel();
    _timer = null;
    _locked = true;
    notifyListeners();
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
