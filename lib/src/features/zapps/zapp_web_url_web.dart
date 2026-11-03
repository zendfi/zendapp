import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Web: while a ZApp is open the address bar reads `app.usezend.app/apps/<slug>`,
/// so it's a real, shareable, refresh-safe Zend page. The browser's back button
/// closes the app. Returns a callback to run when the app closes from inside Zend.
VoidCallback enterZAppUrl(String slug, VoidCallback onBrowserBack) {
  final target = '/apps/$slug';
  final pushed = web.window.location.pathname != target;
  if (pushed) web.window.history.pushState(null, '', target);
  var active = true;
  late final JSFunction listener;
  listener = ((web.Event _) {
    if (!active) return;
    if (web.window.location.pathname != target) {
      active = false;
      web.window.removeEventListener('popstate', listener);
      onBrowserBack();
    }
  }).toJS;
  web.window.addEventListener('popstate', listener);
  return () {
    if (!active) return;
    active = false;
    web.window.removeEventListener('popstate', listener);
    if (web.window.location.pathname != target) return;
    // Opened by link straight into the app: there's no Zend page behind it.
    pushed ? web.window.history.back() : web.window.history.replaceState(null, '', '/');
  };
}
