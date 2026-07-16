import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/pool_message_local.dart';

/// Renders a single pool chat message.
///
/// When [participantCount] ≤ 3, messages from the current user are
/// right-aligned in rounded iMessage-style bubbles; others left-aligned.
/// When > 3 (larger group), everyone is left-aligned, feed style.
class MissionRoomMessage extends StatelessWidget {
  const MissionRoomMessage({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.onLongPress,
    required this.onReactionTap,
    this.isContinuation = false,
    this.participantCount = 0,
    this.onRetry,
    this.readers = const {},
    this.player,
    this.onPlayTap,
  });

  final PoolMessageLocal message;
  final String? currentUserId;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final bool isContinuation;
  /// Number of pool participants. ≤ 3 enables iMessage-style bubble layout.
  final int participantCount;
  final VoidCallback? onRetry;
  final Map<String, String?> readers;
  final AudioPlayer? player;
  final VoidCallback? onPlayTap;

  /// True when the pool is small enough for iMessage-style bubble layout.
  bool get _isCompact => participantCount <= 3;

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
              onRetry: onRetry, readers: readers),
          PoolMessageType.voiceNote => _VoiceNoteRow(
              message: message, onLongPress: onLongPress,
              onReactionTap: onReactionTap, currentUserId: currentUserId,
              isContinuation: isContinuation, isCompact: _isCompact,
              onRetry: onRetry, player: player, onPlayTap: onPlayTap,
              readers: readers),
          _ => _TextMessageRow(
              message: message, onLongPress: onLongPress,
              onReactionTap: onReactionTap, currentUserId: currentUserId,
              isContinuation: isContinuation, isCompact: _isCompact,
              onRetry: onRetry, readers: readers),
        },
      ),
    );
  }
}

// ── Delivery status ───────────────────────────────────────────────────────────

class _DeliveryStatus extends StatelessWidget {
  const _DeliveryStatus({required this.status, required this.onRetry});
  final LocalStatus status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    switch (status) {
      case LocalStatus.sending:
        return Icon(SolarIconsBold.clockCircle, size: 12, color: zt.textSecondary.withValues(alpha: 0.5));
      case LocalStatus.delivered:
        return Icon(SolarIconsBold.checkCircle, size: 12, color: zt.textSecondary.withValues(alpha: 0.5));
      case LocalStatus.failed:
        return GestureDetector(
          onTap: onRetry,
          child: const Icon(SolarIconsBold.infoCircle, size: 12, color: ZendColors.destructive),
        );
    }
  }
}

// ── Read receipts ─────────────────────────────────────────────────────────────

class _ReadReceiptAvatars extends StatelessWidget {
  const _ReadReceiptAvatars({required this.readers});
  final Map<String, String?> readers;

