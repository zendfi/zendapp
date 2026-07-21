enum DmMessageType { text, payment, vibe, paymentRequest }

enum DmLocalStatus { sending, delivered, failed }

class DmPaymentData {
  const DmPaymentData({
    required this.transferId,
    required this.amountUsdc,
    required this.direction,
    this.note,
    required this.status,
  });

  final String transferId;
  final String amountUsdc;
  /// 'sent' or 'received' from the sender's perspective
  final String direction;
  final String? note;
  final String status;

  factory DmPaymentData.fromJson(Map<String, dynamic> json) {
    return DmPaymentData(
      transferId: json['transfer_id'] as String? ?? '',
      amountUsdc: json['amount_usdc'] as String? ?? '0',
      direction: json['direction'] as String? ?? 'sent',
      note: json['note'] as String?,
      status: json['status'] as String? ?? 'confirmed',
    );
  }
}

class DmVibeData {
  const DmVibeData({
    required this.stickerId,
    required this.stickerSlug,
    required this.stickerName,
    required this.amountUsdc,
    required this.transferId,
  });

  final String stickerId;
  final String stickerSlug;
  final String stickerName;
  final String amountUsdc;
  final String transferId;

  factory DmVibeData.fromJson(Map<String, dynamic> json) {
    return DmVibeData(
      stickerId: json['sticker_id'] as String? ?? '',
      stickerSlug: json['sticker_slug'] as String? ?? '',
      stickerName: json['sticker_name'] as String? ?? '',
      amountUsdc: json['amount_usdc'] as String? ?? '0',
      transferId: json['transfer_id'] as String? ?? '',
    );
  }
}

class DmMessage {
  DmMessage({
    required this.id,
    required this.roomId,
    required this.senderUserId,
    this.senderZendtag,
    this.senderAvatarUrl,
    required this.type,
    this.content,
    this.paymentData,
    this.vibeData,
    this.clientId,
    required this.createdAt,
    this.localStatus = DmLocalStatus.delivered,
  });

  final String id;
  final String roomId;
  final String senderUserId;
  final String? senderZendtag;
  final String? senderAvatarUrl;
  final DmMessageType type;
  final String? content;
  final DmPaymentData? paymentData;
  final DmVibeData? vibeData;
  final String? clientId;
  final DateTime createdAt;
  DmLocalStatus localStatus;

  bool get isMe => false; // caller sets based on currentUserId

  factory DmMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['message_type'] as String? ?? 'text';
    final type = switch (typeStr) {
      'payment' => DmMessageType.payment,
      'vibe' => DmMessageType.vibe,
      'payment_request' => DmMessageType.paymentRequest,
      _ => DmMessageType.text,
    };

    final meta = json['metadata'] as Map<String, dynamic>? ?? {};

    DmPaymentData? paymentData;
    DmVibeData? vibeData;
    if (type == DmMessageType.payment && meta.isNotEmpty) {
      paymentData = DmPaymentData.fromJson(meta);
    } else if (type == DmMessageType.vibe && meta.isNotEmpty) {
      vibeData = DmVibeData.fromJson(meta);
    }

    return DmMessage(
      id: json['id'] as String? ?? '',
      roomId: json['room_id'] as String? ?? '',
      senderUserId: json['sender_user_id'] as String? ?? '',
      senderZendtag: json['sender_zendtag'] as String?,
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      type: type,
      content: json['content'] as String?,
      paymentData: paymentData,
      vibeData: vibeData,
      clientId: json['client_id'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// Creates an optimistic local-only message for immediate UI display.
  factory DmMessage.optimistic({
    required String roomId,
    required String senderUserId,
    required String senderZendtag,
    String? senderAvatarUrl,
    required String content,
    required String clientId,
  }) {
    return DmMessage(
      id: 'local-$clientId',
      roomId: roomId,
      senderUserId: senderUserId,
      senderZendtag: senderZendtag,
      senderAvatarUrl: senderAvatarUrl,
      type: DmMessageType.text,
      content: content,
      clientId: clientId,
      createdAt: DateTime.now(),
      localStatus: DmLocalStatus.sending,
    );
  }
}
