import 'dm_message.dart';

class DmCounterparty {
  const DmCounterparty({
    required this.userId,
    required this.zendtag,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String zendtag;
  final String displayName;
  final String? avatarUrl;

  String get initialLetter => zendtag.isNotEmpty ? zendtag[0].toUpperCase() : '?';

  factory DmCounterparty.fromJson(Map<String, dynamic> json) {
    return DmCounterparty(
      userId: json['user_id'] as String? ?? '',
      zendtag: json['zendtag'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class DmThread {
  const DmThread({
    required this.roomId,
    required this.counterparty,
    this.lastMessage,
    required this.unreadCount,
    required this.lastMessageAt,
  });

  final String roomId;
  final DmCounterparty counterparty;
  final DmMessage? lastMessage;
  final int unreadCount;
  final DateTime lastMessageAt;

  factory DmThread.fromJson(Map<String, dynamic> json) {
    DmMessage? lastMsg;
    final lastMsgJson = json['last_message'] as Map<String, dynamic>?;
    if (lastMsgJson != null) {
      lastMsg = DmMessage.fromJson({
        ...lastMsgJson,
        'room_id': json['room_id'] as String? ?? '',
      });
    }

    return DmThread(
      roomId: json['room_id'] as String? ?? '',
      counterparty: DmCounterparty.fromJson(
        json['counterparty'] as Map<String, dynamic>? ?? {},
      ),
      lastMessage: lastMsg,
      unreadCount: json['unread_count'] as int? ?? 0,
      lastMessageAt: DateTime.tryParse(json['last_message_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String get lastMessagePreview {
    if (lastMessage == null) return '';
    switch (lastMessage!.type) {
      case DmMessageType.text:
        final content = lastMessage!.content ?? '';
        return content.length > 40 ? '${content.substring(0, 40)}…' : content;
      case DmMessageType.payment:
        final amt = lastMessage!.paymentData?.amountUsdc ?? '0';
        return '💸 \$$amt';
      case DmMessageType.vibe:
        final name = lastMessage!.vibeData?.stickerName ?? 'Vibe';
        final amt = lastMessage!.vibeData?.amountUsdc ?? '0';
        return '🎁 $name · \$$amt';
      case DmMessageType.paymentRequest:
        return '💬 Payment request';
    }
  }
}
