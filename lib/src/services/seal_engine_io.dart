/// Mobile: `zend_seal.js` runs in a hidden webview that only this file talks
/// to, through the `ZendSealHost` channel. The page is an inline string with an
/// `https` base URL (a secure context, so WebCrypto works) and a CSP that
/// allows no network at all: key requests come back out to Dart.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

import 'unlock_reader.dart';

class _WebviewEngine implements SealEngine {
  _WebviewEngine(this._host);

  final SealHost _host;
  final WebViewController _web = WebViewController();
  final _ready = Completer<void>();
  final _pending = <int, Completer<String>>{};
  var _next = 1;

  Future<void> start() async {
    final js = await rootBundle.loadString('assets/seal/zend_seal.js');
    await _web.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _web.addJavaScriptChannel(
      'ZendSealHost',
      onMessageReceived: _onMessage,
    );
    await _web.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (r) =>
            r.url.startsWith('https://zend-seal.invalid/')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ),
    );
    // `</script` can't appear in the minified bundle's strings unescaped, but
    // guard anyway so the page can't be cut short.
    final safe = js.replaceAll('</script', r'<\/script');
    await _web.loadHtmlString(
      '<!doctype html><html><head><meta charset="utf-8">'
      '<meta http-equiv="Content-Security-Policy" '
      "content=\"default-src 'none'; script-src 'unsafe-inline'\">"
      '<script>$safe</script></head><body>'
      '<script>zendSeal.attach(ZendSealHost);</script></body></html>',
      baseUrl: 'https://zend-seal.invalid/',
    );
    await _ready.future.timeout(const Duration(seconds: 20));
  }

  void _onMessage(JavaScriptMessage m) {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(m.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['t']) {
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
      case 'res':
        _pending.remove(msg['id'])?.complete(msg['result'] as String);
      case 'cb':
        _answer(msg['id'] as int, msg['kind'] as String, msg['args'] as Map);
    }
  }

  Future<void> _answer(int id, String kind, Map args) async {
    bool ok;
    Object? value;
    try {
      value = switch (kind) {
        'sign' => await _host.sign(args['message'] as String),
        'fetchKey' => jsonDecode(await _host.fetchKey(jsonEncode(args))),
        _ => throw StateError('unknown callback $kind'),
      };
      ok = true;
    } catch (e) {
      ok = false;
      value = {'message': '$e'};
    }
    await _web.runJavaScript(
      'zendSealReply($id, $ok, ${jsonEncode(jsonEncode(value))})',
    );
  }

  @override
  Future<String> call(String method, String argsJson) {
    final id = _next++;
    final done = Completer<String>();
    _pending[id] = done;
    _web
        .runJavaScript(
          'zendSealCall($id, ${jsonEncode(method)}, ${jsonEncode(argsJson)})',
        )
        .catchError((Object e) {
          _pending.remove(id);
          if (!done.isCompleted) done.completeError(e);
        });
    return done.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pending.remove(id);
        return jsonEncode({
          'ok': false,
          'error': {'code': 'unavailable', 'message': 'timed out'},
        });
      },
    );
  }
}

Future<SealEngine> createSealEngine(SealHost host) async {
  final e = _WebviewEngine(host);
  await e.start();
  return e;
}
