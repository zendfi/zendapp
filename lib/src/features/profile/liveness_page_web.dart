import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

/// Web: the hosted check page in an iframe allowed to use the camera. The page reports back with
/// postMessage; only messages from this iframe's window and the page's own origin count.
class LivenessPage extends StatefulWidget {
  const LivenessPage({super.key, required this.url});

  final String url;

  @override
  State<LivenessPage> createState() => _LivenessPageState();
}

class _LivenessPageState extends State<LivenessPage> {
  static int _seq = 0;
  late final String _viewType = 'liveness-iframe-${_seq++}';
  late final web.HTMLIFrameElement _frame;
  JSFunction? _listener;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _frame = web.HTMLIFrameElement()
      ..src = widget.url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'camera';
    _frame.addEventListener(
      'load',
      ((web.Event _) {
        if (mounted) setState(() => _loading = false);
      }).toJS,
    );
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _frame);
    final origin = Uri.parse(widget.url).origin;
    _listener = ((web.MessageEvent e) {
      if (e.origin != origin) return;
      final source = e.source;
      final child = _frame.contentWindow;
      if (child == null || source == null || !source.strictEquals(child).toDart) {
        return;
      }
      final data = e.data;
      if (!data.isA<JSString>() || !mounted) return;
      final msg = (data as JSString).toDart;
      if (msg == 'done') {
        Navigator.of(context).pop(true);
      } else if (msg == 'cancel') {
        Navigator.of(context).pop(false);
      } else if (msg == 'error') {
        setState(() => _error = 'That didn\'t go through. Try again.');
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  @override
  void dispose() {
    if (_listener != null) web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      appBar: AppBar(
        backgroundColor: zt.bgPrimary,
        elevation: 0,
        iconTheme: IconThemeData(color: zt.textPrimary),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: TextStyle(color: zt.destructive)))
          : Stack(
              children: [
                HtmlElementView(viewType: _viewType),
                if (_loading) const Center(child: ZendLoader(size: 22)),
              ],
            ),
    );
  }
}
