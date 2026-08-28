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

  /// When present, the rail is resolved per operation from the backend's
  /// capabilities instead of being fixed at construction. Absent in tests and in
  /// legacy composition, which keeps the original single-rail behaviour intact.
  final RailRouter? _railRouter;

  String? _nextCursor;

  /// [apiClient] and [walletService] remain accepted for source compatibility.
  /// New composition roots can inject rail-specific interfaces directly.
  TransferService({
    ApiClient? apiClient,
    WalletService? walletService,
    RailClient? railClient,
    TransactionSigner? transactionSigner,
    RailRouter? railRouter,
  }) : _railRouter = railRouter,
       _railClient =
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

  /// Declares whether this account can use a rail that signs with a local key.
  ///
  /// False for a zkLogin account, which has no Solana wallet. Set after sign-in
  /// and on session restore, once the account type is known. A setter rather than
  /// a constructor argument because the account type is not known at composition
  /// time — the app has to read it from storage first.
  set accountUsesLocalKeyRail(bool value) {
    _railRouter?.allowLocalKeyRailFallback = value;
  }

  /// Resolves the rail for [operations], falling back to the fixed pair when no
  /// router was supplied.
  Future<({RailClient client, TransactionSigner signer})> _bindingFor(
    Set<PaymentOperation> operations,
  ) async {
    final router = _railRouter;
    if (router == null) {
      return (client: _railClient, signer: _transactionSigner);
    }
    final binding = await router.resolve(
      operations: operations,
      fallback: _railClient.rail,
    );
    return (client: binding.client, signer: binding.signer);
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
    // Resolved before validating authorization, because whether a local secret is
    // even required depends on the rail: a zkLogin account signs with an
    // in-memory ephemeral key and has no PIN or stored keypair to supply.
    final binding = await _bindingFor({
      PaymentOperation.prepare,
      PaymentOperation.submit,
    });
    final needsLocalSecret = binding.signer.rail == PaymentRail.solana;

    if (needsLocalSecret && (pin == null) == (keypairBytes == null)) {
      // Reached either by a genuine caller mistake, or by an account with no
      // local key being routed to a rail that requires one — which happens when
      // a zkLogin account's own rail is unavailable. Both are unrecoverable here,
      // so name the real condition rather than only the missing argument.
      throw ArgumentError(
        'This transfer resolved to the ${binding.signer.rail.name} rail, which '
        'signs with a local key. Exactly one of pin or keypairBytes is required.',
      );
    }

    // One key identifies this logical send and is reused for prepare, submit,
    // and any adapter-level retries of either request.
    final idempotencyKey = const Uuid().v4();
    final prepared = await binding.client.prepareTransfer(
      recipientZendtag: recipientZendtag,
      amountUsdc: amountUsdc,
      idempotencyKey: idempotencyKey,
    );

    final SigningAuthorization authorization;
    if (!needsLocalSecret) {
      authorization = const SigningAuthorization.none();
    } else if (keypairBytes != null) {
      authorization = SigningAuthorization.withCachedKeypair(keypairBytes);
    } else {
      authorization = SigningAuthorization.withPin(pin!);
    }
    final signedTransfer = await binding.signer.signPreparedTransfer(
      prepared: prepared,
      amountUsdc: amountUsdc,
      authorization: authorization,
    );

    final submission = await binding.client.submitTransfer(
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
    final binding = await _bindingFor({PaymentOperation.balance});
    final balance = await binding.client.getBalance();
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
    final binding = await _bindingFor({PaymentOperation.history});
    final response = await binding.client.getTransferHistory();
    _nextCursor = response.nextCursor;
    return response.transfers
        .map(_toLegacyHistoryEntry)
        .toList(growable: false);
  }

  Future<List<TransferHistoryEntry>> getNextPage() async {
    final binding = await _bindingFor({PaymentOperation.history});
    final response = await binding.client.getTransferHistory(
      cursor: _nextCursor,
    );
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
