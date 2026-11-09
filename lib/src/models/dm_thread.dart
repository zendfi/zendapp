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

  String get initialLetter =>
      zendtag.isNotEmpty ? zendtag[0].toUpperCase() : '?';

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
    this.group,
  });

  final String roomId;
  final DmCounterparty counterparty;
  final DmMessage? lastMessage;
  final int unreadCount;
  final DateTime lastMessageAt;

  /// Set for group chats. [counterparty] is then a stand-in carrying the group
  /// name, so screens that only need a title and an avatar keep working.
  final DmGroupSummary? group;

  bool get isGroup => group != null;

  /// Builds a thread from an entry of the `groups` array in GET /api/zend/dm.
  factory DmThread.fromGroupJson(Map<String, dynamic> json) {
    final roomId = json['room_id'] as String? ?? '';
    final summary = DmGroupSummary.fromJson(json);
    DmMessage? lastMsg;
    final lm = json['last_message'] as Map<String, dynamic>?;
    if (lm != null) {
      lastMsg = DmMessage.fromJson({...lm, 'id': 'preview', 'room_id': roomId});
    }
    return DmThread(
      roomId: roomId,
      counterparty: summary.asCounterparty(),
      lastMessage: lastMsg,
      unreadCount: json['unread_count'] as int? ?? 0,
      lastMessageAt:
          DateTime.tryParse(json['last_message_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      group: summary,
    );
  }

  factory DmThread.fromJson(Map<String, dynamic> json) {
    DmMessage? lastMsg;
    final lastMsgJson = json['last_message'] as Map<String, dynamic>?;
    if (lastMsgJson != null) {
      lastMsg = DmMessage.fromJson({
        ...lastMsgJson,
        // 'id' is intentionally not sent by list_threads (DmLastMessage has
        // no id field) — supply a placeholder so DmMessage.fromJson doesn't
        // silently produce an empty id. This message is only ever used for
        // its preview text, never looked up by id.
        'id': lastMsgJson['id'] as String? ?? 'preview',
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
      lastMessageAt:
          DateTime.tryParse(json['last_message_at'] as String? ?? '') ??
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

  /// Preview line for the chat list. In a group it is prefixed with the sender.
  String get listPreview {
    final base = lastMessagePreview;
    final g = group;
    if (g == null || base.isEmpty || (lastMessage?.isSystem ?? false)) {
      return base;
    }
    final who = g.lastSenderTag;
    if (who == null || who.isEmpty) return base;
    // A long name (an email-style handle, say) would push the message out of the row.
    final short = who.length > 14 ? '${who.substring(0, 13)}…' : who;
    return '$short: $base';
  }

  String get lastMessagePreview {
    if (lastMessage == null) return '';
    if (lastMessage!.isSystem) return lastMessage!.content ?? '';
    switch (lastMessage!.type) {
      case DmMessageType.text:
        final content = lastMessage!.content ?? '';
        if (content.startsWith(kE2eePrefix)) return _lockedPreviewFallback;
        // GIF messages are stored as `gif:<id>`; never show the raw id.
        if (content.trim().startsWith('gif:')) return '🖼️ GIF';
        return content.length > 40 ? '${content.substring(0, 40)}…' : content;
      case DmMessageType.payment:
        // paymentData is parsed from the message's metadata JSON — see
        // DmMessage.fromJson. Falls back to '0.00' only if metadata was
        // genuinely empty/missing (shouldn't happen for real payment
        // messages), rather than always showing $0.
        final amt =
            double.tryParse(lastMessage!.paymentData?.amountUsdc ?? '') ?? 0.0;
        return '💸 \$${amt.toStringAsFixed(2)}';
      case DmMessageType.vibe:
        final vd = lastMessage!.vibeData;
        final amt = double.tryParse(vd?.amountUsdc ?? '') ?? 0.0;
        return '${vd?.displayEmoji ?? '✨'} Vibe · \$${amt.toStringAsFixed(2)}';
      case DmMessageType.paymentRequest:
        final amt =
            double.tryParse(
              lastMessage!.paymentRequestData?.amountUsdc ?? '',
            ) ??
            0.0;
        return '💬 Payment request · \$${amt.toStringAsFixed(2)}';
      case DmMessageType.appCard:
        final d = lastMessage!.appCardData ?? const {};
        return '${d['app_name'] ?? 'App'}: ${(d['slots'] as Map?)?['title'] ?? ''}';
    }
  }
}

/// Group details shown on the chat list and in the thread header.
class DmGroupSummary {
  const DmGroupSummary({
    required this.roomId,
    required this.name,
    this.emoji,
    this.memberCount = 0,
    this.memberAvatars = const [],
    this.muted = false,
    this.lastSenderTag,
  });

  final String roomId;
  final String name;
  final String? emoji;
  final int memberCount;
  final List<DmCounterparty> memberAvatars;
  final bool muted;

  /// Zendtag of whoever sent the last message, for "ada: see you there".
  final String? lastSenderTag;

  factory DmGroupSummary.fromJson(Map<String, dynamic> json) {
    final avatars = (json['member_avatars'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(DmCounterparty.fromJson)
        .toList();
    final last = json['last_message'] as Map<String, dynamic>?;
    return DmGroupSummary(
      roomId: json['room_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Group',
      emoji: (json['emoji'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['emoji'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      memberAvatars: avatars,
      muted: json['muted'] as bool? ?? false,
      lastSenderTag: last?['sender_zendtag'] as String?,
    );
  }

  /// Stand-in used where a screen expects a [DmCounterparty]. The id is
  /// prefixed so it can never collide with a real person.
  DmCounterparty asCounterparty() =>
      DmCounterparty(userId: 'group:$roomId', zendtag: name, displayName: name);
}

/// Group room ids start with `g_`; direct rooms are plain hex.
bool isGroupRoomId(String roomId) => roomId.startsWith('g_');
