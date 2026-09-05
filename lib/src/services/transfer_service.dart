import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/api_exceptions.dart';
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
  ///
  /// Recorded even when no router is present. Previously this was
  /// `_railRouter?.allowLocalKeyRailFallback = value`, which silently discarded
  /// the value in that case — and discarding *false* is the dangerous direction:
  /// it leaves a zkLogin account believing it may fall back to Solana, which is
  /// precisely the state that produces a misleading `WALLET_NOT_REGISTERED`.
  /// Keeping the field means [_bindingFor] can assert on it rather than depending
  /// on call ordering.
  set accountUsesLocalKeyRail(bool value) {
    _accountUsesLocalKeyRail = value;
    _railRouter?.allowLocalKeyRailFallback = value;
  }

  /// Last value given to [accountUsesLocalKeyRail], or null if never set.
  ///
  /// Null is distinct from `true`: it means the account type was never
  /// established, which is a wiring fault rather than a legacy account.
  bool? _accountUsesLocalKeyRail;

  /// Resolves the rail for [operations], falling back to the fixed pair when no
  /// router was supplied.
  Future<({RailClient client, TransactionSigner signer})> _bindingFor(
    Set<PaymentOperation> operations,
  ) async {
    final router = _railRouter;
    if (router == null) {
      // The fixed pair is Solana, so an account that cannot sign with a local key
      // has no usable rail here. Failing with the real reason beats proceeding and
      // surfacing `WALLET_NOT_REGISTERED`, which tells a Google-sign-in user to
      // store a wallet backup — a concept their account does not have.
      if (_accountUsesLocalKeyRail == false) {
        throw const RailUnavailableException(null);
      }
      return (client: _railClient, signer: _transactionSigner);
    }
    // Re-assert rather than trusting that the setter ran before the router was
    // attached. Cheap, and it removes an ordering dependency between sign-in and
    // service composition that has already caused one production incident.
    final localKeyRail = _accountUsesLocalKeyRail;
    if (localKeyRail != null) {
      router.allowLocalKeyRailFallback = localKeyRail;
    }
    final binding = await router.resolve(
      operations: operations,
      fallback: _railClient.rail,
    );
    return (client: binding.client, signer: binding.signer);
  }

  /// Rail error meaning "the funds exist but are in a form this rail cannot spend".
  ///
  /// On Sui, value lives either in `Coin<T>` objects or in a per-address accumulator,
  /// and gasless transfers can only draw on the accumulator. Anything arriving from
  /// outside Zend — an exchange withdrawal, an external wallet, a CCTP mint — lands as
  /// coin objects, which count towards the balance but cannot be sent.
  static const _fundsInWrongFormCode = 'SUI_ADDRESS_BALANCE_INSUFFICIENT';

  /// Prepares the transfer, converting funds into spendable form first if the rail
  /// says they are not.
  ///
  /// Handled here rather than surfaced as a separate user action, because "your money
  /// is in the wrong internal representation" is not something a payments app should
  /// ask a user to understand. They tap send once; two transactions may happen.
  ///
  /// This costs no extra authentication: the zkLogin proof is cached for the session,
  /// so the deposit reuses it and there is no second Google round-trip.
  ///
  /// Retried exactly once. A second identical failure means something other than the
  /// fund form is wrong — most likely that the deposit has not been indexed yet — and
  /// looping on it would turn a visible error into a hang. The message from the rail
  /// already names both the spendable and the parked amounts, so it is worth showing.
  Future<PreparedRailTransfer> _prepareMakingFundsSpendableIfNeeded({
    required ({RailClient client, TransactionSigner signer}) binding,
    required String recipientZendtag,
    required double amountUsdc,
    required String idempotencyKey,
  }) async {
    try {
      return await binding.client.prepareTransfer(
        recipientZendtag: recipientZendtag,
        amountUsdc: amountUsdc,
        idempotencyKey: idempotencyKey,
      );
    } on ApiException catch (error) {
      if (error.errorCode != _fundsInWrongFormCode) rethrow;

      final converted = await binding.signer.makeFundsSpendable();
      if (!converted) rethrow;

      // A fresh key, deliberately. The backend caches the *failed* prepare
      // response against its idempotency key for 90 seconds, so retrying under the
      // original key replays the pre-deposit rejection without ever reaching the
      // rail — the funds move, and the transfer still fails with a stale error.
      //
      // Safe because prepare only builds an unsigned transaction and moves nothing.
      // Submit keeps its own key in a separate namespace, so double-send protection
      // is unaffected by this.
      return binding.client.prepareTransfer(
        recipientZendtag: recipientZendtag,
        amountUsdc: amountUsdc,
        idempotencyKey: const Uuid().v4(),
      );
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

    /// Who may see this transfer in Activity. Null inherits the sender's profile
    /// default rather than forcing a choice.
    TransferVisibility? visibility,
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
    final prepared = await _prepareMakingFundsSpendableIfNeeded(
      binding: binding,
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
      visibility: visibility,
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
