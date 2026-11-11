/// Web: `zend_seal.js` runs in the Zend page itself (same origin, `script-src
/// 'self'`), injected on first use so other visits don't download it. ZApps run
/// in cross-origin iframes and can't reach `window.zendSeal`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'unlock_reader.dart';

@JS('zendSeal')
external _ZendSeal? get _zendSeal;

extension type _ZendSeal._(JSObject _) implements JSObject {
  external void setJsonHost(JSObject host);
  external JSPromise<JSString> call(String method, String argsJson);
}

Future<void>? _loading;

Future<void> _load() {
  if (_zendSeal != null) return Future.value();
  return _loading ??= () {
    final done = Completer<void>();
    final s = web.HTMLScriptElement()
      ..src = 'zend_seal.js'
      ..async = true;
    s.onload = ((web.Event _) => done.complete()).toJS;
    s.onerror = ((web.Event _) {
      _loading = null;
      if (!done.isCompleted) {
        done.completeError(
          const UnlockException('unavailable', "That didn't open. Try again."),
        );
      }
    }).toJS;
    web.document.head!.append(s);
    return done.future;
  }();
}

class _WebEngine implements SealEngine {
  _WebEngine(this._s);
  final _ZendSeal _s;

  @override
  Future<String> call(String method, String argsJson) async =>
      (await _s.call(method, argsJson).toDart).toDart;
}

Future<SealEngine> createSealEngine(SealHost host) async {
  await _load();
  final s = _zendSeal!;
  final h = JSObject();
  h['sign'] =
      ((JSString m) => host.sign(m.toDart).then((v) => v.toJS).toJS).toJS;
  h['fetchKey'] =
      ((JSString a) => host.fetchKey(a.toDart).then((v) => v.toJS).toJS).toJS;
  s.setJsonHost(h);
  return _WebEngine(s);
}
