import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

/// Performs the post-confirmation HTTPS redirect back to a Developer's
/// `redirect_url` after a "Pay with Zend" payment is confirmed
/// (Requirement 5.3). Opens the system browser (not an in-app WebView)
/// since the redirect target is the Developer's own site, not part of the
/// Zend App experience.
class DevReturnRedirectService {
  const DevReturnRedirectService._();

  /// Appends `zend_return_token` to [redirectUrl]'s existing query
  /// parameters (preserving any that are already present) and launches it
  /// in the system browser. Returns `true` on success, `false` if the
  /// launch failed or threw.
  static Future<bool> redirect(String redirectUrl, String token) async {
    try {
      final parsed = Uri.parse(redirectUrl);
      final uri = parsed.replace(
        queryParameters: {...parsed.queryParameters, 'zend_return_token': token},
      );
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Performs the redirect and reports the outcome back to the backend for
  /// per-platform tracking (Requirement 5.10), then returns whether the
  /// redirect itself succeeded (independent of whether the outcome report
  /// succeeded — that call is best-effort and never blocks or fails this
  /// method).
  static Future<bool> redirectAndReportOutcome({
    required ApiClient apiClient,
    required String requestId,
    required String redirectUrl,
    required String token,
    required String platform,
  }) async {
    final success = await redirect(redirectUrl, token);
    await apiClient.reportReturnRedirectOutcome(
      requestId,
      platform: platform,
      success: success,
    );
    return success;
  }
}
