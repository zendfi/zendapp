import 'dm_message.dart';
import '../services/e2ee_service.dart' show kE2eePrefix;

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

  /// Defensive fallback shown for an encrypted text preview that hasn't
  /// been decrypted yet (or couldn't be). This is a UI-safety net, not the
  /// primary decryption path — DmListScreen decrypts thread previews in the
  /// background and mutates [DmMessage.content] in place on success, at
  /// which point this getter naturally starts returning the real text
  /// instead. The point of keeping this check here (rather than trusting
  /// callers to always decrypt first) is that the raw `e2ee:<base64>` wire
  /// string must never be able to reach a Text widget under any code path,
  /// present or future.
  static const _lockedPreviewFallback = '🔒 New message';

  String get lastMessagePreview {
    if (lastMessage == null) return '';
    switch (lastMessage!.type) {
      case DmMessageType.text:
        final content = lastMessage!.content ?? '';
        if (content.startsWith(kE2eePrefix)) return _lockedPreviewFallback;
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
