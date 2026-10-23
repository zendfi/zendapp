// zkLogin OAuth callback for the web build (see kZkLoginWebRedirectUri in
// lib/main.dart). Hands the full callback URL (the id_token is in the
// fragment) back to the app window using flutter_web_auth_2's protocol, then
// closes the popup. postMessage is pinned to our own origin so the token is
// never delivered anywhere else.
(function () {
  var href = window.location.href;
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
