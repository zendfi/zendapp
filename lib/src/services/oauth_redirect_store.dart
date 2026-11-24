/// Carries a Google sign-in across a full-page trip to Google and back.
///
/// The installed web app (home-screen PWA) cannot use the popup that
/// `flutter_web_auth_2` opens. On iPhone a popup from a home-screen app opens
/// in a separate Safari sheet with its own storage and no `window.opener`, so
/// `auth.html` hands the token to a place the app never reads, and the app
/// waits five minutes for nothing. The installed app navigates its own window
/// to Google instead. That unloads the app, so the pending sign-in (ephemeral
/// key, randomness, session, state) is parked here and read back on return.
///
/// Storage is `localStorage`, not `sessionStorage`: iOS can show the return
/// from an out-of-scope page as a fresh load of the app, and sessionStorage is
/// tied to one browsing context. To keep the key's time on disk short:
///   * [take] deletes both entries in the same call that reads them.
///   * [discard] runs on every launch that is not a return from Google, so an
///     abandoned trip (cancelled at Google, app closed) is cleared next start.
///   * the session inside expires within the day, and is checked on resume.
///
/// The key in here is the same one already held in page memory during a
/// popup sign-in, so this adds disk residency, not a new kind of exposure.
library;

export 'oauth_redirect_store_stub.dart'
    if (dart.library.js_interop) 'oauth_redirect_store_web.dart';

/// What came back from Google, paired with what was parked before leaving.
class OAuthRedirectReturn {
  const OAuthRedirectReturn({required this.pending, required this.callback});

  /// JSON written by `SuiZkLoginService.redirectPublicSignIn`.
  final String pending;

  /// The full `auth.html` URL Google redirected to (token in the fragment).
  final String callback;
}
