// Mobile builds: sign-in uses the system browser and an App Link, never a
// full-page redirect, so there is nothing to park.
import 'oauth_redirect_store.dart';

class OAuthRedirectStore {
  const OAuthRedirectStore._();

  static bool get isInstalledWebApp => false;
  static bool get hasReturn => false;
  static void park(String pending) =>
      throw UnsupportedError('Redirect sign-in is web only');
  static void navigate(String url) =>
      throw UnsupportedError('Redirect sign-in is web only');
  static OAuthRedirectReturn? take() => null;
  static void discard() {}
}
