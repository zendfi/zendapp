import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Web: true only where the browser has a share sheet. Without one,
/// share_plus falls back to opening a `mailto:` link, which is never what a
/// ZApp's "Invite" button means, so Zend copies the link instead.
bool deviceCanShare() =>
    (web.window.navigator as JSObject).has('share') &&
    (web.window.navigator as JSObject).has('canShare');
