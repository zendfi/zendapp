import 'api_client.dart';
import 'wallet_service.dart';
import 'zendtag_service.dart';
import '../models/api_models.dart';

class TransferService {
  final ApiClient _apiClient;
  final WalletService _walletService;
  final ZendtagService _zendtagService;

  String? _nextCursor;

  TransferService({
    required ApiClient apiClient,
    required WalletService walletService,
    required ZendtagService zendtagService,
  })  : _apiClient = apiClient,
        _walletService = walletService,
        _zendtagService = zendtagService;

  Future<TransferResponse> sendTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    required String pin,
    String? note,
  }) async {
    final resolved = await _zendtagService.resolve(recipientZendtag);

    final partiallySignedTxB64 = await _walletService.buildAndSignTransaction(
      pin: pin,
      amountUsdc: amountUsdc,
      recipientAddress: resolved.walletAddress,
    );

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
