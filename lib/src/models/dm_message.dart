/// A single emoji reaction on a DM message — tracks count and whether the
/// current user has reacted with this emoji.
class DmReaction {
  final String emoji;
  final int count;
  final bool reactedByMe;

  const DmReaction({required this.emoji, required this.count, required this.reactedByMe});

  factory DmReaction.fromJson(Map<String, dynamic> json) => DmReaction(
    emoji: json['emoji'] as String,
    count: (json['count'] as num?)?.toInt() ?? 1,
    reactedByMe: json['reacted_by_me'] as bool? ?? false,
  );

  DmReaction copyWith({int? count, bool? reactedByMe}) => DmReaction(
    emoji: emoji,
    count: count ?? this.count,
    reactedByMe: reactedByMe ?? this.reactedByMe,
  );
}

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

/// Slug→emoji fallback map — used when the server metadata doesn't include
/// an explicit `sticker_emoji` field (older messages).
const _kSlugToEmoji = {
  'fire': '🔥',
  'heart': '❤️',
  'money': '💸',
  'clap': '👏',
  'star': '⭐',
  'rocket': '🚀',
  'crown': '👑',
  'gift': '🎁',
  'party': '🎉',
  'highfive': '🙏',
  'laugh': '😂',
  'wave': '👋',
};

/// Data for a payment request sent inside a DM thread.
class DmPaymentRequestData {
  const DmPaymentRequestData({
    required this.amountUsdc,
    required this.requesterZendtag,
    this.note,
    required this.status,
  });

  final String amountUsdc;
  final String requesterZendtag;
  final String? note;
  /// 'pending' | 'paid' | 'cancelled'
  final String status;

  bool get isPending => status == 'pending';

  factory DmPaymentRequestData.fromJson(Map<String, dynamic> json) =>
      DmPaymentRequestData(
        amountUsdc: json['amount_usdc'] as String? ?? '0',
        requesterZendtag: json['requester_zendtag'] as String? ?? '',
        note: json['note'] as String?,
        status: json['status'] as String? ?? 'pending',
      );
}

class DmVibeData {
  const DmVibeData({
    required this.stickerId,
    required this.stickerSlug,
    required this.stickerName,
    required this.amountUsdc,
    required this.transferId,
    this.stickerEmoji,
  });

  final String stickerId;
  final String stickerSlug;
  final String stickerName;
  final String amountUsdc;
  final String transferId;
  /// The actual emoji character. Derived from stickerSlug if not explicitly set.
  final String? stickerEmoji;

  /// Returns the best available emoji for display.
  String get displayEmoji {
    if (stickerEmoji != null && stickerEmoji!.isNotEmpty) return stickerEmoji!;
    // If stickerSlug is already an emoji (contains non-ASCII), use it directly
    if (stickerSlug.runes.any((r) => r > 127)) return stickerSlug;
    // Map slug → emoji
    return _kSlugToEmoji[stickerSlug.toLowerCase()] ?? '✨';
  }

  factory DmVibeData.fromJson(Map<String, dynamic> json) {
    return DmVibeData(
      stickerId: json['sticker_id'] as String? ?? '',
      stickerSlug: json['sticker_slug'] as String? ?? '',
      stickerName: json['sticker_name'] as String? ?? '',
      amountUsdc: json['amount_usdc'] as String? ?? '0',
      transferId: json['transfer_id'] as String? ?? '',
      stickerEmoji: json['sticker_emoji'] as String?,
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
    this.paymentRequestData,
    this.clientId,
    required this.createdAt,
    this.localStatus = DmLocalStatus.delivered,
    this.reactions = const [],
    this.replyToContent,
    this.replyToSenderZendtag,
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
  final DmPaymentRequestData? paymentRequestData;
  final String? clientId;
  final DateTime createdAt;
  DmLocalStatus localStatus;
  /// Live emoji reactions — updated optimistically and via WS frames.
  List<DmReaction> reactions;
  /// If this message is a reply, the quoted snippet of the parent message.
  final String? replyToContent;
  final String? replyToSenderZendtag;

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
    DmPaymentRequestData? paymentRequestData;
    if (type == DmMessageType.payment && meta.isNotEmpty) {
      paymentData = DmPaymentData.fromJson(meta);
    } else if (type == DmMessageType.vibe && meta.isNotEmpty) {
      vibeData = DmVibeData.fromJson(meta);
    } else if (type == DmMessageType.paymentRequest && meta.isNotEmpty) {
      paymentRequestData = DmPaymentRequestData.fromJson(meta);
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
      paymentRequestData: paymentRequestData,
      clientId: json['client_id'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      reactions: (json['reactions'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(DmReaction.fromJson)
          .toList(),
      replyToContent: json['reply_to_content'] as String?,
      replyToSenderZendtag: json['reply_to_sender_zendtag'] as String?,
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
