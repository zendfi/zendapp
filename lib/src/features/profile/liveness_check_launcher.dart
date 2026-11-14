import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'human_verification_screen.dart';

/// Where the hosted check page lives (the `liveness-page/` project, built and served over https).
const _livenessUrl = String.fromEnvironment('HUMAN_LIVENESS_URL');

/// Runs the face check in a web view that loads the hosted page. The page gets the session details
/// in the URL fragment (never sent to a server or logged) and reports back through a JS channel.
/// The result is an empty map: the server reads the verdict itself when the app calls complete.
class LivenessCheckLauncher implements HumanCheckLauncher {
  LivenessCheckLauncher(this.navigator);
  final NavigatorState navigator;

  @override
  bool get isAvailable => _livenessUrl.isNotEmpty;

  @override
  Future<Map<String, dynamic>?> scan({
    required Map<String, dynamic> challenge,
  }) async {
    if (challenge['provider'] != 'aws') return null;
    final payload = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'session_id': challenge['session_id'],
          'region': challenge['region'],
          'credentials': challenge['credentials'],
        }),
      ),
    );
    final done = await navigator.push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LivenessPage(url: '$_livenessUrl#$payload'),
      ),
    );
    return done == true ? <String, dynamic>{} : null;
  }
}

class _LivenessPage extends StatefulWidget {
  const _LivenessPage({required this.url});
  final String url;

  @override
  State<_LivenessPage> createState() => _LivenessPageState();
}

class _LivenessPageState extends State<_LivenessPage> {
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
