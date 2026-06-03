class OtpResponse {
  final String sessionId;
  final DateTime expiresAt;

  OtpResponse({required this.sessionId, required this.expiresAt});

  factory OtpResponse.fromJson(Map<String, dynamic> json) {
    return OtpResponse(
      sessionId: json['session_id'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'expires_at': expiresAt.toIso8601String(),
    };
  }
}

class OtpVerifyResponse {
  final String verificationToken;
  final String phoneNumber;
  final bool userExists;

  /// When the verified email matches a Zend! consumer waitlist entry,
  /// the backend echoes the reserved zendtag (if any) and full name
  /// (if any) so the onboarding flow can greet the visitor and
  /// prefill the username/name screens.
  final bool waitlistMatch;
  final String? reservedZendtag;
  final String? waitlistFullName;

  OtpVerifyResponse({
    required this.verificationToken,
    required this.phoneNumber,
    required this.userExists,
    this.waitlistMatch = false,
    this.reservedZendtag,
    this.waitlistFullName,
  });

  factory OtpVerifyResponse.fromJson(Map<String, dynamic> json) {
    return OtpVerifyResponse(
      verificationToken: json['verification_token'] as String,
      phoneNumber: json['phone_number'] as String,
      userExists: json['user_exists'] as bool,
      waitlistMatch: (json['waitlist_match'] as bool?) ?? false,
      reservedZendtag: json['reserved_zendtag'] as String?,
      waitlistFullName: json['waitlist_full_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'verification_token': verificationToken,
      'phone_number': phoneNumber,
      'user_exists': userExists,
      'waitlist_match': waitlistMatch,
      if (reservedZendtag != null) 'reserved_zendtag': reservedZendtag,
      if (waitlistFullName != null) 'waitlist_full_name': waitlistFullName,
    };
  }
}

class AuthResponse {
  final String userId;
  final String zendtag;
  final String sessionToken;
  final int expiresAt;

  AuthResponse({
    required this.userId,
    required this.zendtag,
    required this.sessionToken,
    required this.expiresAt,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      userId: json['user_id'] as String,
      zendtag: json['zendtag'] as String,
      sessionToken: json['session_token'] as String,
      expiresAt: json['expires_at'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'zendtag': zendtag,
      'session_token': sessionToken,
      'expires_at': expiresAt,
    };
  }
}

class RegisterResponse {
  final String userId;
  final String zendtag;
  final String sessionToken;
  final int expiresAt;

  RegisterResponse({
    required this.userId,
    required this.zendtag,
    required this.sessionToken,
    required this.expiresAt,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) {
    return RegisterResponse(
      userId: json['user_id'] as String,
      zendtag: json['zendtag'] as String,
      sessionToken: json['session_token'] as String,
      expiresAt: json['expires_at'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'zendtag': zendtag,
      'session_token': sessionToken,
      'expires_at': expiresAt,
    };
  }
}

class ZendtagCheckResponse {
  final String zendtag;
  final bool available;

  ZendtagCheckResponse({required this.zendtag, required this.available});

  factory ZendtagCheckResponse.fromJson(Map<String, dynamic> json) {
    return ZendtagCheckResponse(
      zendtag: json['zendtag'] as String,
      available: json['available'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'zendtag': zendtag,
      'available': available,
    };
  }
}

class ZendtagResolveResponse {
  final String zendtag;
  final String displayName;
  final String walletAddress;
  final String accountType;
  final String? avatarUrl;

  ZendtagResolveResponse({
    required this.zendtag,
    required this.displayName,
    required this.walletAddress,
    required this.accountType,
    this.avatarUrl,
  });

  factory ZendtagResolveResponse.fromJson(Map<String, dynamic> json) {
    return ZendtagResolveResponse(
      zendtag: json['zendtag'] as String,
      displayName: json['display_name'] as String,
      walletAddress: json['wallet_address'] as String,
      accountType: json['account_type'] as String,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'zendtag': zendtag,
      'display_name': displayName,
      'wallet_address': walletAddress,
      'account_type': accountType,
      'avatar_url': avatarUrl,
    };
  }
}

class BackupResponse {
  final String keyId;
  final String publicKey;

  BackupResponse({required this.keyId, required this.publicKey});

  factory BackupResponse.fromJson(Map<String, dynamic> json) {
    return BackupResponse(
      keyId: json['key_id'] as String,
      publicKey: json['public_key'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key_id': keyId,
      'public_key': publicKey,
    };
  }
}

class RetrieveBackupResponse {
  final String encryptedKeypair;
  final String nonce;
  final String publicKey;

  RetrieveBackupResponse({
    required this.encryptedKeypair,
    required this.nonce,
    required this.publicKey,
  });

  factory RetrieveBackupResponse.fromJson(Map<String, dynamic> json) {
    return RetrieveBackupResponse(
      encryptedKeypair: json['encrypted_keypair'] as String,
      nonce: json['nonce'] as String,
      publicKey: json['public_key'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'encrypted_keypair': encryptedKeypair,
      'nonce': nonce,
      'public_key': publicKey,
    };
  }
}

class BalanceResponse {
  final String walletAddress;
  final String solBalance;
  final String usdcBalance;
  /// Spendable balance = on-chain USDC minus the sum of pending email intent amounts.
  /// Falls back to [usdcBalance] if the backend doesn't include the field (older API).
  final String spendableBalance;

  BalanceResponse({
    required this.walletAddress,
    required this.solBalance,
    required this.usdcBalance,
    String? spendableBalance,
  }) : spendableBalance = spendableBalance ?? usdcBalance;

  factory BalanceResponse.fromJson(Map<String, dynamic> json) {
    final usdc = json['usdc_balance'] as String;
    return BalanceResponse(
      walletAddress: json['wallet_address'] as String,
      solBalance: json['sol_balance'] as String,
      usdcBalance: usdc,
      spendableBalance: json['spendable_balance'] as String? ?? usdc,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'wallet_address': walletAddress,
      'sol_balance': solBalance,
      'usdc_balance': usdcBalance,
      'spendable_balance': spendableBalance,
    };
  }
}

class TransferResponse {
  final String transferId;
  final String transactionSignature;
  final int slot;
  final String status;

  TransferResponse({
    required this.transferId,
    required this.transactionSignature,
    required this.slot,
    required this.status,
  });

  factory TransferResponse.fromJson(Map<String, dynamic> json) {
    return TransferResponse(
      transferId: json['transfer_id'] as String,
      transactionSignature: json['transaction_signature'] as String,
      slot: json['slot'] as int,
      status: json['status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transfer_id': transferId,
      'transaction_signature': transactionSignature,
      'slot': slot,
      'status': status,
    };
  }
}

class TransferHistoryEntry {
  final String id;
  final String senderZendtag;
  final String recipientZendtag;
  final String amountUsdc;
  final String transactionSignature;
  final String? note;
  final String status;
  final DateTime createdAt;
  final String? senderAvatarUrl;
  final String? recipientAvatarUrl;
  final String? senderDisplayName;
  final String? recipientDisplayName;
  /// For email-intent claim transfers: the masked original recipient email
  /// (e.g. "te***@gmail.com"). When non-null, use this for display instead of
  /// [recipientZendtag] on the sender's activity feed.
  final String? emailRecipientHint;

  TransferHistoryEntry({
    required this.id,
    required this.senderZendtag,
    required this.recipientZendtag,
    required this.amountUsdc,
    required this.transactionSignature,
    this.note,
    required this.status,
    required this.createdAt,
    this.senderAvatarUrl,
    this.recipientAvatarUrl,
    this.senderDisplayName,
    this.recipientDisplayName,
    this.emailRecipientHint,
  });

  factory TransferHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TransferHistoryEntry(
      id: json['id'] as String,
      senderZendtag: json['sender_zendtag'] as String,
      recipientZendtag: json['recipient_zendtag'] as String,
      amountUsdc: json['amount_usdc'] as String,
      transactionSignature: json['transaction_signature'] as String,
      note: json['note'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      recipientAvatarUrl: json['recipient_avatar_url'] as String?,
      senderDisplayName: json['sender_display_name'] as String?,
      recipientDisplayName: json['recipient_display_name'] as String?,
      emailRecipientHint: json['email_recipient_hint'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_zendtag': senderZendtag,
      'recipient_zendtag': recipientZendtag,
      'amount_usdc': amountUsdc,
      'transaction_signature': transactionSignature,
      'note': note,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'sender_avatar_url': senderAvatarUrl,
      'recipient_avatar_url': recipientAvatarUrl,
      'sender_display_name': senderDisplayName,
      'recipient_display_name': recipientDisplayName,
      if (emailRecipientHint != null) 'email_recipient_hint': emailRecipientHint,
    };
  }
}

class TransferHistoryResponse {
  final List<TransferHistoryEntry> transfers;
  final String? nextCursor;

  TransferHistoryResponse({required this.transfers, this.nextCursor});

  factory TransferHistoryResponse.fromJson(Map<String, dynamic> json) {
    return TransferHistoryResponse(
      transfers: (json['transfers'] as List<dynamic>)
          .map((e) => TransferHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transfers': transfers.map((e) => e.toJson()).toList(),
      'next_cursor': nextCursor,
    };
  }
}

class FxPreviewResponse {
  final double amountUsd;
  final double amountNgn;
  final double rate;
  final DateTime rateUpdatedAt;

  FxPreviewResponse({
    required this.amountUsd,
    required this.amountNgn,
    required this.rate,
    required this.rateUpdatedAt,
  });

  factory FxPreviewResponse.fromJson(Map<String, dynamic> json) {
    return FxPreviewResponse(
      amountUsd: (json['amount_usd'] as num).toDouble(),
      amountNgn: (json['amount_ngn'] as num).toDouble(),
      rate: (json['rate'] as num).toDouble(),
      rateUpdatedAt: DateTime.parse(json['rate_updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount_usd': amountUsd,
      'amount_ngn': amountNgn,
      'rate': rate,
      'rate_updated_at': rateUpdatedAt.toIso8601String(),
    };
  }
}

/// Response from POST /api/zend/transfer/prepare
class PrepareTransferResponse {
  final String blockhash;
  final String recipientWalletAddress;
  final String feePayer;
  final bool ataCreated;

  PrepareTransferResponse({
    required this.blockhash,
    required this.recipientWalletAddress,
    required this.feePayer,
    required this.ataCreated,
  });

  factory PrepareTransferResponse.fromJson(Map<String, dynamic> json) {
    return PrepareTransferResponse(
      blockhash: json['blockhash'] as String,
      recipientWalletAddress: json['recipient_wallet_address'] as String,
      feePayer: json['fee_payer'] as String,
      ataCreated: json['ata_created'] as bool,
    );
  }
}

class UserProfileResponse {
  final String userId;
  final String zendtag;
  final String displayName;
  final String? walletAddress;
  final String? avatarUrl;

  UserProfileResponse({
    required this.userId,
    required this.zendtag,
    required this.displayName,
    this.walletAddress,
    this.avatarUrl,
  });

  factory UserProfileResponse.fromJson(Map<String, dynamic> json) {
    return UserProfileResponse(
      userId: json['user_id'] as String,
      zendtag: json['zendtag'] as String,
      displayName: json['display_name'] as String,
      walletAddress: json['wallet_address'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'zendtag': zendtag,
      'display_name': displayName,
      'wallet_address': walletAddress,
      'avatar_url': avatarUrl,
    };
  }
}

/// Details of a public payment request link, returned by
/// `GET /api/v1/public/zend/{zendtag}/{requestLinkId}`.
///
/// A 200 response always means the request is payable (pending and not expired).
/// The backend returns 404 for non-pending or expired requests.
class RequestLinkDetails {
  final double amountUsdc;
  final String? description;
  final DateTime? expiresAt;

  const RequestLinkDetails({
    required this.amountUsdc,
    this.description,
    this.expiresAt,
  });

  factory RequestLinkDetails.fromJson(Map<String, dynamic> json) {
    // The backend wraps request data under a 'request' key.
    // Fall back to top-level for any legacy callers.
    final requestData = json['request'] as Map<String, dynamic>? ?? json;

    final rawAmount = requestData['amount_usdc'];
    final double amount;
    if (rawAmount is num) {
      amount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      amount = double.tryParse(rawAmount) ?? 0.0;
    } else {
      amount = 0.0;
    }

    final expiresAtStr = requestData['expires_at'] as String?;

    return RequestLinkDetails(
      amountUsdc: amount,
      description: requestData['description'] as String?,
      expiresAt: expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null,
    );
  }
}