  @override
  Widget build(BuildContext context) {
    if (readers.isEmpty) return const SizedBox.shrink();
    final entries = readers.entries.take(3).toList();
    return SizedBox(
      width: entries.length * 12.0 + 4,
      height: 16,
      child: Stack(
        children: [
          for (var i = 0; i < entries.length; i++)
            Positioned(
              left: i * 12.0,
              child: ZendAvatar(
                radius: 8,
                photoUrl: entries[i].value,
                initials: entries[i].key.isNotEmpty ? entries[i].key[0].toUpperCase() : '?',
              ),
            ),
        ],
      ),
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

// ── Text message row ──────────────────────────────────────────────────────────

class _TextMessageRow extends StatelessWidget {
  const _TextMessageRow({
    required this.message, required this.onLongPress,
    required this.onReactionTap, required this.currentUserId,
    this.isContinuation = false, this.isCompact = false,
    this.onRetry, this.readers = const {},
  });

  final PoolMessageLocal message;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final String? currentUserId;
  final bool isContinuation;
  final bool isCompact;
  final VoidCallback? onRetry;
  final Map<String, String?> readers;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final sender = message.senderZendtag ?? '?';
    final avatarLabel = sender.isNotEmpty ? sender[0].toUpperCase() : '?';
    final isMe = message.senderUserId != null && message.senderUserId == currentUserId;

    // Compact (≤3 participants): iMessage-style — mine right, theirs left.
    if (isCompact) {
      final bubbleColor = isMe ? zt.accent : zt.bgSecondary;
      final textColor = isMe ? Colors.white : zt.textPrimary;
      final timeColor = isMe ? Colors.white.withValues(alpha: 0.7) : zt.textSecondary;
      final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;

      return Column(
        crossAxisAlignment: alignment,
        children: [
          if (!isContinuation && !isMe) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text('@$sender', style: TextStyle(fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w600, color: zt.textSecondary)),
            ),
          ],
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe && !isContinuation) ...[
                ZendAvatar(radius: 14, photoUrl: message.senderAvatarUrl, initials: avatarLabel),
                const SizedBox(width: 6),
              ] else if (!isMe && isContinuation) ...[
                const SizedBox(width: 34),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: alignment,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message.content ?? '', style: TextStyle(fontFamily: 'DMSans', fontSize: 14.5, color: textColor, height: 1.35)),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_formatTime(message.createdAt), style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: timeColor)),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            _DeliveryStatus(status: message.localStatus, onRetry: onRetry),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 6),
              ],
            ],
          ),
          if (readers.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: isMe ? 6 : 0, left: isMe ? 0 : 34, top: 2),
              child: _ReadReceiptAvatars(readers: readers),
            ),
          if (message.reactions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 4, left: isMe ? 0 : 34),
              child: _ReactionRow(reactions: message.reactions, currentUserId: currentUserId, onTap: onReactionTap),
            ),
        ],
      );
    }

    // Feed style (larger group): left-aligned, with sender label.
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
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _DeliveryStatus(status: message.localStatus, onRetry: onRetry),
                  if (readers.isNotEmpty) ...[const SizedBox(width: 4), _ReadReceiptAvatars(readers: readers)],
                ]),
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
    this.onRetry, this.readers = const {},
  });

  final PoolMessageLocal message;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final String? currentUserId;
  final VoidCallback? onRetry;
  final Map<String, String?> readers;

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
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (isMe) _DeliveryStatus(status: message.localStatus, onRetry: onRetry),
              if (readers.isNotEmpty) ...[if (isMe) const SizedBox(width: 4), _ReadReceiptAvatars(readers: readers)],
            ]),
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
    this.isContinuation = false, this.isCompact = false,
    this.onRetry, this.player, this.onPlayTap, this.readers = const {},
  });

  final PoolMessageLocal message;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final String? currentUserId;
  final bool isContinuation;
  final bool isCompact;
  final VoidCallback? onRetry;
  final AudioPlayer? player;
  final VoidCallback? onPlayTap;
  final Map<String, String?> readers;

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
    final progress = duration > 0 ? (position.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final displayTime = isPlaying ? _formatDuration(totalDuration - position) : _formatDuration(totalDuration);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isContinuation) const SizedBox(width: 36)
        else ZendAvatar(radius: 18, photoUrl: message.senderAvatarUrl, initials: avatarLabel),
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
              GestureDetector(
                onTap: message.localStatus == LocalStatus.sending ? null : onPlayTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: ZendSpacing.sm, vertical: ZendSpacing.xs),
                  decoration: BoxDecoration(color: zt.bgCard, borderRadius: BorderRadius.circular(ZendRadii.pill)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.localStatus == LocalStatus.sending)
                        ZendLoader(size: 24, strokeWidth: 2, color: zt.accent)
                      else
                        Icon(isPlaying ? SolarIconsBold.pauseCircle : SolarIconsBold.playCircle, size: 28, color: zt.accent),
                      const SizedBox(width: ZendSpacing.xs),
                      SizedBox(
                        width: 80,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(ZendRadii.pill),
                          child: LinearProgressIndicator(
                            value: progress.toDouble(), minHeight: 4,
                            backgroundColor: zt.accentBright.withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(zt.accentBright),
                          ),
                        ),
                      ),
                      const SizedBox(width: ZendSpacing.xs),
                      Text(displayTime, style: TextStyle(fontFamily: 'DMMono', fontSize: 12, color: zt.textSecondary)),
                    ],
                  ),
                ),
              ),
              if (isMe || readers.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isMe) _DeliveryStatus(status: message.localStatus, onRetry: onRetry),
                  if (readers.isNotEmpty) ...[if (isMe) const SizedBox(width: 4), _ReadReceiptAvatars(readers: readers)],
                ]),
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
