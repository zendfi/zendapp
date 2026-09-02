import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'sui_oauth_provider.dart' show SuiOAuthPrompt;
import 'sui_salt_custody_service.dart';
import 'sui_salt_shares.dart';
import 'sui_signing_service.dart';
import 'sui_zklogin_models.dart';

/// Obtains a nonce-bearing OpenID Connect ID token.
///
/// zkLogin requires the `nonce` to be embedded in the ID token, which rules out
/// the default `google_sign_in` flow: that plugin does not let callers set a
/// nonce. An implementation must run an OpenID Connect flow with
/// `response_type=id_token`, `scope=openid`, and the supplied nonce.
abstract interface class SuiOAuthProvider {
  /// Returns a raw ID token whose `nonce` claim equals [nonce].
  ///
  /// Requests identity scopes only. Drive access is obtained separately by
  /// [authorizeDriveAppdata], so that a Drive-side misconfiguration degrades
  /// wallet recovery rather than blocking all authentication. `accessToken` on the
  /// result is therefore normally null on this path.
  ///
  /// [prompt] controls how much user interaction is requested; see
  /// `SuiOAuthPrompt`. Implementations that cannot vary it may ignore it.
  Future<SuiOAuthTokens> signInForIdToken({
    required String nonce,
    SuiOAuthPrompt prompt,
  });

  /// Requests `drive.appdata` for the account identified by [currentIdToken].
  ///
  /// Called at the moment Drive is actually needed — provisioning or recovering
  /// salt shares — so the consent prompt carries obvious context.
  ///
  /// Returns null when the user declines, which is a normal outcome that callers
  /// must handle by falling back to non-Drive custody. Implementations must
  /// guarantee the grant belongs to the same Google account as [currentIdToken]:
  /// share B written into the wrong person's Drive fails silently now and
  /// unrecoverably later.
  Future<SuiOAuthTokens?> authorizeDriveAppdata({
    required String currentIdToken,
  });
}

/// Credentials from one OAuth grant.
class SuiOAuthTokens {
  const SuiOAuthTokens({required this.idToken, this.accessToken});

  /// Nonce-bound OpenID Connect ID token. Proves identity to the backend.
  final String idToken;

  /// Google API access token, present only when the flow requested a scope that
  /// needs one. Short-lived and never refreshed: it is used immediately for Drive
  /// during sign-in, provisioning, or recovery, then dropped.
  final String? accessToken;

  /// Never log this: both fields are live credentials.
  @override
  String toString() => 'SuiOAuthTokens(<redacted>)';
}

/// In-memory session state. Deliberately not persisted: the ephemeral private
/// key and proof together authorize transactions, so they live only for the
/// lifetime of the process.
class _ActiveSession {
  _ActiveSession({
    required this.sessionId,
    required this.keyPair,
    required this.jwtRandomness,
    required this.idToken,
    required this.maxEpoch,
    required this.expiresAt,
    this.accessToken,
  });

  final String sessionId;
  final SuiEphemeralKeyPair keyPair;
  final String jwtRandomness;
  final String idToken;

  /// Google API access token used to reach the Drive `appdata` folder holding
  /// share B.
  ///
  /// Normally null immediately after sign-in, because sign-in requests identity
  /// scopes only. Populated by `ensureDriveAccess()` when a Drive-backed operation
  /// actually needs it, then cached here so one provisioning or recovery sequence
  /// prompts at most once.
  ///
  /// Short-lived and never refreshed, so it is only good for the window after the
  /// grant. Verified to belong to the same Google account as [idToken] before being
  /// set — see `SuiOAuthProvider.authorizeDriveAppdata`.
  String? accessToken;
  final int maxEpoch;
  final DateTime expiresAt;

  /// Cached proof, fetched lazily and reused for every transfer in the session.
  Map<String, dynamic>? proof;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  void dispose() {
    keyPair.zeroize();
    proof = null;
  }
}

