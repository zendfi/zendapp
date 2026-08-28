/// Typed models for the additive Sui zkLogin identity API.
///
/// Nothing here holds a secret. The ephemeral private key, `jwtRandomness`, and
/// the raw ID token stay in [SuiZkLoginSession] / secure storage and are
/// deliberately excluded from anything that could be logged or serialized to a
/// log sink.
library;

/// Response from `POST /api/zend/v1/sui/zklogin/sessions`.
///
/// The backend derives both `nonce` and `maxEpoch`, so the client cannot widen
/// its own signing window.
class SuiZkLoginSessionInit {
  const SuiZkLoginSessionInit({
    required this.sessionId,
    required this.network,
    required this.nonce,
    required this.maxEpoch,
    required this.expiresAt,
  });

  final String sessionId;
  final String network;

  /// Place this in the OAuth request. It commits to the ephemeral key, the
  /// max epoch, and the randomness.
  final String nonce;
  final int maxEpoch;
  final DateTime expiresAt;

  factory SuiZkLoginSessionInit.fromJson(Map<String, dynamic> json) {
    return SuiZkLoginSessionInit(
      sessionId: json['session_id'] as String,
      network: json['network'] as String,
      nonce: json['nonce'] as String,
      maxEpoch: (json['max_epoch'] as num).toInt(),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

/// A linked Sui identity. The address is public; there is no secret here.
class SuiZkLoginIdentity {
  const SuiZkLoginIdentity({
    required this.linked,
    this.identityId,
    this.network,
    this.suiAddress,
    this.addressSource,
    this.saltBackedUp = false,
  });

  final bool linked;
  final String? identityId;
  final String? network;
  final String? suiAddress;
  final String? addressSource;
  final bool saltBackedUp;

  factory SuiZkLoginIdentity.fromJson(Map<String, dynamic> json) {
    return SuiZkLoginIdentity(
      linked: json['linked'] as bool? ?? false,
      identityId: json['identity_id'] as String?,
      network: json['network'] as String?,
      suiAddress: json['sui_address'] as String?,
      addressSource: json['address_source'] as String?,
      saltBackedUp: json['salt_backed_up'] as bool? ?? false,
    );
  }
}

/// A zero-knowledge proof, cached for the lifetime of a session.
///
/// Reusable for any number of transactions until the network epoch passes
/// `maxEpoch`, so it is fetched once per session rather than per transfer.
class SuiZkLoginProof {
  const SuiZkLoginProof({required this.payload});

  final Map<String, dynamic> payload;

  factory SuiZkLoginProof.fromJson(Map<String, dynamic> json) {
    final proof = json['proof'];
    return SuiZkLoginProof(
      payload: proof is Map<String, dynamic>
          ? proof
          : Map<String, dynamic>.from(proof as Map),
    );
  }

  /// Never include the proof body in logs: combined with the ephemeral private
  /// key it authorizes transactions.
  @override
  String toString() => 'SuiZkLoginProof(<redacted>)';
}

/// Thrown when a zkLogin session can no longer be used and the user must
/// re-authenticate. Callers should restart the sign-in flow rather than retry.
class SuiZkLoginSessionExpired implements Exception {
  const SuiZkLoginSessionExpired([this.message = 'zkLogin session expired']);
  final String message;

  @override
  String toString() => 'SuiZkLoginSessionExpired: $message';
}

/// Thrown when the backend rejects the identity for a reason the user must act
/// on, for example the Google account already being linked elsewhere.
class SuiZkLoginIdentityConflict implements Exception {
  const SuiZkLoginIdentityConflict(this.message);
  final String message;

  @override
  String toString() => 'SuiZkLoginIdentityConflict: $message';
}

/// Response from `POST /api/zend/v1/sui/zklogin/public/signin`.
///
/// This is the whole onboarding result: a Zend session token equivalent to the
/// one OTP sign-in returns, plus the Sui identity that was established in the
/// same call. There is no separate register step.
class SuiZkLoginPublicSignIn {
  const SuiZkLoginPublicSignIn({
    required this.sessionToken,
    required this.expiresAt,
    required this.userId,
    required this.displayName,
    required this.zendtag,
    required this.zendtagIsPlaceholder,
    required this.zendtagPromptSuppressed,
    required this.outcome,
    required this.identity,
  });

  /// Bearer token for every subsequent authenticated call.
  final String sessionToken;

  /// Unix seconds at which [sessionToken] expires.
  final int expiresAt;
  final String userId;

  /// The user's name from their Google profile. Prefer this over [zendtag] in
  /// greetings — showing a placeholder handle would echo their own email at them.
  final String displayName;

  /// The user's handle. When [zendtagIsPlaceholder] is true this is their email
  /// address standing in for a chosen zendtag.
  final String zendtag;

  /// True when the handle was auto-assigned. Such handles are excluded from
  /// public discovery, so the user should be offered a real one eventually —
  /// but never on the critical path, which is the point of the placeholder.
  final bool zendtagIsPlaceholder;

  /// True when the user has already declined to pick a handle. Never prompt again.
  final bool zendtagPromptSuppressed;

  /// `created` for a brand-new account, `signed_in` for a returning one. Lets the
  /// UI welcome a new user without a separate "is this a signup?" round-trip.
  final String outcome;
  final SuiZkLoginIdentity identity;

  bool get isNewAccount => outcome == 'created';

  /// Whether to offer the optional zendtag picker after sign-in.
  ///
  /// Never blocks the flow: the account is already usable, and the email works as
  /// a handle indefinitely if the user declines.
  bool get shouldOfferZendtag =>
      zendtagIsPlaceholder && !zendtagPromptSuppressed;

  factory SuiZkLoginPublicSignIn.fromJson(Map<String, dynamic> json) {
    final identity = json['identity'];
    return SuiZkLoginPublicSignIn(
      sessionToken: json['session_token'] as String,
      expiresAt: (json['expires_at'] as num).toInt(),
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String? ?? '',
      zendtag: json['zendtag'] as String,
      zendtagIsPlaceholder: json['zendtag_is_placeholder'] as bool? ?? false,
      zendtagPromptSuppressed:
          json['zendtag_prompt_suppressed'] as bool? ?? false,
      outcome: json['outcome'] as String? ?? 'signed_in',
      identity: identity is Map
          ? SuiZkLoginIdentity(
              linked: true,
              identityId: identity['identity_id'] as String?,
              network: identity['network'] as String?,
              suiAddress: identity['sui_address'] as String?,
              addressSource: identity['address_source'] as String?,
              saltBackedUp: identity['salt_backed_up'] as bool? ?? false,
            )
          : const SuiZkLoginIdentity(linked: false),
    );
  }

  /// Never log this object: [sessionToken] is a live bearer credential.
  @override
  String toString() => 'SuiZkLoginPublicSignIn(outcome: $outcome, <redacted>)';
}
