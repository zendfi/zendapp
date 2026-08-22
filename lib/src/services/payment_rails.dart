import 'dart:typed_data';

import 'api_client.dart';
import 'payment_rail_models.dart';
import 'wallet_service.dart';

export 'payment_rail_models.dart';

/// Chain-scoped access to the wallet's public identity.
abstract interface class WalletIdentity {
  PaymentRail get rail;
  PaymentNetwork get network;

  Future<String?> getAddress();
}

/// Authorization supplied to a local transaction signer.
class SigningAuthorization {
  final String? pin;
  final Uint8List? keypairBytes;

  const SigningAuthorization._({this.pin, this.keypairBytes});

  factory SigningAuthorization.withPin(String pin) {
    return SigningAuthorization._(pin: pin);
  }

  factory SigningAuthorization.withCachedKeypair(Uint8List keypairBytes) {
    return SigningAuthorization._(keypairBytes: keypairBytes);
  }
}

/// Signs opaque preparation data locally. Shared send orchestration never
/// interprets chain-specific payload fields.
abstract interface class TransactionSigner {
  PaymentRail get rail;
  PaymentNetwork get network;

  Future<SignedRailTransfer> signPreparedTransfer({
    required PreparedRailTransfer prepared,
    required double amountUsdc,
    required SigningAuthorization authorization,
  });
}

/// Network operations for one explicitly selected payment rail.
abstract interface class RailClient {
  PaymentRail get rail;
  PaymentNetwork get network;

  Future<RailBalance> getBalance();

  Future<PreparedRailTransfer> prepareTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    required String idempotencyKey,
  });

  Future<RailSubmission> submitTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    required SignedRailTransfer signedTransfer,
    String? note,
  });

  Future<RailHistory> getTransferHistory({String? cursor, int? limit});
}

class SolanaWalletIdentity implements WalletIdentity {
  final WalletService _walletService;

  SolanaWalletIdentity({required WalletService walletService})
    : _walletService = walletService;

  @override
  PaymentRail get rail => PaymentRail.solana;

  @override
  PaymentNetwork get network => PaymentNetwork.mainnet;

  @override
  Future<String?> getAddress() => _walletService.getWalletAddress();
}

/// The only component allowed to parse Solana preparation fields. It delegates
/// byte production to [WalletService], preserving the existing transaction
/// builder, signature order, and serialized bytes exactly.
class SolanaTransactionSigner implements TransactionSigner {
  final WalletService _walletService;

  SolanaTransactionSigner({required WalletService walletService})
    : _walletService = walletService;

  @override
  PaymentRail get rail => PaymentRail.solana;

  @override
  PaymentNetwork get network => PaymentNetwork.mainnet;

  @override
  Future<SignedRailTransfer> signPreparedTransfer({
    required PreparedRailTransfer prepared,
    required double amountUsdc,
    required SigningAuthorization authorization,
  }) async {
    if (prepared.provenance.rail != rail ||
        prepared.provenance.network != network ||
        prepared.provenance.asset != PaymentAsset.usdc ||
        prepared.envelope.type != 'solana_legacy_prepare' ||
        prepared.envelope.version != 1) {
      throw StateError('Unsupported Solana preparation envelope');
    }

    final payload = prepared.envelope.payload;
    final recipientAddress = payload['recipient_wallet_address'] as String;
    final blockhash = payload['blockhash'] as String;
    final feePayer = payload['fee_payer'] as String;
    final senderAta = payload['sender_ata'] as String?;
    final recipientAta = payload['recipient_ata'] as String?;

    final String transaction;
    final keypairBytes = authorization.keypairBytes;
    if (keypairBytes != null) {
      transaction = await _walletService.buildAndSignTransactionFromCache(
        keypairBytes: keypairBytes,
        amountUsdc: amountUsdc,
        recipientAddress: recipientAddress,
        blockhash: blockhash,
        feePayerAddress: feePayer,
        senderAtaOverride: senderAta,
        recipientAtaOverride: recipientAta,
      );
    } else {
      final pin = authorization.pin;
      if (pin == null) {
        throw ArgumentError('Signing authorization requires a PIN or keypair');
      }
      transaction = await _walletService.buildAndSignTransaction(
        pin: pin,
        amountUsdc: amountUsdc,
        recipientAddress: recipientAddress,
        blockhash: blockhash,
        feePayerAddress: feePayer,
        senderAtaOverride: senderAta,
        recipientAtaOverride: recipientAta,
      );
    }

    return SignedRailTransfer(
      provenance: prepared.provenance,
      idempotencyKey: prepared.idempotencyKey,
      envelope: RailEnvelope(
        type: 'solana_signed_transaction',
        version: 1,
        payload: {'encoding': 'base64', 'transaction': transaction},
      ),
    );
  }
}

/// Thin adapter over the released Solana API. It remains available as the
/// rollback path and preserves every legacy endpoint and DTO.
class LegacySolanaRailClient implements RailClient {
  final ApiClient _apiClient;

