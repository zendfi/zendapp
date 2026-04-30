import 'api_client.dart';
import '../models/api_models.dart';

class FxService {
  final ApiClient _apiClient;

  FxService({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<FxPreviewResponse> getPreview(double amountUsd) async {
    return _apiClient.getFxPreview(amountUsd);
  }
}
