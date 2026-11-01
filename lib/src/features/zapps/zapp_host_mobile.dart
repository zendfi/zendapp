import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/appkit_service.dart';
import 'zapp_bridge.dart';

/// Mobile host. The SDK finds the `ZendBridge` channel and posts JSON to it;
/// replies arrive through `window.__zendReceive(json)`.
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
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri != null && widget.app.allows(uri)) {
              return NavigationDecision.navigate;
            }
            // Anything off the app's own origins opens outside, never inside the sheet.
            if (uri != null &&
                (uri.scheme == 'https' || uri.scheme == 'http')) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel('ZendBridge', onMessageReceived: _onMessage)
      ..loadRequest(widget.app.entryUri(widget.path));
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
