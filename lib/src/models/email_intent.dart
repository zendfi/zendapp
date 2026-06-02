class EmailIntent {
  final String id;
  final double amountUsdc;
  final DateTime expiry;
  final String status; // 'pending' | 'claimed' | 'expired' | 'cancelled'
  final String? note;
  final DateTime createdAt;
  /// Masked recipient email hint, e.g. "to***@gmail.com".
  final String recipientHint;

  const EmailIntent({
    required this.id,
    required this.amountUsdc,
    required this.expiry,
    required this.status,
    this.note,
    required this.createdAt,
    required this.recipientHint,
  });

  factory EmailIntent.fromJson(Map<String, dynamic> json) {
    return EmailIntent(
      id: json['id'] as String,
      amountUsdc: (json['amount_usdc'] as num).toDouble(),
      expiry: DateTime.parse(json['expiry'] as String),
      status: json['status'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      recipientHint: json['recipient_hint'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount_usdc': amountUsdc,
        'expiry': expiry.toIso8601String(),
        'status': status,
        'note': note,
        'created_at': createdAt.toIso8601String(),
        'recipient_hint': recipientHint,
      };

  bool get isPending => status == 'pending';
  bool get isClaimed => status == 'claimed';
  bool get isExpired => status == 'expired';
  bool get isCancelled => status == 'cancelled';

  /// Formatted amount string, e.g. "$5.00"
  String get amountFormatted {
    if (amountUsdc == amountUsdc.roundToDouble()) {
      return '\$${amountUsdc.toStringAsFixed(0)}';
    }
    return '\$${amountUsdc.toStringAsFixed(2)}';
  }

  /// Days remaining before expiry (0 if already expired).
  int get daysRemaining {
    final diff = expiry.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inDays;
  }
}

/// Result from `POST /api/zend/email-intents`.
class CreateIntentResult {
  final String id;
  final double amountUsdc;
  final DateTime expiry;
  final String status;

  const CreateIntentResult({
    required this.id,
    required this.amountUsdc,
    required this.expiry,
    required this.status,
  });

  factory CreateIntentResult.fromJson(Map<String, dynamic> json) {
    return CreateIntentResult(
      id: json['id'] as String,
      amountUsdc: (json['amount_usdc'] as num).toDouble(),
      expiry: DateTime.parse(json['expiry'] as String),
      status: json['status'] as String,
    );
  }
}

/// Public preview of an email intent, returned by
/// `GET /api/zend/claim/:id/preview` — no auth required.
class IntentPreview {
  final double amountUsdc;
  final String senderZendtag;
  final String senderDisplayName;
  final DateTime expiry;
  final String status;

  const IntentPreview({
    required this.amountUsdc,
    required this.senderZendtag,
    required this.senderDisplayName,
    required this.expiry,
    required this.status,
  });

  factory IntentPreview.fromJson(Map<String, dynamic> json) {
    return IntentPreview(
      amountUsdc: (json['amount_usdc'] as num).toDouble(),
      senderZendtag: json['sender_zendtag'] as String,
      senderDisplayName: json['sender_display_name'] as String,
      expiry: DateTime.parse(json['expiry'] as String),
      status: json['status'] as String,
    );
  }

  bool get isPending => status == 'pending';

  String get amountFormatted {
    if (amountUsdc == amountUsdc.roundToDouble()) {
      return '\$${amountUsdc.toStringAsFixed(0)}';
    }
    return '\$${amountUsdc.toStringAsFixed(2)}';
  }
}
