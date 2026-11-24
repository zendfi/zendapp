import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'oauth_redirect_store.dart';

// Keys shared with web/auth.js. Change them together.
const _pendingKey = 'zend-oauth-pending';
const _callbackKey = 'zend-oauth-callback';

class OAuthRedirectStore {
  const OAuthRedirectStore._();

  /// True when running from the home screen rather than a browser tab.
  ///
  /// `display-mode: standalone` covers Android and current iOS; the
  /// non-standard `navigator.standalone` covers older iOS.
  static bool get isInstalledWebApp {
    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    final legacy = (web.window.navigator as JSObject).getProperty<JSAny?>(
      'standalone'.toJS,
    );
    return legacy.isA<JSBoolean>() && (legacy as JSBoolean).toDart;
  }

  /// True when auth.html has handed back a Google callback for us.
  static bool get hasReturn => _get(_callbackKey) != null;

  static void park(String pending) {
    web.window.localStorage.removeItem(_callbackKey);
    web.window.localStorage.setItem(_pendingKey, pending);
  }

  /// Leaves the app for [url]. Same window, so no user activation is needed.
  static void navigate(String url) => web.window.location.assign(url);

  /// Reads and deletes the parked sign-in and its callback, in one step.
  /// Null unless both are present; either way nothing is left behind.
  static OAuthRedirectReturn? take() {
    final pending = _get(_pendingKey);
    final callback = _get(_callbackKey);
    discard();
    if (pending == null || callback == null) return null;
    return OAuthRedirectReturn(pending: pending, callback: callback);
  }

  static void discard() {
    try {
      web.window.localStorage.removeItem(_pendingKey);
      web.window.localStorage.removeItem(_callbackKey);
    } catch (_) {
      // Storage disabled: nothing could have been parked either.
    }
  }

  static String? _get(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }
}
