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
}
