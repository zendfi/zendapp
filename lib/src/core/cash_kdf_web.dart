/// Web: Argon2id through WebAssembly (`web/zend_argon2.js`), injected on first
/// use. Pure-Dart Argon2 compiled to JS takes far too long at 64 MiB, and the
/// parameters must not be lowered for the web. Same origin, so `script-src
/// 'self'` and the existing `'wasm-unsafe-eval'` cover it.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

@JS('zendArgon2')
external _ZendArgon2? get _zendArgon2;

extension type _ZendArgon2._(JSObject _) implements JSObject {
  external JSPromise<JSUint8Array> derive(JSUint8Array password, JSUint8Array salt);
}

Future<void>? _loading;

Future<void> _load() {
  if (_zendArgon2 != null) return Future.value();
  return _loading ??= () {
    final done = Completer<void>();
    final s = web.HTMLScriptElement()
      ..src = 'zend_argon2.js'
      ..async = true;
    s.onload = ((web.Event _) => done.complete()).toJS;
    s.onerror = ((web.Event _) {
      _loading = null;
      if (!done.isCompleted) {
        done.completeError(StateError('zend_argon2.js failed to load'));
      }
    }).toJS;
    web.document.head!.append(s);
    return done.future;
  }();
}

Future<Uint8List> deriveCashSeed(Uint8List password, Uint8List salt) async {
  await _load();
  final out = await _zendArgon2!.derive(password.toJS, salt.toJS).toDart;
  return out.toDart;
}
