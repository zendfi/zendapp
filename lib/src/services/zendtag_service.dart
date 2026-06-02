import 'api_client.dart';
import '../models/api_models.dart';

class ZendtagService {
  final ApiClient _apiClient;

  ZendtagService({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<bool> checkAvailability(String tag) async {
    final response = await _apiClient.checkZendtag(tag);
    return response.available;
  }

  Future<ZendtagResolveResponse> resolve(String tag) async {
    return _apiClient.resolveZendtag(tag);
  }

  /// Looks up a registered Zend! account by email address.
  /// Throws if no account is found (caller checks for EMAIL_NOT_FOUND code).
  Future<ZendtagResolveResponse> resolveByEmail(String email) async {
    return _apiClient.resolveByEmail(email);
  }
}