/// Orchestrates the Sui zkLogin session lifecycle.
///
/// Ordering is dictated by the protocol: the session (and therefore the nonce)
/// must exist before the OAuth redirect, because the nonce is what binds the
/// resulting ID token to this specific ephemeral key and epoch window.
class SuiZkLoginService {
  SuiZkLoginService({
    required ApiClient apiClient,
    required SuiOAuthProvider oauthProvider,
    SuiSigningService signingService = const SuiSigningService(),
    SuiSaltCustodyService? saltCustody,
  }) : _api = apiClient,
       _oauth = oauthProvider,
       _signing = signingService,
       _custody = saltCustody;

  final ApiClient _api;
  final SuiOAuthProvider _oauth;
  final SuiSigningService _signing;

  /// Sharded salt custody. Optional so this service still works on the
  /// whole-salt strategies, where the backend supplies the salt itself.
  final SuiSaltCustodyService? _custody;

  _ActiveSession? _session;

  /// True when a usable session is held, so the UI can skip re-authentication.
  bool get hasActiveSession => _session != null && !_session!.isExpired;

  /// Establishes a Sui identity and an active signing session.
  ///
  /// Steps, in the only order the protocol permits:
  ///   1. generate an ephemeral key pair and randomness locally
  ///   2. register the session so the backend derives nonce and maxEpoch
  ///   3. complete OAuth with that nonce
  ///   4. redeem the ID token for the linked Sui address
  Future<SuiZkLoginIdentity> signIn() async {
    final keyPair = await _signing.generateEphemeralKeyPair();
    final randomness = _generateRandomness();

    try {
      final init = await _api.createSuiZkLoginSession(
        extendedEphemeralPublicKey: keyPair.extendedPublicKeyBase64,
        jwtRandomness: randomness,
      );

      final tokens = await _oauth.signInForIdToken(nonce: init.nonce);

      final identity = await _api.redeemSuiZkLoginSession(
        sessionId: init.sessionId,
        idToken: tokens.idToken,
      );

      _replaceSession(
        _ActiveSession(
          sessionId: init.sessionId,
          keyPair: keyPair,
          jwtRandomness: randomness,
          idToken: tokens.idToken,
          accessToken: tokens.accessToken,
          maxEpoch: init.maxEpoch,
          expiresAt: init.expiresAt,
        ),
      );
      return identity;
    } catch (error) {
      // Never leave a live ephemeral key behind on a failed sign-in.
      keyPair.zeroize();
      rethrow;
    }
  }

  /// Signs in with Google, creating the Zend account if it does not exist.
  ///
  /// This is the replacement for the OTP flow, not an addition to it: it needs no
  /// existing Zend session and returns one. The ordering is the same as [signIn]
  /// and is forced by the protocol — the nonce must exist before the OAuth
  /// redirect, because it is what binds the ID token to this ephemeral key.
  ///
  /// The caller is responsible for persisting
  /// [SuiZkLoginPublicSignIn.sessionToken]; this service deliberately holds no
  /// storage handle, so it cannot leave a credential behind on disk.
  Future<SuiZkLoginPublicSignIn> signInPublic() async {
    final keyPair = await _signing.generateEphemeralKeyPair();
    final randomness = _generateRandomness();

    try {
      final init = await _api.createPublicSuiZkLoginSession(
        extendedEphemeralPublicKey: keyPair.extendedPublicKeyBase64,
        jwtRandomness: randomness,
      );

      final tokens = await _oauth.signInForIdToken(nonce: init.nonce);

      final result = await _api.publicSuiZkLoginSignIn(
        sessionId: init.sessionId,
        idToken: tokens.idToken,
      );

      // Retain the signing session so the first transfer after sign-in does not
      // need another OAuth round-trip.
      _replaceSession(
        _ActiveSession(
          sessionId: init.sessionId,
          keyPair: keyPair,
          jwtRandomness: randomness,
          idToken: tokens.idToken,
          accessToken: tokens.accessToken,
          maxEpoch: init.maxEpoch,
          expiresAt: init.expiresAt,
        ),
      );
      return result;
    } catch (error) {
      keyPair.zeroize();
      rethrow;
    }
  }

