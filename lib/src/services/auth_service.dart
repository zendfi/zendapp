import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import '../models/api_models.dart';
import '../models/api_exceptions.dart';

class AuthService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _secureStorage;

  static const _tokenKey = 'zend_session_token';

  static const _userIdKey = 'zend_user_id';
  static const _zendtagKey = 'zend_zendtag';
  static const _displayNameKey = 'zend_display_name';
  static const _walletAddressKey = 'zend_wallet_address';

  String? _otpSessionId;       // In-memory only
  String? _verificationToken;  // In-memory only

  AuthService({required ApiClient apiClient, required FlutterSecureStorage secureStorage})
      : _apiClient = apiClient, _secureStorage = secureStorage;

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
    if (_otpSessionId == null) throw StateError('No OTP session. Call requestOtp first.');
    final response = await _apiClient.verifyOtp(_otpSessionId!, code);
    _verificationToken = response.verificationToken;
    return response;
  }

  Future<RegisterResponse> register(String displayName, String zendtag) async {
    if (_verificationToken == null) throw StateError('No verification token. Call verifyOtp first.');
    final response = await _apiClient.register(_verificationToken!, displayName, zendtag);
    await _secureStorage.write(key: _tokenKey, value: response.sessionToken);
    _verificationToken = null;
    return response;
  }

  Future<AuthResponse> signIn() async {
    if (_verificationToken == null) throw StateError('No verification token. Call verifyOtp first.');
    final response = await _apiClient.signIn(_verificationToken!);
    await _secureStorage.write(key: _tokenKey, value: response.sessionToken);
    _verificationToken = null;
    return response;
  }

  /// Public wrapper to persist user identity to secure storage.
  Future<void> saveUserIdentity(UserProfileResponse profile) async {
    await _saveUserIdentity(profile);
  }

  Future<bool> tryRestoreSession() async {
    final token = await _secureStorage.read(key: _tokenKey);
    if (token == null || token.isEmpty) return false;
    try {
      await _apiClient.getBalance(); // validates JWT
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _clearAll();
        return false;
      }
      rethrow;
    } catch (_) {
      return false;
    }
  }

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
    await _secureStorage.write(key: _displayNameKey, value: profile.displayName);
    if (profile.walletAddress != null) {
      await _secureStorage.write(key: _walletAddressKey, value: profile.walletAddress!);
    }
  }

  Future<UserProfileResponse?> tryRestoreUserIdentity() async {
    final userId = await _secureStorage.read(key: _userIdKey);
    final zendtag = await _secureStorage.read(key: _zendtagKey);
    final displayName = await _secureStorage.read(key: _displayNameKey);
    final walletAddress = await _secureStorage.read(key: _walletAddressKey);

    if (userId == null || zendtag == null || displayName == null) {
      return null;
    }

    return UserProfileResponse(
      userId: userId,
      zendtag: zendtag,
      displayName: displayName,
      walletAddress: walletAddress,
    );
  }

  Future<void> _clearAll() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _zendtagKey);
    await _secureStorage.delete(key: _displayNameKey);
    await _secureStorage.delete(key: _walletAddressKey);
    await _secureStorage.delete(key: 'zend_wallet_encrypted_private_key');
    await _secureStorage.delete(key: 'zend_wallet_public_key');
    await _secureStorage.delete(key: 'zend_pin_salt');
    await _secureStorage.delete(key: 'zend_encryption_nonce');
    _otpSessionId = null;
    _verificationToken = null;
  }
}
