import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/api_models.dart';
import 'api_client.dart';
import 'payment_rails.dart';
import 'wallet_service.dart';

T _requireDependency<T>(T? dependency, String name) {
  if (dependency == null) {
    throw ArgumentError('TransferService requires $name');
  }
  return dependency;
}

class TransferService {
  final RailClient _railClient;
  final TransactionSigner _transactionSigner;

  String? _nextCursor;

  /// [apiClient] and [walletService] remain accepted for source compatibility.
  /// New composition roots can inject rail-specific interfaces directly.
  TransferService({
    ApiClient? apiClient,
    WalletService? walletService,
    RailClient? railClient,
    TransactionSigner? transactionSigner,
  }) : _railClient =
           railClient ??
           LegacySolanaRailClient(
             apiClient: _requireDependency(apiClient, 'apiClient'),
           ),
       _transactionSigner =
           transactionSigner ??
           SolanaTransactionSigner(
             walletService: _requireDependency(walletService, 'walletService'),
           ) {
    if (_railClient.rail != _transactionSigner.rail ||
        _railClient.network != _transactionSigner.network) {
      throw ArgumentError('Transfer client and signer must use the same rail');
    }
  }

  /// Sends a USDC transfer to [recipientZendtag]. The return type remains the
  /// legacy UI DTO while all rail-facing data stays neutral and opaque.
  Future<TransferResponse> sendTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    String? pin,
    Uint8List? keypairBytes,
    String? note,
  }) async {
    if ((pin == null) == (keypairBytes == null)) {
      throw ArgumentError(
        'Exactly one of pin or keypairBytes must be provided',
      );
    }

    // One key identifies this logical send and is reused for prepare, submit,
    // and any adapter-level retries of either request.
    final idempotencyKey = const Uuid().v4();
    final prepared = await _railClient.prepareTransfer(
      recipientZendtag: recipientZendtag,
      amountUsdc: amountUsdc,
      idempotencyKey: idempotencyKey,
    );

    final authorization = keypairBytes != null
        ? SigningAuthorization.withCachedKeypair(keypairBytes)
        : SigningAuthorization.withPin(pin!);
    final signedTransfer = await _transactionSigner.signPreparedTransfer(
      prepared: prepared,
      amountUsdc: amountUsdc,
      authorization: authorization,
    );

    final submission = await _railClient.submitTransfer(
      recipientZendtag: recipientZendtag,
      amountUsdc: amountUsdc,
      signedTransfer: signedTransfer,
      note: note,
    );
    return TransferResponse(
      transferId: submission.transferId,
      transactionSignature: submission.transactionId,
      slot: submission.slot ?? 0,
      status: submission.state,
    );
  }

  /// Preserves the legacy balance DTO expected by app state and screens while
  /// routing the request through the selected rail façade.
  Future<BalanceResponse> getBalance() async {
    final balance = await _railClient.getBalance();
    final usdc = balance.amountFor(PaymentAsset.usdc);
    return BalanceResponse(
      walletAddress: balance.walletAddress,
      solBalance: balance.amountFor(PaymentAsset.native),
      usdcBalance: usdc,
      spendableBalance: balance.spendable.amount,
    );
  }

  Future<List<TransferHistoryEntry>> getHistory() async {
    _nextCursor = null;
    final response = await _railClient.getTransferHistory();
    _nextCursor = response.nextCursor;
    return response.transfers
        .map(_toLegacyHistoryEntry)
        .toList(growable: false);
  }

  Future<List<TransferHistoryEntry>> getNextPage() async {
    final response = await _railClient.getTransferHistory(cursor: _nextCursor);
    _nextCursor = response.nextCursor;
    return response.transfers
        .map(_toLegacyHistoryEntry)
        .toList(growable: false);
  }

  bool get hasMorePages => _nextCursor != null;
}

TransferHistoryEntry _toLegacyHistoryEntry(RailHistoryEntry entry) {
  return TransferHistoryEntry(
    id: entry.transferId,
    senderZendtag: entry.senderZendtag,
    recipientZendtag: entry.recipientZendtag,
    amountUsdc: entry.amountUsdc,
    transactionSignature: entry.transactionId,
    note: entry.note,
    status: entry.state,
    createdAt: entry.createdAt,
    senderAvatarUrl: entry.senderAvatarUrl,
    recipientAvatarUrl: entry.recipientAvatarUrl,
    senderDisplayName: entry.senderDisplayName,
    recipientDisplayName: entry.recipientDisplayName,
    emailRecipientHint: entry.emailRecipientHint,
  );
}
