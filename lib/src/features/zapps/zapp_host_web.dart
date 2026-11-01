import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../services/appkit_service.dart';
import 'zapp_bridge.dart';

/// Web host: a sandboxed iframe. The SDK posts JSON strings to `window.parent`;
/// only messages from this iframe's window and a registered origin are handled.
/// The sandbox omits `allow-top-navigation`, so the app can't navigate Zend away.
class ZAppHost extends StatefulWidget {
  const ZAppHost({
    super.key,
    required this.app,
    required this.bridge,
    this.path,
  });
  final ZAppDescriptor app;
  final ZAppBridge bridge;
  final String? path;

  @override
  State<ZAppHost> createState() => _ZAppHostState();
}

class _ZAppHostState extends State<ZAppHost> {
  static int _seq = 0;
  late final String _viewType = 'zapp-iframe-${_seq++}';
  late final web.HTMLIFrameElement _frame;
  JSFunction? _listener;

  @override
  void initState() {
    super.initState();
    _frame = web.HTMLIFrameElement()
      ..src = widget.app.entryUri(widget.path).toString()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'clipboard-write';
    _frame.setAttribute(
      'sandbox',
      'allow-scripts allow-same-origin allow-forms allow-popups',
    );
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _frame,
    );
    _listener = ((web.MessageEvent e) => _onMessage(e)).toJS;
    web.window.addEventListener('message', _listener);
  }

  Future<void> _onMessage(web.MessageEvent e) async {
    final origin = Uri.tryParse(e.origin);
    if (origin == null || !widget.app.allows(origin)) return;
    final child = _frame.contentWindow;
    if (child == null || e.source != child) return;
    final data = e.data;
    if (!data.isA<JSString>()) return;
    final reply = await widget.bridge.handleRaw((data as JSString).toDart);
    if (reply == null || !mounted) return;
    _frame.contentWindow?.postMessage(reply.toJS, e.origin.toJS);
  }

  @override
  void dispose() {
    if (_listener != null) web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
