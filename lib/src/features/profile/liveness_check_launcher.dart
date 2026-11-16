import 'dart:convert';

import 'package:flutter/material.dart';

import 'human_verification_screen.dart';
import 'liveness_page_stub.dart'
    if (dart.library.js_interop) 'liveness_page_web.dart';

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
        builder: (_) => LivenessPage(url: '$_livenessUrl#$payload'),
      ),
    );
    return done == true ? <String, dynamic>{} : null;
  }
}

