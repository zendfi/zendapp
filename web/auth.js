// zkLogin OAuth callback for the web build (see kZkLoginWebRedirectUri in
// lib/main.dart). Two ways in:
//
//  * Popup (browser tab): hands the full callback URL (the id_token is in the
//    fragment) back to the app window using flutter_web_auth_2's protocol,
//    then closes. postMessage is pinned to our own origin so the token is
//    never delivered anywhere else.
//  * Same-window redirect (installed home-screen app): the app parked its
//    sign-in under zend-oauth-pending and sent this window to Google. Store
//    the callback beside it and go back to the app, which finishes sign-in on
//    start (lib/src/services/oauth_redirect_store.dart; keys must match).
(function () {
  var href = window.location.href;

  var redirected = false;
  if (!window.opener) {
    try {
      redirected = localStorage.getItem('zend-oauth-pending') !== null;
    } catch (e) {
      redirected = false;
    }
  }
  if (redirected) {
    localStorage.setItem('zend-oauth-callback', href);
    // replace(), so this URL (and the token in it) leaves the history.
    window.location.replace(window.location.origin + '/');
    return;
  }

  if (window.opener) {
    window.opener.postMessage({ 'flutter-web-auth-2': href }, window.location.origin);
  } else {
    // The opener can be severed by Cross-Origin-Opener-Policy during the
    // Google round-trip; flutter_web_auth_2 polls this key and deletes it on read.
    localStorage.setItem('flutter-web-auth-2', href);
  }
  // Drop the token from this tab's URL and history before closing.
  history.replaceState(null, '', window.location.pathname);
  window.close();
})();