  LegacySolanaRailClient({required ApiClient apiClient})
    : _apiClient = apiClient;

  @override
  PaymentRail get rail => PaymentRail.solana;

  @override
  PaymentNetwork get network => PaymentNetwork.mainnet;

  RailProvenance get _provenance => const RailProvenance(
    apiVersion: '1',
    payloadVersion: 1,
    rail: PaymentRail.solana,
    network: PaymentNetwork.mainnet,
    asset: PaymentAsset.usdc,
  );

  @override
  Future<RailBalance> getBalance() async {
    final legacy = await _apiClient.getBalance();
    return RailBalance(
      provenance: _provenance,
      walletAddress: legacy.walletAddress,
      balances: [
        RailBalanceAmount(
          asset: PaymentAsset.native,
          amount: legacy.solBalance,
        ),
        RailBalanceAmount(asset: PaymentAsset.usdc, amount: legacy.usdcBalance),
      ],
      spendable: RailBalanceAmount(
        asset: PaymentAsset.usdc,
        amount: legacy.spendableBalance,
      ),
    );
  }

  @override
  Future<PreparedRailTransfer> prepareTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    required String idempotencyKey,
  }) async {
    final legacy = await _apiClient.prepareTransfer(
      recipientZendtag: recipientZendtag,
      amountUsdc: amountUsdc,
    );
    return PreparedRailTransfer(
      provenance: _provenance,
      state: 'prepared',
      idempotencyKey: idempotencyKey,
      envelope: RailEnvelope(
        type: 'solana_legacy_prepare',
        version: 1,
        payload: {
          'blockhash': legacy.blockhash,
          'recipient_wallet_address': legacy.recipientWalletAddress,
          'fee_payer': legacy.feePayer,
          'ata_created': legacy.ataCreated,
          'sender_ata': legacy.senderAta,
          'recipient_ata': legacy.recipientAta,
          'sender_pubkey': legacy.senderPubkey,
        },
      ),
    );
  }

  @override
  Future<RailSubmission> submitTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    required SignedRailTransfer signedTransfer,
    String? note,
  }) async {
    final transaction = _signedSolanaTransaction(signedTransfer);
    final legacy = await _apiClient.submitTransfer(
      recipientZendtag,
      amountUsdc,
      transaction,
      note,
    );
    return RailSubmission(
      provenance: _provenance,
      transferId: legacy.transferId,
      transactionId: legacy.transactionSignature,
      state: legacy.status,
      slot: legacy.slot,
    );
  }

  @override
  Future<RailHistory> getTransferHistory({String? cursor, int? limit}) async {
    final legacy = await _apiClient.getTransferHistory(
      cursor: cursor,
      limit: limit,
    );
    return RailHistory(
      provenance: _provenance,
      nextCursor: legacy.nextCursor,
      transfers: legacy.transfers
          .map(
            (entry) => RailHistoryEntry(
              transferId: entry.id,
              transactionId: entry.transactionSignature,
              state: entry.status,
              rail: rail,
              network: network,
              asset: PaymentAsset.usdc,
              senderZendtag: entry.senderZendtag,
              recipientZendtag: entry.recipientZendtag,
              amountUsdc: entry.amountUsdc,
              note: entry.note,
              createdAt: entry.createdAt,
              senderAvatarUrl: entry.senderAvatarUrl,
              recipientAvatarUrl: entry.recipientAvatarUrl,
              senderDisplayName: entry.senderDisplayName,
              recipientDisplayName: entry.recipientDisplayName,
              emailRecipientHint: entry.emailRecipientHint,
            ),
          )
          .toList(growable: false),
    );
  }
}

/// Additive chain-neutral API adapter for Solana/mainnet/USDC.
class SolanaV2RailClient implements RailClient {
  final ApiClient _apiClient;

  SolanaV2RailClient({required ApiClient apiClient}) : _apiClient = apiClient;

  @override
  PaymentRail get rail => PaymentRail.solana;

  @override
  PaymentNetwork get network => PaymentNetwork.mainnet;

  @override
  Future<RailBalance> getBalance() {
    return _apiClient.getP2pWalletBalance(rail: rail, network: network);
  }

  @override
  Future<PreparedRailTransfer> prepareTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    required String idempotencyKey,
  }) {
    return _apiClient.prepareP2pTransfer(
      rail: rail,
      network: network,
      recipientZendtag: recipientZendtag,
      amountUsdc: amountUsdc,
      asset: PaymentAsset.usdc,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<RailSubmission> submitTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    required SignedRailTransfer signedTransfer,
    String? note,
  }) {
    return _apiClient.submitP2pTransfer(
      rail: rail,
      network: network,
      recipientZendtag: recipientZendtag,
      amountUsdc: amountUsdc,
      note: note,
      asset: PaymentAsset.usdc,
      envelope: signedTransfer.envelope,
      idempotencyKey: signedTransfer.idempotencyKey,
    );
  }

  @override
  Future<RailHistory> getTransferHistory({String? cursor, int? limit}) {
    return _apiClient.getP2pTransferHistory(
      rail: rail,
      network: network,
      cursor: cursor,
      limit: limit,
    );
  }
}

