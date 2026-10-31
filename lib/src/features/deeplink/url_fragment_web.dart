import 'package:web/web.dart' as web;

/// Removes `#<link key>` from the address bar and history as soon as it has
/// been read, so the key isn't left in browser history or screenshots.
void stripUrlFragment() {
  final loc = web.window.location;
  if (loc.hash.isEmpty) return;
  web.window.history.replaceState(null, '', '${loc.pathname}${loc.search}');
}
