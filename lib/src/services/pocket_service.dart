import 'api_client.dart';
import '../models/pocket_models.dart';
import '../models/savings_models.dart';

class PocketService {
  final ApiClient _apiClient;

  const PocketService({required ApiClient apiClient})
      : _apiClient = apiClient;

  Future<List<SavingsPocket>> listPockets() => _apiClient.listPockets();

  Future<SavingsPocket> getPocket(String pocketId) =>
      _apiClient.getPocket(pocketId);

  Future<SavingsPocket> createGoal(CreateGoalRequest req) =>
      _apiClient.createGoal(req);

  Future<void> deleteGoal(String pocketId) => _apiClient.deleteGoal(pocketId);

  Future<SavingsPocket> createLock(CreateLockRequest req) =>
      _apiClient.createLock(req);

  Future<SavingsPrepareResponse> prepareFreeWithdraw(double amountUsd) =>
      _apiClient.prepareFreeWithdraw(amountUsd);

  Future<SavingsSubmitResult> submitFreeWithdraw(String signedTx) =>
      _apiClient.submitFreeWithdraw(signedTx);

  Future<SavingsPrepareResponse> prepareGoalWithdraw(String pocketId) =>
      _apiClient.prepareGoalWithdraw(pocketId);

  Future<SavingsSubmitResult> submitGoalWithdraw(
          String pocketId, String signedTx) =>
      _apiClient.submitGoalWithdraw(pocketId, signedTx);

  Future<SavingsPrepareResponse> prepareLockWithdraw() =>
      _apiClient.prepareLockWithdraw();

  Future<SavingsSubmitResult> submitLockWithdraw(String signedTx) =>
      _apiClient.submitLockWithdraw(signedTx);
}