  /// Signs prepared Sui transaction bytes and returns a submittable zkLogin
  /// signature.
  ///
  /// The proof is fetched once per session and reused, which is why capacity is
  /// measured in active sessions rather than transactions.
  Future<String> signPreparedTransaction({
    required String transactionDataBcsBase64,
  }) async {
    // A zkLogin signing session is short-lived by design — that TTL is the only
    // bound on how long a stolen ephemeral key stays useful. Rather than surface
    // that to the user as a re-login roughly once a day, renew it silently first.
    // Google answers `prompt=none` without any UI while its own session is alive.
    if (!hasActiveSession) {
      await renewSessionSilently();
    }

    final session = _requireSession();

    // Under sharded custody the backend cannot rebuild the salt, so it is
    // reconstructed here and supplied with the proof request. Only needed when a
    // proof is actually being fetched — proofs are cached for the whole session,
    // so this is at most one reconstruction per sign-in rather than per transfer.
    final proof = session.proof ??= (await _api.requestSuiZkLoginProof(
      sessionId: session.sessionId,
      idToken: session.idToken,
      extendedEphemeralPublicKey: session.keyPair.extendedPublicKeyBase64,
      jwtRandomness: session.jwtRandomness,
      salt: await _reconstructSaltIfSharded(session),
    )).payload;

    final signature = await _signing.signPreparedTransfer(
      transactionDataBcsBase64: transactionDataBcsBase64,
      keyPair: session.keyPair,
    );

    return _api.assembleSuiZkLoginSignature(
      sessionId: session.sessionId,
      idToken: session.idToken,
      proof: proof,
      ephemeralSignature: signature.signatureBase64,
      extendedEphemeralPublicKey: session.keyPair.extendedPublicKeyBase64,
    );
  }

  /// Reconstructs the salt for a proof request, or null when custody is not
  /// sharded.
  ///
  /// Failures are surfaced rather than swallowed: a proof built without the right
  /// salt would commit to an address the user does not control, so failing the
  /// transfer is strictly better than producing one.
  Future<String?> _reconstructSaltIfSharded(_ActiveSession session) async {
    final custody = _custody;
    if (custody == null) return null;

    // Reconstruction needs any two of three shares. The device share is present on
    // a device that has provisioned before, so the common case needs no Drive and
    // therefore no consent prompt mid-transfer. Only when the device share is
    // missing — a reinstall, or a new device — is Drive the second share, and only
    // then is it worth interrupting the user.
    //
    // Deliberately best-effort: if the prompt is declined, fall through and let
    // reconstruction fail on its own terms with a message about shares rather than
    // about Google.
    // On web `keepsDeviceShare` is false, so this always takes the Drive branch —
    // which is correct, since the web client deliberately holds no share.
    var accessToken = session.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      final deviceShare = await custody.readDeviceShare();
      if (deviceShare == null || deviceShare.isEmpty) {
        accessToken = await ensureDriveAccess();
      }
    }

