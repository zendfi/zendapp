import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/sha256.dart';

import 'sui_zklogin_service.dart' show SuiOAuthProvider, SuiOAuthTokens;

/// Which OAuth response type to use.
///
/// The choice is dictated by the Google client type, not by preference:
///   * A "Web application" client cannot use a custom-scheme redirect, and its
///     token endpoint requires a client secret — which must never ship in an
///     app. So a web client must use [implicitIdToken], where the ID token comes
///     straight back in the redirect fragment and no token call happens.
///   * An "Android"/"iOS" client is a public client: no secret, and the token
///     endpoint accepts PKCE. So it uses [authorizationCodePkce].
///
/// zkLogin only ever needs an ID token, never an access or refresh token, which
/// is what makes the secret-free implicit path viable at all.
enum SuiOAuthFlow { implicitIdToken, authorizationCodePkce }

/// How insistently to involve the user in an OAuth round-trip.
///
/// Three distinct jobs, three different answers:
///
///   * [selectAccount] — first sign-in. The chooser is shown deliberately: `sub`
///     determines the Sui address, so silently reusing whichever Google account
///     happens to be active could put the user on a different address than they
///     expect.
///   * [none] — renewing an expired signing session for an account already
///     signed in. Google answers without any UI when its own session is alive,
///     which is what keeps the daily zkLogin session expiry invisible. Fails with
///     `login_required` when interaction would be needed.
///   * [reauthenticate] — step-up for a high-value action. `max_age=0` forces
///     Google itself to re-verify the person, which device possession alone
///     cannot satisfy.
enum SuiOAuthPrompt {
  selectAccount,
  none,
  reauthenticate;

  Map<String, String> get parameters => switch (this) {
    SuiOAuthPrompt.selectAccount => const {'prompt': 'select_account'},
    SuiOAuthPrompt.none => const {'prompt': 'none'},
    // `prompt=login` and `max_age=0` together: the first asks for
    // re-authentication, the second makes any cached authentication too old to
    // reuse, so the backend can verify freshness from `auth_time`.
    SuiOAuthPrompt.reauthenticate => const {
      'prompt': 'login',
      'max_age': '0',
    },
  };
}

/// Obtains a nonce-bearing Google ID token for zkLogin.
///
/// ## Why not `google_sign_in`
///
/// zkLogin requires the `nonce` claim inside the ID token, because that nonce is
/// what cryptographically binds the token to one ephemeral key and one epoch
/// window. `google_sign_in` exposes no way to set it (flutter#85439), so it
/// cannot be used here regardless of version. It remains in the project for
/// Drive backup, which needs an access token rather than a bound ID token.
///
/// ## Address stability warning
///
/// A zkLogin Sui address derives from `iss`, `aud`, `sub`, and the user salt.
/// `aud` **is the OAuth client id**. The same Google user authenticating through
/// two different client ids therefore controls two different Sui addresses, and
/// funds in one are not visible from the other. Every platform that must share
/// an address has to send the same [clientId].
class GoogleZkLoginOAuthProvider implements SuiOAuthProvider {
  GoogleZkLoginOAuthProvider({
    required this.clientId,
    required this.redirectUri,
    required this.callbackUrlScheme,
    required this.flow,
    this.httpsHost,
    this.httpsPath,
    this.implicitResponseType = 'id_token token',
    this.requestDriveScope = false,
    http.Client? httpClient,
    Random? random,
  }) : _http = httpClient ?? http.Client(),
       _random = random ?? Random.secure() {
    if (callbackUrlScheme == 'https' && (httpsHost == null || httpsPath == null)) {
      // flutter_web_auth_2 5.x requires both on Android when the callback is an
      // App Link; failing here beats failing inside the platform channel.
      throw ArgumentError(
        'httpsHost and httpsPath are required when callbackUrlScheme is "https"',
      );
    }
  }

  static const _authorizationEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';

  /// Hidden per-app Drive folder. Non-sensitive per Google's Drive scope
  /// classification, and the only Drive access this app ever requests.
  static const _driveAppdataScope =
      'https://www.googleapis.com/auth/drive.appdata';

  /// The OAuth client id. Also the `aud` claim, so it participates in address
  /// derivation — see the class-level warning before changing it.
  final String clientId;
  final String redirectUri;
  final String callbackUrlScheme;
  final SuiOAuthFlow flow;
  final String? httpsHost;
  final String? httpsPath;

