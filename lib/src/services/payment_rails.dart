import 'dart:typed_data';

import 'api_client.dart';
import 'payment_rail_models.dart';
import 'sui_zklogin_service.dart';
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

  /// For rails that hold no local secret to unlock.
  ///
  /// A zkLogin account's signing authority is an in-memory ephemeral key plus a
  /// zero-knowledge proof, so there is no PIN and no stored keypair. Passing a
  /// PIN here would be theatre: it would gate a secret that does not exist.
  const SigningAuthorization.none() : pin = null, keypairBytes = null;

  /// True when this carries a local secret, i.e. the rail signs with a stored key.
  bool get hasLocalSecret => pin != null || keypairBytes != null;
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

  /// Non-throwing lookup, for callers choosing between rails rather than
  /// asserting one. Still never substitutes a different rail.
  PaymentRailBinding? maybeResolve(PaymentRail rail) => _bindings[rail];
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

// ---------------------------------------------------------------------------
// Sui rail
//
// Additive: nothing above changes. The Sui rail satisfies the same three
// interfaces as Solana, so shared send orchestration never learns which chain it
// is driving — which is what keeps chain detail out of the UI entirely.
// ---------------------------------------------------------------------------

/// Public Sui identity, derived from the user's zkLogin account.
///
/// The address is not stored on the device: it is owned by the backend identity
/// record, because it is derived from the OAuth subject, the client id and the
/// user salt. Cached per instance so repeat reads during a send do not re-fetch.
class SuiWalletIdentity implements WalletIdentity {
  final ApiClient _apiClient;
  final PaymentNetwork _network;
  String? _cachedAddress;

  SuiWalletIdentity({
    required ApiClient apiClient,
    PaymentNetwork network = PaymentNetwork.testnet,
  }) : _apiClient = apiClient,
       _network = network;

  @override
  PaymentRail get rail => PaymentRail.sui;

  @override
  PaymentNetwork get network => _network;

  @override
  Future<String?> getAddress() async {
    final cached = _cachedAddress;
    if (cached != null) return cached;
    final identity = await _apiClient.getSuiZkLoginIdentity();
    if (!identity.linked) return null;
    return _cachedAddress = identity.suiAddress;
  }

  /// Drops the cached address, for use after sign-out or an identity change.
  void invalidate() => _cachedAddress = null;
}

/// The only component allowed to parse Sui preparation fields.
///
/// Unlike Solana, [SigningAuthorization] is unused here and that is deliberate:
/// a zkLogin account has no local private key and no PIN. Authority comes from
/// the in-memory ephemeral key plus the zero-knowledge proof held by
/// [SuiZkLoginService], so there is no secret for a PIN to unlock. Callers that
/// gate on a PIN must skip that gate for this rail rather than prompt for
/// something that protects nothing.
class SuiTransactionSigner implements TransactionSigner {
  final SuiZkLoginService _zkLogin;
  final PaymentNetwork _network;

  SuiTransactionSigner({
    required SuiZkLoginService zkLoginService,
    PaymentNetwork network = PaymentNetwork.testnet,
  }) : _zkLogin = zkLoginService,
       _network = network;

  @override
  PaymentRail get rail => PaymentRail.sui;

  @override
  PaymentNetwork get network => _network;

  @override
  Future<SignedRailTransfer> signPreparedTransfer({
    required PreparedRailTransfer prepared,
    required double amountUsdc,
    required SigningAuthorization authorization,
  }) async {
    if (prepared.provenance.rail != rail ||
        prepared.provenance.network != network ||
        prepared.provenance.asset != PaymentAsset.usdc ||
        prepared.envelope.type != 'sui_gasless_transfer_prepare' ||
        prepared.envelope.version != 1) {
      throw StateError('Unsupported Sui preparation envelope');
    }

    final transactionDataBcs =
        prepared.envelope.payload['transaction_data_bcs'] as String?;
    if (transactionDataBcs == null || transactionDataBcs.isEmpty) {
      throw StateError('Sui preparation envelope carries no transaction bytes');
    }

    // Signs blake2b256(intent || bcs) with the ephemeral key, then has the
    // backend wrap that signature and the proof into a zkLogin authenticator.
    final signature = await _zkLogin.signPreparedTransaction(
      transactionDataBcsBase64: transactionDataBcs,
    );

    return SignedRailTransfer(
      provenance: prepared.provenance,
      envelope: RailEnvelope(
        type: 'sui_signed_transaction',
        version: 1,
        // `kind` and `version` are repeated *inside* the payload on purpose. The
        // outer pair satisfies the shared envelope check, while the Sui rail
        // deserializes this payload on its own and requires a `kind` of its own —
        // omitting it fails submission with INVALID_SIGNED_PAYLOAD.
        payload: {
          'kind': 'sui_signed_transaction',
          'version': 1,
          'transaction_data_bcs': transactionDataBcs,
          'signatures': [signature],
        },
      ),
      idempotencyKey: prepared.idempotencyKey,
    );
  }
}

/// Chain-neutral API adapter for Sui USDC.
///
/// Sui has no legacy endpoint to fall back to — it exists only behind the v2 P2P
/// API — so unlike Solana there is no capability-gated dual path here. Whether
/// Sui may be used at all is decided by the backend's own rail policy, which the
/// caller consults through `/capabilities`.
class SuiV2RailClient implements RailClient {
  final ApiClient _apiClient;
  final PaymentNetwork _network;

  SuiV2RailClient({
    required ApiClient apiClient,
    PaymentNetwork network = PaymentNetwork.testnet,
  }) : _apiClient = apiClient,
       _network = network;

  @override
  PaymentRail get rail => PaymentRail.sui;

