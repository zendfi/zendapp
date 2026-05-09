import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';
import 'pool.dart';

class MissionRoomMessage extends StatelessWidget {
  const MissionRoomMessage({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.onLongPress,
    required this.onReactionTap,
  });

  final PoolMessage message;
  final String? currentUserId;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: switch (message.messageType) {
          PoolMessageType.contributionEvent => _ContributionEventRow(
              message: message,
              onLongPress: onLongPress,
              onReactionTap: onReactionTap,
              currentUserId: currentUserId,
            ),
          PoolMessageType.voiceNote => _VoiceNoteRow(
              message: message,
              onLongPress: onLongPress,
              onReactionTap: onReactionTap,
              currentUserId: currentUserId,
            ),
          _ => _TextMessageRow(
              message: message,
              onLongPress: onLongPress,
              onReactionTap: onReactionTap,
              currentUserId: currentUserId,
            ),
        },
      ),
    );
  }
}

class _TextMessageRow extends StatelessWidget {
  const _TextMessageRow({
    required this.message,
    required this.onLongPress,
    required this.onReactionTap,
    required this.currentUserId,
  });

  final PoolMessage message;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final sender = message.senderZendtag ?? '?';
    final avatarLabel = sender.isNotEmpty ? sender[0].toUpperCase() : '?';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: ZendColors.bgSecondary,
          child: Text(
            avatarLabel,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ZendColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: ZendSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '@$sender',
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ZendColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: ZendSpacing.xs),
                  Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 11,
                      color: ZendColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                message.content ?? '',
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: ZendColors.textPrimary,
                  height: 1.4,
                ),
              ),
              if (message.reactions.isNotEmpty) ...[
                const SizedBox(height: 4),
                _ReactionRow(
                  reactions: message.reactions,
                  currentUserId: currentUserId,
                  onTap: onReactionTap,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ContributionEventRow extends StatelessWidget {
  const _ContributionEventRow({
    required this.message,
    required this.onLongPress,
    required this.onReactionTap,
    required this.currentUserId,
  });

  final PoolMessage message;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: ZendSpacing.sm, vertical: ZendSpacing.xs),
      decoration: BoxDecoration(
        color: ZendColors.accentBright.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZendRadii.md),
        border: Border.all(color: ZendColors.accentBright.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  message.content ?? '',
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ZendColors.textPrimary,
                  ),
                ),
              ),
              Text(
                _formatTime(message.createdAt),
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 11,
                  color: ZendColors.textSecondary,
                ),
              ),
            ],
          ),
          if (message.reactions.isNotEmpty) ...[
            const SizedBox(height: 4),
            _ReactionRow(
              reactions: message.reactions,
              currentUserId: currentUserId,
              onTap: onReactionTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _VoiceNoteRow extends StatelessWidget {
  const _VoiceNoteRow({
    required this.message,
    required this.onLongPress,
    required this.onReactionTap,
    required this.currentUserId,
  });

  final PoolMessage message;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final sender = message.senderZendtag ?? '?';
    final avatarLabel = sender.isNotEmpty ? sender[0].toUpperCase() : '?';
    final duration = message.voiceNoteDurationSeconds ?? 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: ZendColors.bgSecondary,
          child: Text(
            avatarLabel,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ZendColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: ZendSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '@$sender',
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ZendColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: ZendSpacing.xs),
                  Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 11,
                      color: ZendColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Voice note player row
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: ZendSpacing.sm, vertical: ZendSpacing.xs),
                decoration: BoxDecoration(
                  color: ZendColors.bgSecondary,
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_outline,
                      size: 24,
                      color: ZendColors.accent,
                    ),
                    const SizedBox(width: ZendSpacing.xs),
                    // Waveform placeholder
                    Container(
                      width: 80,
                      height: 20,
                      decoration: BoxDecoration(
                        color: ZendColors.accentBright.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                    ),
                    const SizedBox(width: ZendSpacing.xs),
                    Text(
                      '${duration}s',
                      style: const TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 12,
                        color: ZendColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (message.reactions.isNotEmpty) ...[
                const SizedBox(height: 4),
                _ReactionRow(
                  reactions: message.reactions,
                  currentUserId: currentUserId,
                  onTap: onReactionTap,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({
    required this.reactions,
    required this.currentUserId,
    required this.onTap,
  });

  final List<PoolReactionCount> reactions;
  final String? currentUserId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: reactions.map((r) {
        return GestureDetector(
          onTap: () => onTap(r.emoji),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: r.reactedByMe
                  ? ZendColors.accentBright.withValues(alpha: 0.2)
                  : ZendColors.bgSecondary,
              borderRadius: BorderRadius.circular(ZendRadii.pill),
              border: Border.all(
                color: r.reactedByMe
                    ? ZendColors.accentBright.withValues(alpha: 0.5)
                    : ZendColors.border,
              ),
            ),
            child: Text(
              '${r.emoji} ${r.count}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );
      }).toList(),
    );
  }
}

String _formatTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  return '${dt.month}/${dt.day}';
}
