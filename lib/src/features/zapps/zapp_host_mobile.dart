import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/appkit_service.dart';
import 'zapp_bridge.dart';

/// Lets the screen ask the host to go back inside the app before leaving it.
class ZAppHostHandle {
  Future<bool> Function()? _back;

  /// True if the app handled it (went back a page).
  Future<bool> back() async => await _back?.call() ?? false;
}

/// Native-feeling mobile host: no zoom, no link callouts, no tap flashes, and the
/// page's own background colour reported so Zend can match the status bar.
/// The SDK posts JSON to the `ZendBridge` channel; replies go to `window.__zendReceive`.
class ZAppHost extends StatefulWidget {
  const ZAppHost({
    super.key,
    required this.app,
    required this.bridge,
    required this.handle,
    required this.onReady,
    required this.onLeave,
    this.path,
  });
  final ZAppDescriptor app;
  final ZAppBridge bridge;
  final ZAppHostHandle handle;

  /// First page finished loading; carries the page background colour if known.
  final void Function(Color? background) onReady;

  /// The app tried to open something off its own origins.
  final void Function(Uri uri) onLeave;
  final String? path;

  @override
  State<ZAppHost> createState() => _ZAppHostState();
}

const _polishJs = '''
(function(){
  var m=document.querySelector('meta[name=viewport]');
  if(!m){m=document.createElement('meta');m.name='viewport';document.head.appendChild(m);}
  m.content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover';
  if(!document.getElementById('__zend_native')){
    var s=document.createElement('style');s.id='__zend_native';
    s.textContent='html,body{-webkit-tap-highlight-color:transparent;overscroll-behavior:none}'+
      '*:not(input):not(textarea):not([contenteditable]){-webkit-touch-callout:none;-webkit-user-select:none;user-select:none}';
    document.head.appendChild(s);
  }
})();''';

Color? _parseCss(Object raw) {
  final s = raw.toString().replaceAll('"', '');
  final m = RegExp(
    r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)',
  ).firstMatch(s);
  if (m == null) return null;
  final a = m.group(4) == null ? 1.0 : double.tryParse(m.group(4)!) ?? 1.0;
  if (a < 0.5) return null; // transparent body: keep Zend's background
  return Color.fromARGB(
    255,
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

class _ZAppHostState extends State<ZAppHost> {
  late final WebViewController _controller;
  bool _readySent = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri != null && widget.app.allows(uri))
              return NavigationDecision.navigate;
            if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http'))
              widget.onLeave(uri);
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) => _polish(),
        ),
      )
      ..addJavaScriptChannel('ZendBridge', onMessageReceived: _onMessage)
      ..loadRequest(widget.app.entryUri(widget.path));
    widget.handle._back = () async {
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return true;
      }
      return false;
    };
  }

  Future<void> _polish() async {
    Color? bg;
    try {
      await _controller.runJavaScript(_polishJs);
      bg = _parseCss(
        await _controller.runJavaScriptReturningResult(
          'getComputedStyle(document.body).backgroundColor',
        ),
      );
    } catch (_) {}
    if (!_readySent && mounted) {
      _readySent = true;
      widget.onReady(bg);
    }
  }

  Future<void> _onMessage(JavaScriptMessage m) async {
    // Channel messages carry no origin, so check where the page is right now.
    final current = Uri.tryParse(await _controller.currentUrl() ?? '');
    if (current == null || !widget.app.allows(current)) return;
    final reply = await widget.bridge.handleRaw(m.message);
    if (reply == null || !mounted) return;
    final now = Uri.tryParse(await _controller.currentUrl() ?? '');
    if (now == null || !widget.app.allows(now)) return;
    await _controller.runJavaScript(
      'window.__zendReceive && window.__zendReceive(${_jsString(reply)});',
    );
  }

  static String _jsString(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\n', r'\n').replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029')}'";

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