/// Chooses v2 only after capability discovery confirms every operation needed
/// by the logical action. Send adapter selection is keyed by the caller's UUID,
/// making it sticky from prepare through every submit retry.
class CapabilityGatedSolanaRailClient implements RailClient {
  final ApiClient _apiClient;
  final LegacySolanaRailClient _legacy;
  final SolanaV2RailClient _v2;
  final Map<String, RailClient> _preparedClients = {};

  CapabilityGatedSolanaRailClient({required ApiClient apiClient})
    : _apiClient = apiClient,
      _legacy = LegacySolanaRailClient(apiClient: apiClient),
      _v2 = SolanaV2RailClient(apiClient: apiClient);

  @override
  PaymentRail get rail => PaymentRail.solana;

  @override
  PaymentNetwork get network => PaymentNetwork.mainnet;

  Future<bool> _supportsV2(Set<PaymentOperation> operations) async {
    try {
      final capabilities = await _apiClient.getP2pCapabilities();
      return capabilities.supports(
        rail: rail,
        network: network,
        asset: PaymentAsset.usdc,
        requiredOperations: operations,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<RailBalance> getBalance() async {
    final client = await _supportsV2({PaymentOperation.balance})
        ? _v2
        : _legacy;
    return client.getBalance();
  }

  @override
  Future<PreparedRailTransfer> prepareTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    required String idempotencyKey,
  }) async {
    final useV2 = await _supportsV2({
      PaymentOperation.prepare,
      PaymentOperation.submit,
    });
    final RailClient client = useV2 ? _v2 : _legacy;
    _preparedClients[idempotencyKey] = client;
    return client.prepareTransfer(
      recipientZendtag: recipientZendtag,
      amountUsdc: amountUsdc,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<RailSubmission> submitTransfer({
    required String recipientZendtag,
    required double amountUsdc,
    required SignedRailTransfer signedTransfer,
    String? note,
  }) async {
    final client = _preparedClients[signedTransfer.idempotencyKey];
    if (client == null) {
      throw StateError('No sticky adapter exists for this prepared transfer');
    }

    final result = await client.submitTransfer(
      recipientZendtag: recipientZendtag,
      amountUsdc: amountUsdc,
      signedTransfer: signedTransfer,
      note: note,
    );
    _preparedClients.remove(signedTransfer.idempotencyKey);
    return result;
  }

  @override
  Future<RailHistory> getTransferHistory({String? cursor, int? limit}) async {
    final client = await _supportsV2({PaymentOperation.history})
        ? _v2
        : _legacy;
    return client.getTransferHistory(cursor: cursor, limit: limit);
  }
}

/// Source-compatible name for callers that still explicitly request the old
/// thin client. New composition should use [CapabilityGatedSolanaRailClient].
@Deprecated('Use LegacySolanaRailClient or CapabilityGatedSolanaRailClient')
class SolanaRailClient extends LegacySolanaRailClient {
  SolanaRailClient({required super.apiClient});
}

String _signedSolanaTransaction(SignedRailTransfer signedTransfer) {
  final envelope = signedTransfer.envelope;
  if (envelope.type != 'solana_signed_transaction' ||
      envelope.version != 1 ||
      envelope.payload['encoding'] != 'base64') {
    throw StateError('Unsupported Solana signed transaction envelope');
  }
  return envelope.payload['transaction'] as String;
}

class PaymentRailBinding {
  final WalletIdentity identity;
  final TransactionSigner signer;
  final RailClient client;

  PaymentRailBinding({
    required this.identity,
    required this.signer,
    required this.client,
  }) {
    if (identity.rail != signer.rail || signer.rail != client.rail) {
      throw ArgumentError('Payment rail binding contains mixed rails');
    }
    if (identity.network != signer.network ||
        signer.network != client.network) {
      throw ArgumentError('Payment rail binding contains mixed networks');
    }
  }

  PaymentRail get rail => client.rail;
  PaymentNetwork get network => client.network;
}

/// Fail-closed rail resolver. An explicit unsupported rail never falls back to
/// Solana, preventing an address or signing request from crossing chains.
class PaymentRailRegistry {
  final Map<PaymentRail, PaymentRailBinding> _bindings;

  PaymentRailRegistry(Iterable<PaymentRailBinding> bindings)
    : _bindings = {for (final binding in bindings) binding.rail: binding};

  PaymentRailBinding resolve(PaymentRail rail) {
    final binding = _bindings[rail];
    if (binding == null) {
      throw UnsupportedPaymentRailException(rail);
    }
    return binding;
  }
}

class UnsupportedPaymentRailException implements Exception {
  final PaymentRail rail;
  final String code;

  const UnsupportedPaymentRailException(
    this.rail, {
    this.code = 'RAIL_NOT_SUPPORTED',
  });

  @override
  String toString() => '$code: ${rail.name}';
}
