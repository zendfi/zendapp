import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/pool_message_local.dart';

class MissionRoomMessage extends StatelessWidget {
  const MissionRoomMessage({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.onLongPress,
    required this.onReactionTap,
    this.isContinuation = false,
    this.onRetry,
    this.readReceipts = const {},
    this.isLastMessage = false,
    this.player,
    this.onPlayTap,
  });

  final PoolMessageLocal message;
  final String? currentUserId;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final bool isContinuation;
  final VoidCallback? onRetry;

  /// Map of zendtag → last_read_message_id for other pool members.
  final Map<String, String> readReceipts;

  /// Whether this is the last message in the list (used for read receipt display).
  final bool isLastMessage;

  /// AudioPlayer for this message (non-null only for voice notes currently playing/paused).
  final AudioPlayer? player;

  /// Called when the play/pause button is tapped on a voice note.
  final VoidCallback? onPlayTap;

  /// Zendtags of members who have read up to this message.
  List<String> _readersOf(String messageId) {
    return readReceipts.entries
        .where((e) => e.value == messageId)
        .map((e) => e.key)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.only(top: isContinuation ? 2 : 6, bottom: 2),
        child: switch (message.messageTypeEnum) {
          PoolMessageType.contributionEvent => _ContributionEventRow(
              message: message, onLongPress: onLongPress,
              onReactionTap: onReactionTap, currentUserId: currentUserId,
              onRetry: onRetry,
              readers: _readersOf(message.serverId ?? message.id)),
          PoolMessageType.voiceNote => _VoiceNoteRow(
              message: message, onLongPress: onLongPress,
              onReactionTap: onReactionTap, currentUserId: currentUserId,
              isContinuation: isContinuation, onRetry: onRetry,
              player: player, onPlayTap: onPlayTap,
              readers: _readersOf(message.serverId ?? message.id)),
          _ => _TextMessageRow(
              message: message, onLongPress: onLongPress,
              onReactionTap: onReactionTap, currentUserId: currentUserId,
              isContinuation: isContinuation, onRetry: onRetry,
              readers: _readersOf(message.serverId ?? message.id)),
        },
      ),
    );
  }
}

// ── Delivery status indicator ─────────────────────────────────────────────────

class _DeliveryStatus extends StatelessWidget {
  const _DeliveryStatus({required this.status, required this.onRetry});

  final LocalStatus status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    switch (status) {
      case LocalStatus.sending:
        return Icon(Icons.access_time, size: 12, color: zt.textSecondary.withValues(alpha: 0.5));
      case LocalStatus.delivered:
        return Icon(Icons.check, size: 12, color: zt.textSecondary.withValues(alpha: 0.5));
      case LocalStatus.failed:
        return GestureDetector(
          onTap: onRetry,
          child: const Icon(Icons.error_outline, size: 12, color: ZendColors.destructive),
        );
    }
  }
}

// ── Read receipt avatar stack ─────────────────────────────────────────────────

/// Shows small overlapping avatar initials for each reader.
class _ReadReceiptAvatars extends StatelessWidget {
  const _ReadReceiptAvatars({required this.readers});
  final List<String> readers;

  @override
  Widget build(BuildContext context) {
    if (readers.isEmpty) return const SizedBox.shrink();
    // Show at most 3 avatars.
    final visible = readers.take(3).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: visible.length * 12.0 + 4,
          height: 16,
          child: Stack(
            children: [
              for (var i = 0; i < visible.length; i++)
                Positioned(
                  left: i * 12.0,
                  child: ZendAvatar(
                    radius: 8,
                    initials: visible[i].isNotEmpty ? visible[i][0].toUpperCase() : '?',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Text message row ──────────────────────────────────────────────────────────

class _TextMessageRow extends StatelessWidget {
  const _TextMessageRow({
    required this.message, required this.onLongPress,
    required this.onReactionTap, required this.currentUserId,
    this.isContinuation = false, this.onRetry,
    this.readers = const [],
  });

  final PoolMessageLocal message;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final String? currentUserId;
  final bool isContinuation;
  final VoidCallback? onRetry;
  final List<String> readers;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final sender = message.senderZendtag ?? '?';
    final avatarLabel = sender.isNotEmpty ? sender[0].toUpperCase() : '?';
    final isMe = message.senderUserId != null && message.senderUserId == currentUserId;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isContinuation)
          const SizedBox(width: 36)
        else
          ZendAvatar(radius: 18, photoUrl: message.senderAvatarUrl, initials: avatarLabel),
        const SizedBox(width: ZendSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isContinuation) ...[
                Row(children: [
                  Text('@$sender', style: TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textPrimary)),
                  const SizedBox(width: ZendSpacing.xs),
                  Text(_formatTime(message.createdAt), style: TextStyle(fontFamily: 'DMSans', fontSize: 11, color: zt.textSecondary)),
                ]),
                const SizedBox(height: 2),
              ],
              Text(message.content ?? '', style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary, height: 1.4)),
              if (isMe) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DeliveryStatus(status: message.localStatus, onRetry: onRetry),
                    if (readers.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      _ReadReceiptAvatars(readers: readers),
                    ],
                  ],
                ),
              ] else if (readers.isNotEmpty) ...[
                const SizedBox(height: 2),
                _ReadReceiptAvatars(readers: readers),
              ],
              if (message.reactions.isNotEmpty) ...[
                const SizedBox(height: 4),
                _ReactionRow(reactions: message.reactions, currentUserId: currentUserId, onTap: onReactionTap),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Contribution event row ────────────────────────────────────────────────────

class _ContributionEventRow extends StatelessWidget {
  const _ContributionEventRow({
    required this.message, required this.onLongPress,
    required this.onReactionTap, required this.currentUserId,
    this.onRetry, this.readers = const [],
  });

  final PoolMessageLocal message;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final String? currentUserId;
  final VoidCallback? onRetry;
  final List<String> readers;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final isMe = message.senderUserId != null && message.senderUserId == currentUserId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZendSpacing.sm, vertical: ZendSpacing.xs),
      decoration: BoxDecoration(
        color: zt.accentBright.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZendRadii.md),
        border: Border.all(color: zt.accentBright.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(message.content ?? '', style: TextStyle(fontFamily: 'DMSans', fontSize: 14, fontWeight: FontWeight.w600, color: zt.textPrimary))),
            Text(_formatTime(message.createdAt), style: TextStyle(fontFamily: 'DMSans', fontSize: 11, color: zt.textSecondary)),
          ]),
          if (isMe || readers.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMe) _DeliveryStatus(status: message.localStatus, onRetry: onRetry),
                if (readers.isNotEmpty) ...[
                  if (isMe) const SizedBox(width: 4),
                  _ReadReceiptAvatars(readers: readers),
                ],
              ],
            ),
          ],
          if (message.reactions.isNotEmpty) ...[
            const SizedBox(height: 4),
            _ReactionRow(reactions: message.reactions, currentUserId: currentUserId, onTap: onReactionTap),
          ],
        ],
      ),
    );
  }
}