  /// Response type for [SuiOAuthFlow.implicitIdToken].
  ///
  /// `id_token token` rather than bare `id_token`: the access token is required to
  /// reach Drive `appdata`, where share B of the sharded salt lives. Google's
  /// written guide documents this exact pairing for the implicit flow, and taking
  /// both from one grant is what guarantees the Drive account and the zkLogin
  /// account are the same person.
  ///
  /// Still configurable so a provider-side rejection can be worked around without
  /// a code change, but dropping back to bare `id_token` disables Drive access and
  /// therefore share B.
  ///
  /// Prefer toggling [requestDriveScope], which keeps the response type and the
  /// scope list consistent with each other.
  final String implicitResponseType;

  /// Whether to bundle `drive.appdata` into the *sign-in* grant.
  ///
  /// Defaults to `false`, which is the important part. Bundling Drive into
  /// sign-in couples the core authentication path to a recovery feature: any
  /// Drive-side misconfiguration — the Drive API not enabled on the Cloud
  /// project, the scope not declared under Data Access, the consent screen still
  /// restricted — fails the *entire sign-in* with a Google 403, so nobody can log
  /// in at all. That is not a hypothetical; it is exactly how this broke.
  ///
  /// With the default, Drive access is requested separately and in context by
  /// [authorizeDriveAppdata], so a Drive problem degrades salt recovery instead
  /// of authentication.
  ///
  /// Set to `true` only to deliberately reinstate the single-grant behaviour.
  /// When `false`, the access token is dropped from sign-in too, since its only
  /// purpose is reaching Drive.
  final bool requestDriveScope;

  /// Scopes for the sign-in grant.
  ///
  /// `openid` yields the ID token; `email` and `profile` populate the placeholder
  /// handle and display name the backend assigns on first sign-in. Google expands
  /// the latter two to their `userinfo.*` forms in the request it records.
  ///
  /// These three are the lowest-friction scopes Google offers and the ones that
  /// must never fail — keep this list minimal.
  String get _scope => requestDriveScope
      ? 'openid email profile $_driveAppdataScope'
      : 'openid email profile';

  /// Effective implicit response type, forced to bare `id_token` when no Drive
  /// scope is requested so we never ask for an access token we cannot use.
  String get _effectiveImplicitResponseType =>
      requestDriveScope ? implicitResponseType : 'id_token';

  final http.Client _http;
  final Random _random;

  @override
  Future<SuiOAuthTokens> signInForIdToken({
    required String nonce,
    SuiOAuthPrompt prompt = SuiOAuthPrompt.selectAccount,
  }) async {
    // CSRF guard: an unsolicited redirect carrying someone else's token must not
    // be accepted as a response to our request.
    final state = _randomUrlSafe(24);
    final verifier = flow == SuiOAuthFlow.authorizationCodePkce
        ? _randomUrlSafe(48)
        : null;

    final parameters = <String, String>{
      'client_id': clientId,
      'redirect_uri': redirectUri,
      // Identity scopes only by default. Drive is requested separately by
      // [authorizeDriveAppdata] so that a Drive-side problem cannot take down
      // authentication. See [requestDriveScope].
      'scope': _scope,
      'nonce': nonce,
      'state': state,
      ...prompt.parameters,
      if (flow == SuiOAuthFlow.implicitIdToken) ...{
        'response_type': _effectiveImplicitResponseType,
        'response_mode': 'fragment',
      },
      if (flow == SuiOAuthFlow.authorizationCodePkce) ...{
        'response_type': 'code',
        'code_challenge': _s256Challenge(verifier!),
        'code_challenge_method': 'S256',
      },
    };

    final authorizationUrl = Uri.parse(
      _authorizationEndpoint,
    ).replace(queryParameters: parameters).toString();

    final callback = await FlutterWebAuth2.authenticate(
      url: authorizationUrl,
      callbackUrlScheme: callbackUrlScheme,
      // Deliberately not ephemeral: an isolated browser session would force the
      // user to type their Google password on every sign-in. `prompt` above
      // already guarantees an explicit account choice, which is the property that
      // actually matters here, since `sub` determines the Sui address.
      options: FlutterWebAuth2Options(
        httpsHost: httpsHost,
        httpsPath: httpsPath,
      ),
    );

    final returned = _parseCallback(callback);
    final error = returned['error'];
    if (error != null) {
      throw SuiOAuthException(
        'Google rejected the sign-in request: $error',
      );
    }
    if (returned['state'] != state) {
      throw const SuiOAuthException(
        'OAuth state did not match the request. Sign-in was aborted.',
      );
    }

    final SuiOAuthTokens tokens = switch (flow) {
      // Implicit returns both tokens directly in the fragment.
      SuiOAuthFlow.implicitIdToken => SuiOAuthTokens(
        idToken: returned['id_token'] ?? '',
        accessToken: returned['access_token'],
      ),
      SuiOAuthFlow.authorizationCodePkce => await _exchangeCode(
        code: returned['code'],
        verifier: verifier!,
      ),
    };
    if (tokens.idToken.isEmpty) {
      throw const SuiOAuthException('Google returned no ID token');
    }

    // The backend re-checks this in constant time and is authoritative; this is
    // only a fast, clearer failure for a stale or replayed redirect.
    _assertNonceMatches(idToken: tokens.idToken, expected: nonce);
    return tokens;
  }

