import 'api_client.dart';
import '../models/savings_models.dart';

class SavingsService {
  final ApiClient _apiClient;

  const SavingsService({required ApiClient apiClient})
      : _apiClient = apiClient;

  Future<SavingsMetrics> getSavingsMetrics() =>
      _apiClient.getSavingsMetrics();

  Future<SavingsPosition> getSavingsPosition() =>
      _apiClient.getSavingsPosition();

  Future<SavingsPrepareResponse> prepareDeposit(double amountUsdc) =>
      _apiClient.prepareSavingsDeposit(amountUsdc);

  Future<SavingsSubmitResult> submitDeposit(String partiallySignedTxB64) =>
      _apiClient.submitSavingsDeposit(partiallySignedTxB64);

  Future<SavingsPrepareResponse> prepareWithdraw() =>
      _apiClient.prepareSavingsWithdraw();

  Future<SavingsSubmitResult> submitWithdraw(String partiallySignedTxB64) =>
      _apiClient.submitSavingsWithdraw(partiallySignedTxB64);
}
