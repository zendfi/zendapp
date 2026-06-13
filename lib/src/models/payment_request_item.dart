/// Represents a payment request in the activity feed.
/// Used for both inbound (sent *to* the current user) and outbound
/// (sent *by* the current user to another Zend user).
class PaymentRequestItem {
  const PaymentRequestItem({
    required this.id,
    required this.requestLinkId,
    required this.linkUrl,
    required this.amountUsdc,
    required this.status,
    required this.createdAt,
    required this.isInbound,
    this.description,
    this.expiresAt,
    // Outbound: who was requested
    this.recipientZendtag,
    this.recipientEmail,
    // Inbound: who is requesting
    this.requesterZendtag,
    this.requesterDisplayName,
  });

  final String id;
  final String requestLinkId;
  final String linkUrl;
  final double amountUsdc;
  final String status;
  final DateTime createdAt;

  /// `true`  → this request was sent *to* the current user (they owe someone)
  /// `false` → this request was sent *by* the current user (someone owes them)
  final bool isInbound;

  final String? description;
  final DateTime? expiresAt;

  // Outbound fields
  final String? recipientZendtag;
  final String? recipientEmail;

  // Inbound fields
  final String? requesterZendtag;
  final String? requesterDisplayName;

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';

  /// Human-readable counterparty label shown in the activity tile.
  String get counterpartyLabel {
    if (isInbound) {
      return requesterZendtag != null ? '@$requesterZendtag' : 'Someone';
    }
    if (recipientZendtag != null) return '@$recipientZendtag';
    if (recipientEmail != null) return recipientEmail!;
    return 'Link';
  }

  /// Avatar initials for the activity tile.
  String get avatarInitial {
    final label = isInbound ? (requesterZendtag ?? '') : (recipientZendtag ?? recipientEmail ?? '');
    return label.isNotEmpty ? label[0].toUpperCase() : '?';
  }

  String get formattedAmount {
    if (amountUsdc == amountUsdc.roundToDouble()) {
      return '\$${amountUsdc.toStringAsFixed(0)}';
    }
    return '\$${amountUsdc.toStringAsFixed(2)}';
  }

  factory PaymentRequestItem.fromOutboundJson(Map<String, dynamic> json) {
    return PaymentRequestItem(
      id: json['id'] as String,
      requestLinkId: json['request_link_id'] as String,
      linkUrl: json['link_url'] as String? ?? '',
      amountUsdc: (json['amount_usdc'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      isInbound: false,
      description: json['description'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      recipientZendtag: json['recipient_zendtag'] as String?,
      recipientEmail: json['recipient_email'] as String?,
    );
  }

  factory PaymentRequestItem.fromInboundJson(Map<String, dynamic> json) {
    return PaymentRequestItem(
      id: json['id'] as String,
      requestLinkId: json['request_link_id'] as String,
      linkUrl: json['link_url'] as String? ?? '',
      amountUsdc: (json['amount_usdc'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      isInbound: true,
      description: json['description'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      requesterZendtag: json['requester_zendtag'] as String?,
      requesterDisplayName: json['requester_display_name'] as String?,
    );
  }
}
