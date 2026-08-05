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

/// Delivery/read status for the current user's own outgoing messages.
/// `read` is a strict upgrade from `delivered` — set once a `readReceipt`
/// WS frame (or the HTTP mark_read fallback) confirms the counterparty has
/// seen a message at or after this one. Mirrors WhatsApp/iMessage's
/// single-tick (sent) → double-tick (delivered) → blue double-tick (read)
/// progression, collapsed here to sending → delivered → read since there's
/// no separate "delivered to device" signal in this transport.
enum DmLocalStatus { sending, delivered, read, failed }

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
    this.replyToMessageId,
    this.isForwarded = false,
    this.isDeleted = false,
  });

  final String id;
  final String roomId;
  final String senderUserId;
  final String? senderZendtag;
  final String? senderAvatarUrl;
  final DmMessageType type;
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
  /// UUID of the original message being replied to — used for accurate scroll-to-original.
  final String? replyToMessageId;
  /// True when this message was forwarded from another chat — renders a
  /// "Forwarded" label above the bubble, matching WhatsApp/iMessage. The
  /// original sender/room is deliberately not carried over.
  final bool isForwarded;
  /// Set once the server confirms this message was soft-deleted (by its
  /// sender). Deleted messages render a "message deleted" placeholder
  /// instead of their original content.
  bool isDeleted;
  /// True when the content was encrypted at rest and has been decrypted for display.
  bool isEncrypted = false;

  // content is mutable so E2EE decryption can update it in place after load
  String? content;

  bool get isMe => false; // caller sets based on currentUserId

  /// Safe content for display. If [content] still carries the raw `e2ee:`
  /// wire prefix — meaning a decryption attempt hasn't replaced it yet, due
  /// to the async key-fetch/history-load race — show a lock placeholder
  /// instead of the ciphertext. Once decryption succeeds (or fails and is
  /// replaced with a 🔒 placeholder string), content no longer starts with
  /// `e2ee:` and this simply returns it unchanged.
  String? get displayContent {
    if (isDeleted) return null; // bubble renders its own placeholder text
    final c = content;
    if (c != null && c.startsWith('e2ee:')) {
      return '🔒 (decrypting…)';
    }
    return c;
  }

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
      createdAt: (DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now()).toLocal(),
      reactions: (json['reactions'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(DmReaction.fromJson)
          .toList(),
      replyToContent: json['reply_to_content'] as String?
          ?? meta['reply_to_content'] as String?,
      replyToSenderZendtag: json['reply_to_sender_zendtag'] as String?
          ?? meta['reply_to_sender_zendtag'] as String?,
      replyToMessageId: json['reply_to_message_id'] as String?
          ?? meta['reply_to_message_id'] as String?,
      isForwarded: meta['forwarded'] as bool? ?? false,
      isDeleted: json['deleted_at'] != null,
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