    final salt = await custody.reconstructSalt(
      sessionId: session.sessionId,
      idToken: session.idToken,
      accessToken: accessToken,
    );
    try {
      return saltToDecimalString(salt);
    } finally {
      for (var i = 0; i < salt.length; i++) {
        salt[i] = 0;
      }
    }
  }

  /// Moves this account onto 2-of-3 sharded salt custody.
  ///
  /// Reads the whole salt once, splits it, and distributes the shares. Splitting
  /// the *existing* salt rather than generating a new one is what preserves the
  /// user's address — the address derives from the salt, so a fresh one would
  /// strand any funds already held.
  ///
  /// Acquires Drive access for the current session if it does not already have it.
  ///
  /// Sign-in deliberately does not request Drive, so this is where the second,
  /// in-context consent happens. Caches the token on the session so a single
  /// provisioning or recovery sequence prompts at most once.
  ///
  /// Returns null when the user declines.
  Future<String?> ensureDriveAccess() async {
    final session = _requireSession();
    final existing = session.accessToken;
    if (existing != null && existing.isNotEmpty) return existing;

    final granted = await _oauth.authorizeDriveAppdata(
      currentIdToken: session.idToken,
    );
    final token = granted?.accessToken;
    if (token == null || token.isEmpty) return null;

    session.accessToken = token;
    return token;
  }

  /// Prompts for Drive access if the session does not already hold it.
  Future<void> provisionSaltShares() async {
    final custody = _custody;
    if (custody == null) {
      throw StateError('Salt custody is not configured');
    }
    final session = _requireSession();
    final accessToken = await ensureDriveAccess();
    if (accessToken == null || accessToken.isEmpty) {
      throw const SuiSaltRecoveryException(
        'Google Drive access is required to set up wallet recovery',
      );
    }

    final decimal = await _api.exportSuiZkLoginSalt(
      sessionId: session.sessionId,
      idToken: session.idToken,
    );
    final salt = _saltFromDecimalString(decimal);
    try {
      await custody.provisionShares(
        salt: salt,
        sessionId: session.sessionId,
        idToken: session.idToken,
        accessToken: accessToken,
      );
    } finally {
      for (var i = 0; i < salt.length; i++) {
        salt[i] = 0;
      }
    }
  }

  /// Parses the decimal salt the backend exports into its 16 big-endian bytes.
  Uint8List _saltFromDecimalString(String decimal) {
    final value = BigInt.parse(decimal.trim());
    if (value.isNegative || value.bitLength > kSaltBytes * 8) {
      throw const SuiSaltRecoveryException('Exported salt is out of range');
    }
    final bytes = Uint8List(kSaltBytes);
    var remaining = value;
    for (var i = kSaltBytes - 1; i >= 0; i--) {
      bytes[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining = remaining >> 8;
    }
    return bytes;
  }

  /// Re-establishes a signing session without involving the user.
  ///
  /// Uses the authenticated session/redeem pair rather than the public sign-in
  /// route: the account already exists and the caller already holds a Zend
  /// session, so this only needs a fresh ephemeral key and proof — it must not
  /// mint a second Zend session or risk resolving a different account.
  ///
  /// Throws [SuiZkLoginSessionExpired] if Google declines to answer silently,
  /// which is the signal for the caller to fall back to an interactive sign-in.
  Future<void> renewSessionSilently() async {
    final keyPair = await _signing.generateEphemeralKeyPair();
    final randomness = _generateRandomness();

    try {
      final init = await _api.createSuiZkLoginSession(
        extendedEphemeralPublicKey: keyPair.extendedPublicKeyBase64,
        jwtRandomness: randomness,
      );

      final tokens = await _oauth.signInForIdToken(
        nonce: init.nonce,
        prompt: SuiOAuthPrompt.none,
      );

      await _api.redeemSuiZkLoginSession(
        sessionId: init.sessionId,
        idToken: tokens.idToken,
      );

      _replaceSession(
        _ActiveSession(
          sessionId: init.sessionId,
          keyPair: keyPair,
          jwtRandomness: randomness,
          idToken: tokens.idToken,
          accessToken: tokens.accessToken,
          maxEpoch: init.maxEpoch,
          expiresAt: init.expiresAt,
        ),
      );
    } catch (error) {
      keyPair.zeroize();
      debugPrint('[SuiZkLogin] silent renewal failed: $error');
      throw const SuiZkLoginSessionExpired(
        'Your Sui session expired and could not be renewed silently. '
        'Please sign in again.',
      );
    }
  }

  /// Satisfies the backend's step-up requirement for a high-value transfer.
  ///
  /// Forces Google to re-verify the person rather than accepting a cached
  /// authentication, which is what makes this stronger than any local prompt: it
  /// needs the Google credential, not just possession of the device.
  ///
  /// Deliberately does not replace the active signing session. A step-up proves
  /// who is present; it is not a new signing grant, and conflating the two would
  /// silently extend the ephemeral key's lifetime.
  Future<void> satisfyStepUp() async {
    final keyPair = await _signing.generateEphemeralKeyPair();
    try {
      final init = await _api.createSuiZkLoginSession(
        extendedEphemeralPublicKey: keyPair.extendedPublicKeyBase64,
        jwtRandomness: _generateRandomness(),
      );
      final tokens = await _oauth.signInForIdToken(
        nonce: init.nonce,
        prompt: SuiOAuthPrompt.reauthenticate,
      );
      await _api.suiZkLoginStepUp(
        sessionId: init.sessionId,
        idToken: tokens.idToken,
      );
    } finally {
      // This key never signs anything, so it is discarded immediately.
      keyPair.zeroize();
    }
  }

  /// Clears local session state and revokes server-side sessions.
  Future<void> signOut() async {
    _replaceSession(null);
    try {
      await _api.revokeAllSuiZkLoginSessions();
    } catch (error) {
      // Local state is already gone; a failed revoke must not block logout.
      debugPrint('[SuiZkLogin] revoke-all failed (non-fatal): $error');
    }
  }

  _ActiveSession _requireSession() {
    final session = _session;
    if (session == null) {
      throw const SuiZkLoginSessionExpired('No active zkLogin session');
    }
    if (session.isExpired) {
      _replaceSession(null);
      throw const SuiZkLoginSessionExpired(
        'Your Sui session expired. Please sign in again.',
      );
    }
    return session;
  }

  void _replaceSession(_ActiveSession? next) {
    _session?.dispose();
    _session = next;
  }

  /// Generates `jwtRandomness` as a decimal string below 2^128, which is the
  /// form the nonce derivation and prover both expect.
  String _generateRandomness() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value.toString();
  }
}