  /// Requests `drive.appdata` for an account that is already signed in.
  ///
  /// This is Google's incremental authorization pattern: ask for the minimum at
  /// sign-in, then ask for more later, at a moment where the reason is obvious to
  /// the user ("set up wallet recovery") rather than buried in an onboarding or
  /// money-claim flow.
  ///
  /// ## Why the same-account guarantee still holds
  ///
  /// The single-grant design existed to make it impossible for the Drive account
  /// and the zkLogin account to diverge — writing share B into the wrong person's
  /// Drive would be silent and unrecoverable. Splitting the grant reintroduces
  /// that risk, so it is closed explicitly rather than by construction:
  ///
  ///   * `login_hint` steers Google to the account already signed in.
  ///   * The returned ID token's `sub` is compared against [currentIdToken]'s, and
  ///     a mismatch throws. `login_hint` is a hint, not an enforcement — the user
  ///     can still switch accounts on the consent screen, so the check is what
  ///     actually guarantees the property.
  ///   * A fresh `nonce` is generated and verified, so a replayed redirect from an
  ///     earlier grant cannot be substituted.
  ///
  /// Returns `null` when the user declines. That is a normal outcome, not an
  /// error: the caller falls back to `provider_stored` salt custody.
  @override
  Future<SuiOAuthTokens?> authorizeDriveAppdata({
    required String currentIdToken,
  }) async {
    final expectedSubject = _claim(currentIdToken, 'sub');
    if (expectedSubject == null || expectedSubject.isEmpty) {
      throw const SuiOAuthException(
        'Cannot request Drive access without an established identity',
      );
    }

    final state = _randomUrlSafe(24);
    // Not a zkLogin nonce — nothing is bound to an ephemeral key here. It exists
    // purely so this grant's response cannot be replaced by an older one.
    final nonce = _randomUrlSafe(16);
    final verifier = flow == SuiOAuthFlow.authorizationCodePkce
        ? _randomUrlSafe(48)
        : null;

    final parameters = <String, String>{
      'client_id': clientId,
      'redirect_uri': redirectUri,
      // `openid` is requested alongside Drive so Google returns an ID token we can
      // use for the same-account check. Without it we would receive an access
      // token with no verifiable owner.
      'scope': 'openid $_driveAppdataScope',
      'nonce': nonce,
      'state': state,
      'login_hint': _claim(currentIdToken, 'email') ?? expectedSubject,
      // Preserve scopes already granted, so this grant adds Drive rather than
      // replacing the identity scopes.
      'include_granted_scopes': 'true',
      // Google shows no consent UI for an already-granted scope set, which would
      // silently return no access token on a retry. Forcing consent makes the
      // outcome deterministic.
      'prompt': 'consent',
      if (flow == SuiOAuthFlow.implicitIdToken) ...{
        'response_type': 'id_token token',
        'response_mode': 'fragment',
      },
      if (flow == SuiOAuthFlow.authorizationCodePkce) ...{
        'response_type': 'code',
        'code_challenge': _s256Challenge(verifier!),
        'code_challenge_method': 'S256',
      },
    };

    final authorizationUrl = Uri.parse(
      _authorizationEndpoint,
    ).replace(queryParameters: parameters).toString();

    final String callback;
    try {
      callback = await FlutterWebAuth2.authenticate(
        url: authorizationUrl,
        callbackUrlScheme: callbackUrlScheme,
        options: FlutterWebAuth2Options(
          httpsHost: httpsHost,
          httpsPath: httpsPath,
        ),
      );
    } on Exception {
      // Dismissing the browser is a decline, not a failure.
      return null;
    }

    final returned = _parseCallback(callback);
    if (returned['error'] != null) {
      // `access_denied` is the user refusing the Drive consent. Anything else is a
      // configuration fault worth surfacing, because it is silent otherwise: the
      // Drive API not enabled on the project, or the scope not declared under
      // Data Access, both land here.
      if (returned['error'] == 'access_denied') return null;
      throw SuiOAuthException(
        'Google rejected the Drive authorization request: ${returned['error']}',
      );
    }
    if (returned['state'] != state) {
      throw const SuiOAuthException(
        'OAuth state did not match the Drive authorization request.',
      );
    }

    final tokens = switch (flow) {
      SuiOAuthFlow.implicitIdToken => SuiOAuthTokens(
        idToken: returned['id_token'] ?? '',
        accessToken: returned['access_token'],
      ),
      SuiOAuthFlow.authorizationCodePkce => await _exchangeCode(
        code: returned['code'],
        verifier: verifier!,
      ),
    };

    if (tokens.idToken.isEmpty) {
      throw const SuiOAuthException(
        'Google returned no ID token for the Drive authorization',
      );
    }
    _assertNonceMatches(idToken: tokens.idToken, expected: nonce);

    if (_claim(tokens.idToken, 'sub') != expectedSubject) {
      // The user picked a different Google account. Writing share B here would
      // put it in the wrong Drive, and the loss would only surface on a future
      // recovery attempt.
      throw const SuiOAuthException(
        'Drive access was granted for a different Google account. '
        'Wallet recovery must use the account you signed in with.',
      );
    }

    if (tokens.accessToken == null || tokens.accessToken!.isEmpty) {
      // Granular permissions let a user approve the sign-in and refuse Drive.
      return null;
    }
    return tokens;
  }

