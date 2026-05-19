class PaymentRequestNotification {
  const PaymentRequestNotification({
    required this.requestId,
    required this.requesterZendtag,
    required this.requesterDisplayName,
    required this.amountUsdc,
    this.description,
  });

  final String requestId;
  final String requesterZendtag;
  final String requesterDisplayName;
  final double amountUsdc;
  final String? description;

  factory PaymentRequestNotification.fromJson(Map<String, dynamic> json) {
    return PaymentRequestNotification(
      requestId: json['request_id'] as String? ?? '',
      requesterZendtag: json['requester_zendtag'] as String? ?? '',
      requesterDisplayName: json['requester_display_name'] as String? ?? '',
      amountUsdc: double.tryParse(
            (json['amount_usdc'] as Object?)?.toString() ?? '',
          ) ??
          0.0,
      description: json['description'] as String?,
    );
  }

  String get formattedAmount {
    if (amountUsdc == amountUsdc.roundToDouble()) {
      return '\$${amountUsdc.toStringAsFixed(0)}';
    }
    return '\$${amountUsdc.toStringAsFixed(2)}';
  }
}
