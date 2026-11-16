import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class LivenessPage extends StatefulWidget {
  const LivenessPage({super.key, required this.url});
  final String url;

  @override
  State<LivenessPage> createState() => LivenessPageState();
}

class LivenessPageState extends State<LivenessPage> {
  late final WebViewController _c;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() => _error = 'That didn\'t go through. Try again.');
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'ZendLiveness',
        onMessageReceived: (m) {
          if (!mounted) return;
          if (m.message == 'done') {
            Navigator.of(context).pop(true);
          } else if (m.message == 'cancel') {
            Navigator.of(context).pop(false);
          } else {
            setState(() => _error = 'That didn\'t go through. Try again.');
          }
        },
      );
    final platform = _c.platform;
    if (platform is AndroidWebViewController) {
      // The page asks for the camera; only this page can be loaded here, so grant it.
      platform.setOnPlatformPermissionRequest((req) => req.grant());
    }
    _c.loadRequest(Uri.parse(widget.url));
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
                WebViewWidget(controller: _c),
                if (_loading) const Center(child: ZendLoader(size: 22)),
              ],
            ),
    );
  }
}