// ── Voice note row ────────────────────────────────────────────────────────────

class _VoiceNoteRow extends StatelessWidget {
  const _VoiceNoteRow({
    required this.message, required this.onLongPress,
    required this.onReactionTap, required this.currentUserId,
    this.isContinuation = false, this.onRetry,
    this.player, this.onPlayTap,
    this.readers = const [],
  });

  final PoolMessageLocal message;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final String? currentUserId;
  final bool isContinuation;
  final VoidCallback? onRetry;
  final AudioPlayer? player;
  final VoidCallback? onPlayTap;
  final List<String> readers;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final sender = message.senderZendtag ?? '?';
    final avatarLabel = sender.isNotEmpty ? sender[0].toUpperCase() : '?';
    final duration = message.voiceNoteDurationSeconds ?? 0;
    final isMe = message.senderUserId != null && message.senderUserId == currentUserId;

    final isPlaying = player?.playing ?? false;
    final position = player?.position ?? Duration.zero;
    final totalDuration = Duration(seconds: duration);
    final progress = duration > 0
        ? (position.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final displayTime = isPlaying
        ? _formatDuration(totalDuration - position)
        : _formatDuration(totalDuration);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isContinuation)
          const SizedBox(width: 36)
        else
          ZendAvatar(radius: 18, photoUrl: message.senderAvatarUrl, initials: avatarLabel),
        const SizedBox(width: ZendSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isContinuation) ...[
                Row(children: [
                  Text('@$sender', style: TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textPrimary)),
                  const SizedBox(width: ZendSpacing.xs),
                  Text(_formatTime(message.createdAt), style: TextStyle(fontFamily: 'DMSans', fontSize: 11, color: zt.textSecondary)),
                ]),
                const SizedBox(height: 4),
              ],
              // Voice note player pill
              GestureDetector(
                onTap: message.localStatus == LocalStatus.sending ? null : onPlayTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: ZendSpacing.sm, vertical: ZendSpacing.xs),
                  decoration: BoxDecoration(
                    color: zt.bgCard,
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Play/pause or sending indicator
                      if (message.localStatus == LocalStatus.sending)
                        SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: zt.accent),
                        )
                      else
                        Icon(
                          isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          size: 28,
                          color: zt.accent,
                        ),
                      const SizedBox(width: ZendSpacing.xs),
                      // Waveform progress bar
                      SizedBox(
                        width: 80,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(ZendRadii.pill),
                              child: LinearProgressIndicator(
                                value: progress.toDouble(),
                                minHeight: 4,
                                backgroundColor: zt.accentBright.withValues(alpha: 0.2),
                                valueColor: AlwaysStoppedAnimation<Color>(zt.accentBright),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: ZendSpacing.xs),
                      Text(
                        displayTime,
                        style: TextStyle(fontFamily: 'DMMono', fontSize: 12, color: zt.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              if (isMe || readers.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isMe) _DeliveryStatus(status: message.localStatus, onRetry: onRetry),
                    if (readers.isNotEmpty) ...[
                      if (isMe) const SizedBox(width: 4),
                      _ReadReceiptAvatars(readers: readers),
                    ],
                  ],
                ),
              ],
              if (message.reactions.isNotEmpty) ...[
                const SizedBox(height: 4),
                _ReactionRow(reactions: message.reactions, currentUserId: currentUserId, onTap: onReactionTap),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Reaction row ──────────────────────────────────────────────────────────────

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.reactions, required this.currentUserId, required this.onTap});

  final List<PoolReactionCount> reactions;
  final String? currentUserId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: reactions.map((r) {
        return GestureDetector(
          onTap: () => onTap(r.emoji),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: r.reactedByMe ? zt.accentBright.withValues(alpha: 0.2) : zt.bgCard,
              borderRadius: BorderRadius.circular(ZendRadii.pill),
              border: Border.all(color: r.reactedByMe ? zt.accentBright.withValues(alpha: 0.5) : zt.border),
            ),
            child: Text('${r.emoji} ${r.count}', style: const TextStyle(fontSize: 12)),
          ),
        );
      }).toList(),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  return '${dt.month}/${dt.day}';
}

String _formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