  @override
  PaymentNetwork get network => _network;

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

/// Picks the rail for an operation from the backend's advertised capabilities.
///
/// Rail choice is never hardcoded in the UI or in a screen. The backend already
/// owns the policy — which rails are enabled, on which networks, and for which
/// users — so the client's job is only to ask and then honour the answer. That is
/// what keeps chain selection invisible to the user.
///
/// Sui is preferred when it is available for the requested operations, because a
/// zkLogin account has no Solana wallet at all; Solana remains the answer for
/// accounts that predate zkLogin and whenever Sui is not offered. Preference is
/// only ever expressed between rails the backend has already approved.
class RailRouter {
  final ApiClient _apiClient;
  final PaymentRailRegistry _registry;
  final Duration _cacheTtl;

  P2pCapabilities? _cached;
  DateTime? _cachedAt;

  RailRouter({
    required ApiClient apiClient,
    required PaymentRailRegistry registry,
    Duration cacheTtl = const Duration(minutes: 5),
  }) : _apiClient = apiClient,
       _registry = registry,
       _cacheTtl = cacheTtl;

  /// Order of preference. Anything not advertised is skipped.
  static const _preference = [PaymentRail.sui, PaymentRail.solana];

  Future<P2pCapabilities?> _capabilities() async {
    final cached = _cached;
    final at = _cachedAt;
    if (cached != null && at != null && DateTime.now().difference(at) < _cacheTtl) {
      return cached;
    }
    try {
      final fresh = await _apiClient.getP2pCapabilities();
      _cached = fresh;
      _cachedAt = DateTime.now();
      return fresh;
    } catch (_) {
      // Unreachable capabilities must not strand the user: fall back to the
      // last known answer if we have one, otherwise let the caller default.
      return cached;
    }
  }

  /// Whether [rail] can only be signed for with a locally held private key.
  ///
  /// Solana signing needs a keypair on the device. Sui signing under zkLogin needs
  /// an ephemeral key plus a proof, which a Google sign-in produces on demand — so
  /// a zkLogin account can use Sui but has nothing to sign a Solana transfer with.
  static bool _requiresLocalKey(PaymentRail rail) => rail == PaymentRail.solana;

  /// Whether falling back to a rail that signs with a local key is meaningful.
  ///
  /// Set false for a zkLogin account. Such an account has no Solana wallet, so
  /// falling back to Solana does not degrade gracefully — it fails with
  /// `WALLET_NOT_REGISTERED`, telling the user to "store a wallet backup", which
  /// is a concept their account does not have and names the wrong cause. With
  /// this false the router reports why its own rail is unavailable instead.
  bool allowLocalKeyRailFallback = true;

  /// Resolves the binding to use for [operations].
  ///
  /// Falls back to [fallback] when capabilities cannot be read, so a network blip
  /// degrades to the previous behaviour rather than blocking a transfer — but only
  /// when that fallback is usable by this account.
  Future<PaymentRailBinding> resolve({
    required Set<PaymentOperation> operations,
    PaymentRail fallback = PaymentRail.solana,
  }) async {
    final capabilities = await _capabilities();
    if (capabilities != null) {
      for (final rail in _preference) {
        // Skip rails this account cannot sign for, *inside the preference loop*
        // and not only in the fallback below.
        //
        // The backend advertises Solana as enabled to everyone, because it is
        // enabled — as infrastructure. It has no way to know this particular
        // account holds no Solana keypair. So whenever Sui is unavailable for this
        // account (wrong network, no cohort), the loop would find Solana
        // "supported", return it, and never reach the allowLocalKeyRailFallback
        // guard at all. The guard only ever covered the capabilities-unreadable
        // path, which made it look effective while silently doing nothing in the
        // case it was written for.
        if (!allowLocalKeyRailFallback && _requiresLocalKey(rail)) continue;

        final binding = _registry.maybeResolve(rail);
        if (binding == null) continue;
        if (capabilities.supports(
          rail: rail,
          network: binding.network,
          asset: PaymentAsset.usdc,
          requiredOperations: operations,
        )) {
          return binding;
        }
      }
    }

    if (!allowLocalKeyRailFallback) {
      // Report the reason the account's own rail is unavailable rather than
      // failing later on a rail it can never use.
      throw RailUnavailableException(
        capabilities?.unavailableReasonFor(PaymentRail.sui),
      );
    }
    return _registry.resolve(fallback);
  }

  /// Drops cached capabilities, for use after sign-in changes which account (and
  /// therefore which rail policy) applies.
  void invalidate() {
    _cached = null;
    _cachedAt = null;
  }
}

/// Thrown when no rail this account can actually use is currently available.
///
/// Carries the backend's reason code so the message names the real cause. The
/// alternative — letting the request proceed on a rail the account has no wallet
/// for — surfaces as `WALLET_NOT_REGISTERED` and tells the user to store a wallet
/// backup, which is both wrong and unactionable for a Google sign-in.
class RailUnavailableException implements Exception {
  const RailUnavailableException(this.reasonCode);

  /// `SUI_COHORT_REQUIRED`, `RAIL_NOT_SUPPORTED`, or null when capabilities could
  /// not be read at all.
  final String? reasonCode;

  /// User-facing copy. Deliberately avoids naming a blockchain: which chain moves
  /// the money is not something the user chose or needs to know.
  String get userMessage => switch (reasonCode) {
    'SUI_COHORT_REQUIRED' =>
      'Your account isn’t switched on for transfers yet. '
          'Hang tight — we’re rolling this out gradually.',
    'RAIL_NOT_SUPPORTED' =>
      'Transfers are temporarily unavailable. Please try again later.',
    _ =>
      'We couldn’t reach the transfer service. '
          'Check your connection and try again.',
  };

  @override
  String toString() => 'RailUnavailableException($reasonCode)';
}
