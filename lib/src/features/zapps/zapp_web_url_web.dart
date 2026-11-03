import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Web: while a ZApp is open the address bar reads `app.usezend.app/apps/<slug>`,
/// so it's a real, shareable, refresh-safe Zend page. Returns a callback that
/// puts the previous address back when the app closes.
///
/// This rewrites the current history entry instead of pushing a new one.
/// Flutter web keeps exactly one history entry of its own and treats any entry
/// pushed on top of it as a URL the user typed: going back onto its entry made
/// it replay the initial route, which rebuilt the app from the splash screen
/// and landed on Feed. With no extra entry, the browser's back button reaches
/// Flutter as an ordinary back press, which the ZApp screen handles by closing.
VoidCallback enterZAppUrl(String slug) {
  final target = '/apps/$slug';
  final loc = web.window.location;
  // Opened straight from a link: there's no Zend page behind it, so go home.
  final previous = loc.pathname == target
      ? '/${loc.hash}'
      : '${loc.pathname}${loc.search}${loc.hash}';
  if (loc.pathname != target) {
    web.window.history.replaceState(web.window.history.state, '', target);
  }
  var active = true;
  return () {
    if (!active) return;
    active = false;
    // Something else already changed the address; leave it alone.
    if (web.window.location.pathname != target) return;
    web.window.history.replaceState(web.window.history.state, '', previous);
  };
}
