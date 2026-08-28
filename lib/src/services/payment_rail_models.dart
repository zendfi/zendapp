enum PaymentRail { solana, sui }

/// Note that `_parseNetwork` below throws on an unrecognised value rather than
/// guessing, so every network the backend can report must be listed here. Sui
/// currently runs on testnet, which is why it is not mainnet-only.
enum PaymentNetwork { mainnet, testnet }

enum PaymentAsset { usdc, native }

enum PaymentOperation { balance, prepare, submit, status, history }

extension PaymentRailWireName on PaymentRail {
  String get wireName => name;
}

extension PaymentNetworkWireName on PaymentNetwork {
  String get wireName => name;
}

extension PaymentAssetWireName on PaymentAsset {
  String get wireName => name;
}

class RailEnvelope {
  final String type;
  final int version;
  final Map<String, dynamic> payload;

  RailEnvelope({
    required this.type,
    required this.version,
    required Map<String, dynamic> payload,
  }) : payload = Map<String, dynamic>.unmodifiable(payload);

  factory RailEnvelope.fromJson(Map<String, dynamic> json) {
    return RailEnvelope(
      type: json['type'] as String,
      version: (json['version'] as num).toInt(),
      payload: Map<String, dynamic>.from(
        json['payload'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'version': version,
    'payload': payload,
  };
}

class RailProvenance {
  final String apiVersion;
  final int payloadVersion;
  final PaymentRail rail;
  final PaymentNetwork network;
  final PaymentAsset? asset;

  const RailProvenance({
    required this.apiVersion,
    required this.payloadVersion,
    required this.rail,
    required this.network,
    this.asset,
  });

  factory RailProvenance.fromJson(Map<String, dynamic> json) {
    return RailProvenance(
      apiVersion: json['api_version'] as String,
      payloadVersion: (json['payload_version'] as num).toInt(),
      rail: _parseRail(json['rail'] as String),
      network: _parseNetwork(json['network'] as String),
      asset: _parseOptionalAsset(json['asset']),
    );
  }
}

class PreparedRailTransfer {
  final RailProvenance provenance;
  final String state;
  final RailEnvelope envelope;
  final String idempotencyKey;

  const PreparedRailTransfer({
    required this.provenance,
    required this.state,
    required this.envelope,
    required this.idempotencyKey,
  });

  factory PreparedRailTransfer.fromJson(
    Map<String, dynamic> json, {
    required String idempotencyKey,
  }) {
    return PreparedRailTransfer(
      provenance: RailProvenance.fromJson(json),
      state: json['state'] as String,
      envelope: RailEnvelope.fromJson(
        Map<String, dynamic>.from(json['envelope'] as Map<String, dynamic>),
      ),
      idempotencyKey: idempotencyKey,
    );
  }
}

class SignedRailTransfer {
  final RailProvenance provenance;
  final RailEnvelope envelope;
  final String idempotencyKey;

  const SignedRailTransfer({
    required this.provenance,
    required this.envelope,
    required this.idempotencyKey,
  });
}

class RailSubmission {
  final RailProvenance provenance;
  final String transferId;
  final String transactionId;
  final String state;
  final int? slot;

  const RailSubmission({
    required this.provenance,
    required this.transferId,
    required this.transactionId,
    required this.state,
    this.slot,
  });

  factory RailSubmission.fromJson(Map<String, dynamic> json) {
    return RailSubmission(
      provenance: RailProvenance.fromJson(json),
      transferId: json['transfer_id'] as String,
      transactionId: json['transaction_id'] as String,
      state: json['state'] as String,
    );
  }
}

class RailBalanceAmount {
  final PaymentAsset asset;
  final String amount;

  const RailBalanceAmount({required this.asset, required this.amount});

  factory RailBalanceAmount.fromJson(Map<String, dynamic> json) {
    return RailBalanceAmount(
      asset: _parseAsset(json['asset'] as String),
      amount: json['amount'] as String,
    );
  }
}

class RailBalance {
  final RailProvenance provenance;
  final String walletAddress;
  final List<RailBalanceAmount> balances;
  final RailBalanceAmount spendable;

  const RailBalance({
    required this.provenance,
    required this.walletAddress,
    required this.balances,
    required this.spendable,
  });

  factory RailBalance.fromJson(Map<String, dynamic> json) {
    final wallet = Map<String, dynamic>.from(
      json['wallet'] as Map<String, dynamic>,
    );
    return RailBalance(
      provenance: RailProvenance.fromJson(json),
      walletAddress: wallet['address'] as String,
      balances: (json['balances'] as List<dynamic>)
          .map(
            (entry) => RailBalanceAmount.fromJson(
              Map<String, dynamic>.from(entry as Map<String, dynamic>),
            ),
          )
          .toList(growable: false),
      spendable: RailBalanceAmount.fromJson(
        Map<String, dynamic>.from(json['spendable'] as Map<String, dynamic>),
      ),
    );
  }

  String amountFor(PaymentAsset asset, {String fallback = '0'}) {
    for (final balance in balances) {
      if (balance.asset == asset) return balance.amount;
    }
    return fallback;
  }
}

class RailHistoryEntry {
  final String transferId;
  final String transactionId;
  final String state;
  final PaymentRail rail;
  final PaymentNetwork network;
  final PaymentAsset asset;
  final String senderZendtag;
  final String recipientZendtag;
  final String amountUsdc;
  final String? note;
  final DateTime createdAt;
  final String? senderAvatarUrl;
  final String? recipientAvatarUrl;
  final String? senderDisplayName;
  final String? recipientDisplayName;
  final String? emailRecipientHint;

  const RailHistoryEntry({
    required this.transferId,
    required this.transactionId,
    required this.state,
    required this.rail,
    required this.network,
    required this.asset,
    required this.senderZendtag,
    required this.recipientZendtag,
    required this.amountUsdc,
    required this.createdAt,
    this.note,
    this.senderAvatarUrl,
    this.recipientAvatarUrl,
    this.senderDisplayName,
    this.recipientDisplayName,
    this.emailRecipientHint,
  });

  factory RailHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RailHistoryEntry(
      transferId: json['transfer_id'] as String,
      transactionId: json['transaction_id'] as String,
      state: json['state'] as String,
      rail: _parseRail(json['rail'] as String),
      network: _parseNetwork(json['network'] as String),
      asset: _parseAsset(json['asset'] as String),
      senderZendtag: json['sender_zendtag'] as String,
      recipientZendtag: json['recipient_zendtag'] as String,
      amountUsdc: json['amount_usdc'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      recipientAvatarUrl: json['recipient_avatar_url'] as String?,
      senderDisplayName: json['sender_display_name'] as String?,
      recipientDisplayName: json['recipient_display_name'] as String?,
      emailRecipientHint: json['email_recipient_hint'] as String?,
    );
  }
}

class RailHistory {
  final RailProvenance provenance;
  final List<RailHistoryEntry> transfers;
  final String? nextCursor;

  const RailHistory({
    required this.provenance,
    required this.transfers,
    this.nextCursor,
  });

  factory RailHistory.fromJson(Map<String, dynamic> json) {
    return RailHistory(
      provenance: RailProvenance.fromJson(json),
      transfers: (json['transfers'] as List<dynamic>)
          .map(
            (entry) => RailHistoryEntry.fromJson(
              Map<String, dynamic>.from(entry as Map<String, dynamic>),
            ),
          )
          .toList(growable: false),
      nextCursor: json['next_cursor'] as String?,
    );
  }
}

class RailTransferStatus {
  final RailProvenance provenance;
  final String transferId;
  final String transactionId;
  final String state;

  const RailTransferStatus({
    required this.provenance,
    required this.transferId,
    required this.transactionId,
    required this.state,
  });

  factory RailTransferStatus.fromJson(Map<String, dynamic> json) {
    return RailTransferStatus(
      provenance: RailProvenance.fromJson(json),
      transferId: json['transfer_id'] as String,
      transactionId: json['transaction_id'] as String,
      state: json['state'] as String,
    );
  }
}

class RailCapability {
  final PaymentRail rail;
  final bool enabled;
  final Set<PaymentNetwork> networks;
  final Set<PaymentAsset> assets;
  final Set<PaymentOperation> operations;

  const RailCapability({
    required this.rail,
    required this.enabled,
    required this.networks,
    required this.assets,
    required this.operations,
  });

  factory RailCapability.fromJson(Map<String, dynamic> json) {
    return RailCapability(
      rail: _parseRail(json['rail'] as String),
      enabled: json['enabled'] as bool? ?? false,
      networks: (json['networks'] as List<dynamic>? ?? const [])
          .map((value) => _parseNetwork(value as String))
          .toSet(),
      assets: (json['assets'] as List<dynamic>? ?? const [])
          .map((value) => _parseAsset(value as String))
          .toSet(),
      operations: (json['operations'] as List<dynamic>? ?? const [])
          .map((value) => _parseOperation(value as String))
          .toSet(),
    );
  }

  bool supports({
    required PaymentNetwork network,
    required PaymentAsset asset,
    required Set<PaymentOperation> requiredOperations,
  }) {
    return enabled &&
        networks.contains(network) &&
        assets.contains(asset) &&
        operations.containsAll(requiredOperations);
  }
}

class P2pCapabilities {
  final RailProvenance provenance;
  final bool enabled;
  final List<RailCapability> rails;

  const P2pCapabilities({
    required this.provenance,
    required this.enabled,
    required this.rails,
  });

  factory P2pCapabilities.fromJson(Map<String, dynamic> json) {
    return P2pCapabilities(
      provenance: RailProvenance.fromJson(json),
      enabled: json['enabled'] as bool? ?? false,
      rails: (json['rails'] as List<dynamic>? ?? const [])
          .map(
            (entry) => RailCapability.fromJson(
              Map<String, dynamic>.from(entry as Map<String, dynamic>),
            ),
          )
          .toList(growable: false),
    );
  }

  bool supports({
    required PaymentRail rail,
    required PaymentNetwork network,
    required PaymentAsset asset,
    required Set<PaymentOperation> requiredOperations,
  }) {
    if (!enabled) return false;
    for (final capability in rails) {
      if (capability.rail == rail &&
          capability.supports(
            network: network,
            asset: asset,
            requiredOperations: requiredOperations,
          )) {
        return true;
      }
    }
    return false;
  }
}

PaymentRail _parseRail(String value) {
  return PaymentRail.values.firstWhere(
    (candidate) => candidate.name == value.toLowerCase(),
  );
}

PaymentNetwork _parseNetwork(String value) {
  return PaymentNetwork.values.firstWhere(
    (candidate) => candidate.name == value.toLowerCase(),
  );
}

PaymentAsset _parseAsset(String value) {
  return PaymentAsset.values.firstWhere(
    (candidate) => candidate.name == value.toLowerCase(),
  );
}

PaymentAsset? _parseOptionalAsset(dynamic value) {
  return value is String ? _parseAsset(value) : null;
}

PaymentOperation _parseOperation(String value) {
  return PaymentOperation.values.firstWhere(
    (candidate) => candidate.name == value.toLowerCase(),
  );
}