  /// Exchanges an authorization code for an ID token.
  ///
  /// No client secret is sent: this path is only valid for a public (installed
  /// app) client, where PKCE replaces the secret. Uses a plain HTTP client on
  /// purpose so the app's Dio interceptor cannot attach the Zend bearer token to
  /// a third-party request.
  Future<SuiOAuthTokens> _exchangeCode({
    required String? code,
    required String verifier,
  }) async {
    if (code == null || code.isEmpty) {
      throw const SuiOAuthException('Google returned no authorization code');
    }
    final response = await _http.post(
      Uri.parse(_tokenEndpoint),
      body: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
      },
    );
    if (response.statusCode != 200) {
      // Body may carry an OAuth error code but never a usable credential.
      throw SuiOAuthException(
        'Google token exchange failed (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return SuiOAuthTokens(
      idToken: decoded['id_token'] as String? ?? '',
      accessToken: decoded['access_token'] as String?,
    );
  }

  /// Reads parameters from either the query string or the fragment.
  ///
  /// The implicit flow returns them in the fragment and the code flow in the
  /// query, so both are merged rather than assuming one shape.
  Map<String, String?> _parseCallback(String callback) {
    final uri = Uri.parse(callback);
    final merged = <String, String?>{...uri.queryParameters};
    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      merged.addAll(Uri.splitQueryString(fragment));
    }
    return merged;
  }

  void _assertNonceMatches({required String idToken, required String expected}) {
    if (_claims(idToken)['nonce'] != expected) {
      throw const SuiOAuthException(
        'The ID token nonce does not match this sign-in attempt',
      );
    }
  }

  /// Reads one string claim, or null when absent or not a string.
  ///
  /// Local decode only, with no signature verification — acceptable because every
  /// security decision derived from this token is made by the backend against a
  /// verified copy. These reads only steer the client: which account to hint at,
  /// and whether the account changed mid-flow.
  String? _claim(String idToken, String name) {
    final value = _claims(idToken)[name];
    return value is String ? value : null;
  }

  Map<String, dynamic> _claims(String idToken) {
    final parts = idToken.split('.');
    if (parts.length != 3) {
      throw const SuiOAuthException('Google returned a malformed ID token');
    }
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    return jsonDecode(utf8.decode(base64.decode(payload)))
        as Map<String, dynamic>;
  }

  String _s256Challenge(String verifier) {
    // PKCE verifiers are restricted to unreserved ASCII, so ascii is exact here.
    final digest = SHA256Digest().process(
      Uint8List.fromList(ascii.encode(verifier)),
    );
    return base64Url.encode(digest).replaceAll('=', '');
  }

  String _randomUrlSafe(int byteLength) {
    final bytes = List<int>.generate(byteLength, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Releases the HTTP client. Safe to call more than once.
  void dispose() => _http.close();
}

/// Thrown when the OAuth round-trip fails in a way the user must act on.
class SuiOAuthException implements Exception {
  const SuiOAuthException(this.message);
  final String message;

  @override
  String toString() => 'SuiOAuthException: $message';
}
