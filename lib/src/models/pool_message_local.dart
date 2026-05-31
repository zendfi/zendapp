import '../features/pools/pool.dart';

export '../features/pools/pool.dart' show PoolMessage, PoolMessageType, PoolReactionCount;

enum LocalStatus { sending, delivered, failed }

class PoolMessageLocal {
  final String id;
  final String poolId;
  final String? clientId;
  final String? serverId;
  final String? senderUserId;
  final String? senderZendtag;
  final String? senderAvatarUrl;
  final String messageType;
  final String? content;
  final String? contributionId;
  final String? voiceNoteUrl;
  final int? voiceNoteDurationSeconds;
  final List<double>? waveformData;
  final LocalStatus localStatus;
  final DateTime createdAt;
  final List<PoolReactionCount> reactions;

  const PoolMessageLocal({
    required this.id,
    required this.poolId,
    this.clientId,
    this.serverId,
    this.senderUserId,
    this.senderZendtag,
    this.senderAvatarUrl,
    required this.messageType,
    this.content,
    this.contributionId,
    this.voiceNoteUrl,
    this.voiceNoteDurationSeconds,
    this.waveformData,
    required this.localStatus,
    required this.createdAt,
    this.reactions = const [],
  });

  PoolMessageLocal copyWith({
    LocalStatus? localStatus,
    String? serverId,
    DateTime? createdAt,
    List<PoolReactionCount>? reactions,
  }) {
    return PoolMessageLocal(
      id: serverId ?? id,
      poolId: poolId,
      clientId: clientId,
      serverId: serverId ?? this.serverId,
      senderUserId: senderUserId,
      senderZendtag: senderZendtag,
      senderAvatarUrl: senderAvatarUrl,
      messageType: messageType,
      content: content,
      contributionId: contributionId,
      voiceNoteUrl: voiceNoteUrl,
      voiceNoteDurationSeconds: voiceNoteDurationSeconds,
      waveformData: waveformData,
      localStatus: localStatus ?? this.localStatus,
      createdAt: createdAt ?? this.createdAt,
      reactions: reactions ?? this.reactions,
    );
  }

  PoolMessageLocal withReactions(List<PoolReactionCount> newReactions) =>
      copyWith(reactions: newReactions);

  /// Creates a [PoolMessageLocal] from a WebSocket `message` frame payload.
  factory PoolMessageLocal.fromWsFrame(Map<String, dynamic> data) {
    return PoolMessageLocal(
      id: data['server_id'] as String? ?? '',
      poolId: data['pool_id'] as String? ?? '',
      serverId: data['server_id'] as String?,
      senderUserId: data['sender_user_id'] as String?,
      senderZendtag: data['sender_zendtag'] as String?,
      senderAvatarUrl: data['sender_avatar_url'] as String?,
      messageType: data['message_type'] as String? ?? 'text',
      content: data['content'] as String?,
      contributionId: data['contribution_id'] as String?,
      voiceNoteUrl: data['voice_note_url'] as String?,
      voiceNoteDurationSeconds: data['voice_note_duration_seconds'] as int?,
      localStatus: LocalStatus.delivered,
      createdAt: DateTime.tryParse(data['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// Creates a [PoolMessageLocal] from the legacy [PoolMessage] REST model.
  factory PoolMessageLocal.fromPoolMessage(PoolMessage msg) {
    return PoolMessageLocal(
      id: msg.id,
      poolId: msg.poolId,
      serverId: msg.id,
      senderUserId: msg.senderUserId,
      senderZendtag: msg.senderZendtag,
      senderAvatarUrl: msg.senderAvatarUrl,
      messageType: switch (msg.messageType) {
        PoolMessageType.contributionEvent => 'contribution_event',
        PoolMessageType.voiceNote => 'voice_note',
        _ => 'text',
      },
      content: msg.content,
      contributionId: msg.contributionId,
      voiceNoteUrl: msg.voiceNoteUrl,
      voiceNoteDurationSeconds: msg.voiceNoteDurationSeconds,
      localStatus: LocalStatus.delivered,
      createdAt: msg.createdAt,
      reactions: msg.reactions,
    );
  }

  /// Converts the [messageType] string to a [PoolMessageType] enum value.
  PoolMessageType get messageTypeEnum => switch (messageType) {
    'contribution_event' => PoolMessageType.contributionEvent,
    'voice_note' => PoolMessageType.voiceNote,
    _ => PoolMessageType.text,
  };
}
