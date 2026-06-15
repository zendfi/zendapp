import 'dart:typed_data';
import 'api_client.dart';
import 'wallet_service.dart';
import '../models/drop_models.dart';

class DropService {
  final ApiClient _apiClient;
  final WalletService _walletService;

  DropService({
    required ApiClient apiClient,
    required WalletService walletService,
  })  : _apiClient = apiClient,
        _walletService = walletService;

  /// Generates a fresh BLE beacon for the authenticated user (Receiver path).
  Future<BeaconGenerateResponse> generateBeacon() async {
    return _apiClient.generateBeacon();
  }

  /// Fetches an unconfirmed identity hint for display before GATT completes.
  Future<BeaconPreviewResponse> previewBeacon(String nonce) async {
    return _apiClient.previewBeacon(nonce);
  }

  /// Executes a Drop transfer (Sender path).
  ///
  /// Exactly one of [pin] or [keypairBytes] must be provided — same constraint
  /// as [TransferService.sendTransfer].
  Future<DropExecuteResponse> executeDropTransfer({
    required GattPayload beacon,
    required double amountUsdc,
    String? note,
    String? pin,
    Uint8List? keypairBytes,
  }) async {
    assert(
      (pin != null) ^ (keypairBytes != null),
      'Exactly one of pin or keypairBytes must be provided',
    );

    // Step 1: Prepare — resolves recipient, creates ATA, returns blockhash.
    // We reuse the existing prepareTransfer endpoint (same as regular sends).
    final prepared = await _apiClient.prepareDropTransfer(
      amountUsdc: amountUsdc,
      receiverZendtag: beacon.zendtag,
    );

    // Step 2: Build and sign the transaction locally.
    final String partiallySignedTxB64;
    if (keypairBytes != null) {
      partiallySignedTxB64 =
          await _walletService.buildAndSignTransactionFromCache(
        keypairBytes: keypairBytes,
        amountUsdc: amountUsdc,
        recipientAddress: prepared.recipientWalletAddress,
        blockhash: prepared.blockhash,
        feePayerAddress: prepared.feePayer,
      );
    } else {
      partiallySignedTxB64 = await _walletService.buildAndSignTransaction(
        pin: pin!,
        amountUsdc: amountUsdc,
        recipientAddress: prepared.recipientWalletAddress,
        blockhash: prepared.blockhash,
        feePayerAddress: prepared.feePayer,
      );
    }

    // Step 3: Submit the Drop execute request with the signed transaction.
    return _apiClient.executeDropTransfer(
      beacon: beacon,
      amountUsdc: amountUsdc,
      partiallySignedTxB64: partiallySignedTxB64,
      note: note,
    );
  }
}
