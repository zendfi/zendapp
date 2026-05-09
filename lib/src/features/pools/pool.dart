import 'dart:math';

const _base62Chars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

String generatePoolId() {
  final random = Random();
  return String.fromCharCodes(
    Iterable.generate(
      8,
      (_) => _base62Chars.codeUnitAt(random.nextInt(_base62Chars.length)),
    ),
  );
}

/// Lifecycle state of a Pool.
enum PoolStatus { active, completed, expired, cancelled }

PoolStatus _poolStatusFromString(String s) {
  switch (s) {
    case 'completed':
      return PoolStatus.completed;
    case 'expired':
      return PoolStatus.expired;
    case 'cancelled':
      return PoolStatus.cancelled;
    default:
      return PoolStatus.active;
  }
}

String _poolStatusToString(PoolStatus s) {
  switch (s) {
    case PoolStatus.completed:
      return 'completed';
    case PoolStatus.expired:
      return 'expired';
    case PoolStatus.cancelled:
      return 'cancelled';
    case PoolStatus.active:
      return 'active';
  }
}

class PoolParticipant {
  const PoolParticipant({
    required this.id,
    required this.displayName,
    required this.avatarLabel,
    this.userId,
    this.contribution = 0.0,
    this.isExternal = false,
  });

  final String id;
  final String displayName;
  final String avatarLabel;

  /// UUID of the Zend user, null for external contacts.
  final String? userId;

  final double contribution;
  final bool isExternal;

  factory PoolParticipant.fromJson(Map<String, dynamic> json) {
    final displayName = json['display_name'] as String? ?? '';
    return PoolParticipant(
      id: json['id'] as String? ?? '',
      displayName: displayName,
      avatarLabel: displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
      userId: json['user_id'] as String?,
      contribution: (json['contribution'] as num?)?.toDouble() ?? 0.0,
      isExternal: json['is_external'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'user_id': userId,
        'contribution': contribution,
        'is_external': isExternal,
      };
}

class Pool {
  Pool({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.participants,
    required this.createdAt,
    required this.creatorUserId,
    required this.creatorZendtag,
    this.deadline,
    this.gathered = 0.0,
    this.status = PoolStatus.active,
    this.completedAt,
  });

  final String id;
  final String name;
  final double targetAmount;
  final List<PoolParticipant> participants;
  final DateTime createdAt;
  final DateTime? deadline;
  final String creatorUserId;
  final String creatorZendtag;
  double gathered;
  PoolStatus status;
  DateTime? completedAt;

  /// Progress ratio clamped to [0.0, 1.0].
  double get progress =>
      targetAmount <= 0 ? 0.0 : (gathered / targetAmount).clamp(0.0, 1.0);

  /// Formatted gathered amount as a dollar string.
  String get formattedGathered => '\$${gathered.toStringAsFixed(2)}';

  /// Formatted target amount as a dollar string.
  String get formattedTarget => '\$${targetAmount.toStringAsFixed(2)}';

  factory Pool.fromJson(Map<String, dynamic> json) {
    final participantsJson =
        (json['participants'] as List<dynamic>?) ?? <dynamic>[];
    return Pool(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      targetAmount:
          (json['target_amount_usdc'] as num?)?.toDouble() ?? 0.0,
      gathered:
          (json['gathered_amount_usdc'] as num?)?.toDouble() ?? 0.0,
      status: _poolStatusFromString(json['status'] as String? ?? 'active'),
      creatorUserId: json['creator_user_id'] as String? ?? '',
      creatorZendtag: json['creator_zendtag'] as String? ?? '',
      participants: participantsJson
          .map((p) => PoolParticipant.fromJson(p as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target_amount_usdc': targetAmount,
        'gathered_amount_usdc': gathered,
        'status': _poolStatusToString(status),
        'creator_user_id': creatorUserId,
        'creator_zendtag': creatorZendtag,
        'participants': participants.map((p) => p.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'deadline': deadline?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
      };
}

// ── Message types ─────────────────────────────────────────────────────────────

enum PoolMessageType { text, contributionEvent, voiceNote }

PoolMessageType _messageTypeFromString(String s) {
  switch (s) {
    case 'contribution_event':
      return PoolMessageType.contributionEvent;
    case 'voice_note':
      return PoolMessageType.voiceNote;
    default:
      return PoolMessageType.text;
  }
}

class PoolReactionCount {
  const PoolReactionCount({
    required this.emoji,
    required this.count,
    required this.reactedByMe,
  });

  final String emoji;
  final int count;
  final bool reactedByMe;

  factory PoolReactionCount.fromJson(Map<String, dynamic> json) =>
      PoolReactionCount(
        emoji: json['emoji'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        reactedByMe: json['reacted_by_me'] as bool? ?? false,
      );
}

class PoolMessage {
  const PoolMessage({
    required this.id,
    required this.poolId,
    required this.messageType,
    required this.createdAt,
    this.senderZendtag,
    this.senderUserId,
    this.content,
    this.contributionId,
    this.voiceNoteUrl,
    this.voiceNoteDurationSeconds,
    this.reactions = const [],
  });

  final String id;
  final String poolId;
  final String? senderZendtag;
  final String? senderUserId;
  final PoolMessageType messageType;
  final String? content;
  final String? contributionId;
  final String? voiceNoteUrl;
  final int? voiceNoteDurationSeconds;
  final List<PoolReactionCount> reactions;
  final DateTime createdAt;

  factory PoolMessage.fromJson(Map<String, dynamic> json) {
    final reactionsJson =
        (json['reactions'] as List<dynamic>?) ?? <dynamic>[];
    return PoolMessage(
      id: json['id'] as String? ?? '',
      poolId: json['pool_id'] as String? ?? '',
      senderZendtag: json['sender_zendtag'] as String?,
      senderUserId: json['sender_user_id'] as String?,
      messageType:
          _messageTypeFromString(json['message_type'] as String? ?? 'text'),
      content: json['content'] as String?,
      contributionId: json['contribution_id'] as String?,
      voiceNoteUrl: json['voice_note_url'] as String?,
      voiceNoteDurationSeconds:
          (json['voice_note_duration_seconds'] as num?)?.toInt(),
      reactions: reactionsJson
          .map((r) =>
              PoolReactionCount.fromJson(r as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Returns a copy with updated reaction counts.
  PoolMessage withReactions(List<PoolReactionCount> newReactions) =>
      PoolMessage(
        id: id,
        poolId: poolId,
        senderZendtag: senderZendtag,
        senderUserId: senderUserId,
        messageType: messageType,
        content: content,
        contributionId: contributionId,
        voiceNoteUrl: voiceNoteUrl,
        voiceNoteDurationSeconds: voiceNoteDurationSeconds,
        reactions: newReactions,
        createdAt: createdAt,
      );
}