/// Debug-only OAuth provider for driving the flow with a token obtained out of
/// band (for example from a browser sign-in during staging validation).
///
/// Refuses to run in release builds so it cannot become a production path.
class ManualIdTokenOAuthProvider implements SuiOAuthProvider {
  ManualIdTokenOAuthProvider(this._idToken) {
    if (kReleaseMode) {
      throw StateError(
        'Manual ID token provider is not usable in release mode',
      );
    }
  }

  final String _idToken;

  @override
  Future<SuiOAuthTokens> signInForIdToken({
    required String nonce,
    SuiOAuthPrompt prompt = SuiOAuthPrompt.selectAccount,
  }) async {
    // The backend rejects a mismatched nonce, so a stale pasted token fails
    // loudly rather than producing an unusable session.
    final payload = _decodeClaims(_idToken);
    final tokenNonce = payload['nonce'];
    if (tokenNonce != nonce) {
      throw StateError(
        'Pasted ID token nonce does not match this session. '
        'Re-run the OAuth flow with nonce=$nonce',
      );
    }
    // No access token: a pasted ID token carries no Drive grant, so share B is
    // unreachable on this path. Acceptable, since this provider is debug-only.
    return SuiOAuthTokens(idToken: _idToken);
  }

  @override
  Future<SuiOAuthTokens?> authorizeDriveAppdata({
    required String currentIdToken,
  }) async {
    // No browser round trip is possible here, so Drive-backed custody is simply
    // unavailable when driving the flow with a pasted token. Null is the
    // "declined" signal, which callers already handle by falling back.
    return null;
  }

  Map<String, dynamic> _decodeClaims(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) {
      throw const FormatException('Not a JWT');
    }
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    return jsonDecode(utf8.decode(base64.decode(payload)))
        as Map<String, dynamic>;
  }
}
