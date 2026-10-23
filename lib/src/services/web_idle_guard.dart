import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../core/zend_state.dart';

/// Signs the web app out after a stretch with no input.
///
/// Mobile has the app lock for an unattended phone; a browser tab has nothing
/// equivalent, and on a shared computer an open tab is an open wallet. The
/// banking-site convention is a short idle timeout, so after [timeout] with no
/// pointer or key input the session is cleared (sessionStorage included) and
/// the user lands back on the welcome screen.
///
/// No-op off web.
class WebIdleGuard {
  WebIdleGuard(this._model, {this.timeout = const Duration(minutes: 15)});

  final ZendAppModel _model;
  final Duration timeout;
  Timer? _timer;

  void start() {
    if (!kIsWeb) return;
    HardwareKeyboard.instance.addHandler(_onKey);
    recordActivity();
  }

  void dispose() {
    if (!kIsWeb) return;
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
  }

  /// Call on any user input. Cheap: just restarts one timer.
  void recordActivity() {
    if (!kIsWeb) return;
    _timer?.cancel();
    _timer = Timer(timeout, _expire);
  }

  bool _onKey(KeyEvent _) {
    recordActivity();
    return false; // observe only, never consume
  }

  Future<void> _expire() async {
    if (!_model.isAuthenticated) return;
    await _model.authService.logout();
    _model.handleUnauthorized();
  }
}
