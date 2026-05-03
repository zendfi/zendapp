import 'api_client.dart';
import 'wallet_service.dart';
import '../models/api_models.dart';

class TransferService {
  final ApiClient _apiClient;
  final WalletService _walletService;

  String? _nextCursor;

  TransferService({
    required ApiClient apiClient,
    required WalletService walletService,
  })  : _apiClient = apiClient,
        _walletService = walletService;

  Future<TransferResponse> sendTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    required String pin,
    String? note,
  }) async {
    // Step 1: Prepare — resolves recipient, creates ATA if needed, returns
    // a fresh blockhash. This is the slow step for first-time recipients.
    final prepared = await _apiClient.prepareTransfer(
      recipientZendtag: recipientZendtag,
      amountUsdc: amountUsdc,
    );

    // Step 2: Build and sign the transaction locally using the server-provided
    // blockhash. The signature is always valid because the blockhash is fresh.
    final partiallySignedTxB64 =
        await _walletService.buildAndSignTransaction(
      pin: pin,
      amountUsdc: amountUsdc,
      recipientAddress: prepared.recipientWalletAddress,
      blockhash: prepared.blockhash,
      feePayerAddress: prepared.feePayer,
    );

    // Step 3: Submit the pre-signed transaction.
    return _apiClient.submitTransfer(
      recipientZendtag,
      amountUsdc,
      partiallySignedTxB64,
      note,
    );
  }

  Future<List<TransferHistoryEntry>> getHistory() async {
    _nextCursor = null;
    final response = await _apiClient.getTransferHistory();
    _nextCursor = response.nextCursor;
    return response.transfers;
  }

  Future<List<TransferHistoryEntry>> getNextPage() async {
    final response = await _apiClient.getTransferHistory(cursor: _nextCursor);
    _nextCursor = response.nextCursor;
    return response.transfers;
  }

  bool get hasMorePages => _nextCursor != null;
}
