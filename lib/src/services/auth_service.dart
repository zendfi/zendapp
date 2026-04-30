import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import '../models/api_models.dart';
import '../models/api_exceptions.dart';

class AuthService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _secureStorage;

  static const _tokenKey = 'zend_session_token';

  String? _otpSessionId;       // In-memory only
  String? _verificationToken;  // In-memory only

  AuthService({required ApiClient apiClient, required FlutterSecureStorage secureStorage})
      : _apiClient = apiClient, _secureStorage = secureStorage;

  Future<String> requestOtp(String phoneNumber) async {
    final response = await _apiClient.requestOtp(phoneNumber);
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

  Future<void> _clearAll() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: 'zend_wallet_encrypted_private_key');
    await _secureStorage.delete(key: 'zend_wallet_public_key');
    await _secureStorage.delete(key: 'zend_pin_salt');
    await _secureStorage.delete(key: 'zend_encryption_nonce');
    _otpSessionId = null;
    _verificationToken = null;
  }
}
