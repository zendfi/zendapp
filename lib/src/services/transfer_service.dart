import 'dart:typed_data';

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

  /// Sends a USDC transfer to [recipientZendtag].
  ///
  /// Exactly one of [pin] or [keypairBytes] must be provided:
  /// - [pin]: standard PIN path — decrypts the keypair on-device each time.
  /// - [keypairBytes]: session-signing path — uses a pre-decrypted keypair
  ///   from [WalletSessionCache]. The bytes are zeroed inside [WalletService].
  ///
  /// Pass [amountUsdc] so the correct signing variant is dispatched.
  Future<TransferResponse> sendTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    String? pin,
    Uint8List? keypairBytes,
    String? note,
  }) async {
    assert(
      (pin != null) ^ (keypairBytes != null),
      'Exactly one of pin or keypairBytes must be provided',
    );

    // Step 1: Prepare — resolves recipient, creates ATA if needed, returns
    // a fresh blockhash. This is the slow step for first-time recipients.
    final prepared = await _apiClient.prepareTransfer(
      recipientZendtag: recipientZendtag,
      amountUsdc: amountUsdc,
    );

    // Step 2: Build and sign the transaction locally.
    final String partiallySignedTxB64;
    if (keypairBytes != null) {
      // Session-signing path
      partiallySignedTxB64 =
          await _walletService.buildAndSignTransactionFromCache(
        keypairBytes: keypairBytes,
        amountUsdc: amountUsdc,
        recipientAddress: prepared.recipientWalletAddress,
        blockhash: prepared.blockhash,
        feePayerAddress: prepared.feePayer,
      );
    } else {
      // PIN path
      partiallySignedTxB64 = await _walletService.buildAndSignTransaction(
        pin: pin!,
        amountUsdc: amountUsdc,
        recipientAddress: prepared.recipientWalletAddress,
        blockhash: prepared.blockhash,
        feePayerAddress: prepared.feePayer,
      );
    }

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
