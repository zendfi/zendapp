/// A payment request that was sent *to* the current user by another Zend user.
class InboundPaymentRequest {
  const InboundPaymentRequest({
    required this.id,
    required this.requestLinkId,
    required this.linkUrl,
    required this.amountUsdc,
    required this.status,
    required this.createdAt,
    required this.requesterZendtag,
    required this.requesterDisplayName,
    this.description,
    this.expiresAt,
  });

  final String id;
  final String requestLinkId;
  final String linkUrl;
  final double amountUsdc;
  final String status; // 'pending' | 'paid' | 'expired' | 'cancelled'
  final DateTime createdAt;
  final String requesterZendtag;
  final String requesterDisplayName;
  final String? description;
  final DateTime? expiresAt;

  bool get isPending => status == 'pending';

  String get formattedAmount {
    if (amountUsdc == amountUsdc.roundToDouble()) {
      return '\$${amountUsdc.toStringAsFixed(0)}';
    }
    return '\$${amountUsdc.toStringAsFixed(2)}';
  }

  factory InboundPaymentRequest.fromJson(Map<String, dynamic> json) {
    return InboundPaymentRequest(
      id: json['id'] as String,
      requestLinkId: json['request_link_id'] as String,
      linkUrl: json['link_url'] as String? ?? '',
      amountUsdc: (json['amount_usdc'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      requesterZendtag: json['requester_zendtag'] as String? ?? '',
      requesterDisplayName: json['requester_display_name'] as String? ?? '',
      description: json['description'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
    );
  }
}
