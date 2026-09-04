import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import '../models/api_models.dart';
import '../models/api_exceptions.dart';
import 'sui_zklogin_models.dart';
import 'sui_zklogin_service.dart';
import 'wallet_service.dart';

/// Result of validating a locally-stored session against the backend.
///
/// - [valid]: the backend confirmed the JWT is still honored.
/// - [invalid]: the backend explicitly rejected the JWT (401) — the token
///   has already been cleared from secure storage by the time this is
///   returned.
/// - [unknown]: validation could not be confirmed either way (no network,
///   server error, timeout). Deliberately distinct from [invalid] — a
///   transient connectivity issue at launch must never be treated the same
///   as a confirmed-revoked session (zendapp-hardening Req 1.3).
enum SessionValidation { valid, invalid, unknown }

class AuthService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _secureStorage;

  static const _tokenKey = 'zend_session_token';

  static const _userIdKey = 'zend_user_id';
  static const _zendtagKey = 'zend_zendtag';
  static const _displayNameKey = 'zend_display_name';
  static const _walletAddressKey = 'zend_wallet_address';
  static const _avatarUrlKey = 'zend_avatar_url';

  /// How this device's account authenticates. Currently only [authMethodZkLogin]
  /// is ever written; a null value means the legacy OTP + local-keypair account
  /// shape, which is what every pre-zkLogin install has on disk.
  ///
  /// Startup routing depends on this: a zkLogin account has no Solana keypair and
  /// no PIN, so the keypair-based checks in `app.dart` would otherwise send it to
  /// a PIN restore screen that can never succeed.
  static const _authMethodKey = 'zend_auth_method';
  static const authMethodZkLogin = 'zklogin';

  String? _otpSessionId; // In-memory only
  String? _verificationToken; // In-memory only

  AuthService({
    required ApiClient apiClient,
    required FlutterSecureStorage secureStorage,
  }) : _apiClient = apiClient,
       _secureStorage = secureStorage;

  Future<String> requestOtp(String phoneNumber) async {
    final response = await _apiClient.requestOtp(phoneNumber);
    _otpSessionId = response.sessionId;
    return response.sessionId;
  }

  Future<String> requestOtpByEmail(String email) async {
    final response = await _apiClient.requestOtpByEmail(email);
    _otpSessionId = response.sessionId;
    return response.sessionId;
  }

  Future<OtpVerifyResponse> verifyOtp(String code) async {
    if (_otpSessionId == null) {
      throw StateError('No OTP session. Call requestOtp first.');
    }
    final response = await _apiClient.verifyOtp(_otpSessionId!, code);
    _verificationToken = response.verificationToken;
    return response;
  }

  Future<RegisterResponse> register(String displayName, String zendtag) async {
    if (_verificationToken == null) {
      throw StateError('No verification token. Call verifyOtp first.');
    }
    final response = await _apiClient.register(
      _verificationToken!,
      displayName,
      zendtag,
    );
    await _secureStorage.write(key: _tokenKey, value: response.sessionToken);
    _verificationToken = null;
    return response;
  }

  Future<AuthResponse> signIn() async {
    if (_verificationToken == null) {
      throw StateError('No verification token. Call verifyOtp first.');
    }
    final response = await _apiClient.signIn(_verificationToken!);
    await _secureStorage.write(key: _tokenKey, value: response.sessionToken);
    _verificationToken = null;
    return response;
  }

  /// Signs in with Google via zkLogin, creating the account if it is new.
  ///
  /// Replaces the whole `requestOtp` → `verifyOtp` → `register`/`signIn` sequence
  /// with a single call. There is no verification token to carry between steps
  /// because the Google ID token is itself the proof of identity.
  ///
  /// [zkLoginService] is injected rather than held as a field so this service
  /// keeps no dependency on the Sui stack when zkLogin is not in use, which keeps
  /// the OTP path above completely unaffected.
  Future<SuiZkLoginPublicSignIn> signInWithGoogle(
    SuiZkLoginService zkLoginService,
  ) async {
    final result = await zkLoginService.signInPublic();
    await _secureStorage.write(key: _tokenKey, value: result.sessionToken);
    await _secureStorage.write(key: _userIdKey, value: result.userId);
    await _secureStorage.write(key: _zendtagKey, value: result.zendtag);
    await _secureStorage.write(key: _displayNameKey, value: result.displayName);
    // Written last, and only after the session is durably stored: startup routing
    // keys off this, so a marker without a token would strand the next launch.
    await _secureStorage.write(
      key: _authMethodKey,
      value: authMethodZkLogin,
    );
    // A zkLogin-native account has no Solana wallet, so nothing is written to
    // _walletAddressKey here. Callers must treat a null wallet address as normal
    // rather than as a broken account.
    _verificationToken = null;
    return result;
  }

  /// True when this device's account signs in with Google via zkLogin.
  ///
  /// Such an account has no local Solana keypair and no PIN by design, so callers
  /// must not treat either absence as a broken or half-finished install.
  Future<bool> isZkLoginAccount() async {
    final method = await _secureStorage.read(key: _authMethodKey);
    return method == authMethodZkLogin;
  }

  /// Public wrapper to persist user identity to secure storage.
  Future<void> saveUserIdentity(UserProfileResponse profile) async {
    await _saveUserIdentity(profile);
  }

  /// Confirms the locally-stored JWT against the backend.
  ///
  /// This is the only reliable way to know whether a session is actually
  /// still authenticated — [isAuthenticated] only checks token *presence*,
  /// which is true even for an expired or revoked token (zendapp-hardening
  /// Req 1.3).
  ///
  /// Deliberately designed to be called **without awaiting** on the launch
  /// path: it costs a full network round trip, and only one of its three
  /// outcomes is actionable. `unknown` (offline, 5xx) must never be treated
  /// as a dead session or opening the app without a network would sign the
  /// user out, and `valid` changes nothing. That leaves a confirmed 401,
  /// which [ApiClient]'s interceptor already handles globally by deleting the
  /// token and invoking `ZendAppModel.handleUnauthorized` (Req 1.4).
  ///
  /// Callers must therefore not gate first paint on this. Note also that
  /// `handleUnauthorized` no-ops while `isAuthenticated` is false, so fire
  /// this only *after* the session has been established locally — otherwise
  /// a confirmed-dead session waits for the next API call to be noticed.
  Future<SessionValidation> validateStoredSession() async {
    final token = await _secureStorage.read(key: _tokenKey);
    if (token == null || token.isEmpty) return SessionValidation.invalid;
    try {
      await _apiClient.getBalance(); // validates JWT server-side
      return SessionValidation.valid;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // Backend explicitly rejected the token — clear it so no other
        // code path can mistake token presence for validity afterwards.
        await _clearAll();
        return SessionValidation.invalid;
      }
      // Any other API error (5xx, malformed response, etc.) is ambiguous —
      // do NOT clear the token or treat it as a confirmed invalid session.
      return SessionValidation.unknown;
    } catch (_) {
      // Network/timeout/connection error — ambiguous, not a confirmed
      // rejection. Clearing the token here would force a signed-out state
      // every time the user opens the app offline.
      return SessionValidation.unknown;
    }
  }

  /// Whether a JWT is present in secure storage. Local only — a single
  /// Keychain read, no network.
  ///
  /// This does NOT mean the session is valid: an expired or server-revoked
  /// token still passes. It is enough to decide *routing* at launch (signed
  /// out vs. resume), which is what the splash path uses it for; correctness
  /// against the server is then established by
  /// [validateStoredSession] in the background and by [ApiClient]'s global
  /// 401 handling.
  Future<bool> isAuthenticated() async {
    final token = await _secureStorage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    await _clearAll();
  }

  Future<void> _saveUserIdentity(UserProfileResponse profile) async {
    await _secureStorage.write(key: _userIdKey, value: profile.userId);
    await _secureStorage.write(key: _zendtagKey, value: profile.zendtag);
    await _secureStorage.write(
      key: _displayNameKey,
      value: profile.displayName,
    );
    if (profile.walletAddress != null) {
      await _secureStorage.write(
        key: _walletAddressKey,
        value: profile.walletAddress!,
      );
    }
    // Persist avatar URL — write null as empty string, restore as null
    await _secureStorage.write(
      key: _avatarUrlKey,
      value: profile.avatarUrl ?? '',
    );
  }

  Future<UserProfileResponse?> tryRestoreUserIdentity() async {
    // Concurrent, not sequential. This sits directly on the cold-launch path
    // (the native splash is held until session restore finishes), and each of
    // these is its own platform-channel round trip into the Keychain /
    // Keystore. Awaited one at a time, their latencies stacked; there is no
    // ordering dependency between them.
    //
    // Deliberately five targeted reads rather than one `readAll()`: readAll
    // would also pull and decrypt every unrelated entry in secure storage,
    // including the encrypted wallet key material.
    final values = await Future.wait([
      _secureStorage.read(key: _userIdKey),
      _secureStorage.read(key: _zendtagKey),
      _secureStorage.read(key: _displayNameKey),
      _secureStorage.read(key: _walletAddressKey),
      _secureStorage.read(key: _avatarUrlKey),
    ]);
    final userId = values[0];
    final zendtag = values[1];
    final displayName = values[2];
    final walletAddress = values[3];
    final avatarUrlRaw = values[4];
    final avatarUrl = (avatarUrlRaw != null && avatarUrlRaw.isNotEmpty)
        ? avatarUrlRaw
        : null;

    if (userId == null || zendtag == null || displayName == null) {
      return null;
    }

    return UserProfileResponse(
      userId: userId,
      zendtag: zendtag,
      displayName: displayName,
      walletAddress: walletAddress,
      avatarUrl: avatarUrl,
    );
  }

  /// Update the persisted avatar URL without re-fetching the full profile.
  Future<void> updateAvatarUrl(String? url) async {
    await _secureStorage.write(key: _avatarUrlKey, value: url ?? '');
  }

  Future<void> _clearAll() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _zendtagKey);
    await _secureStorage.delete(key: _displayNameKey);
    await _secureStorage.delete(key: _walletAddressKey);
    await _secureStorage.delete(key: _avatarUrlKey);
    await _secureStorage.delete(key: _authMethodKey);
    await WalletService.clearLocalDataFromStorage(_secureStorage);
    _otpSessionId = null;
    _verificationToken = null;
  }
}
