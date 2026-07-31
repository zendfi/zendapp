import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/pool_message_local.dart';

// ── Corner radius constants (mirrors dm_message_bubble.dart) ─────────────────

const double _kOuter = 18.0;
const double _kInner = 4.0;

/// Per-corner bubble radius matching the dm_message_bubble spec:
/// - Tail (sharp inner) on the LAST bubble for BOTH sender and receiver.
/// - Inner side corners tighten to _kInner on grouped (non-first/non-last) bubbles.
/// - Tail corner uses 0 radius so the beak emerges cleanly.
BorderRadius _bubbleRadius({required bool isMe, required bool isFirst, required bool isLast}) {
  if (isMe) {
    return BorderRadius.only(
      topLeft:     const Radius.circular(_kOuter),
      topRight:    Radius.circular(isFirst ? _kOuter : _kInner),
      bottomLeft:  const Radius.circular(_kOuter),
      bottomRight: Radius.circular(isLast ? _kInner : _kInner),
    );
  } else {
    return BorderRadius.only(
      topLeft:    Radius.circular(isFirst ? _kOuter : _kInner),
      topRight:   const Radius.circular(_kOuter),
      bottomLeft: Radius.circular(isLast ? _kInner : _kInner),
      bottomRight: const Radius.circular(_kOuter),
    );
  }
}

// ── Public widget ─────────────────────────────────────────────────────────────

/// Renders a single pool chat message — styled to match DmThreadScreen's
/// bubble quality: gradient fill on sent, iMessage tail corners, same
/// typography, animated reaction chips, and accent-coloured sender labels.
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
  final void Function(BuildContext ctx) onLongPress;
  final ValueChanged<String> onReactionTap;
  final bool isContinuation;
  final int participantCount;
  final VoidCallback? onRetry;
  final Map<String, String?> readers;
  final AudioPlayer? player;
  final VoidCallback? onPlayTap;

  bool get _isCompact => participantCount <= 3;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => onLongPress(context),
      child: Padding(
        padding: EdgeInsets.only(top: isContinuation ? 2 : 6, bottom: 2),
        child: switch (message.messageTypeEnum) {
          PoolMessageType.contributionEvent => _ContributionEventRow(
              message: message,
              onLongPress: () => onLongPress(context),
              onReactionTap: onReactionTap,
              currentUserId: currentUserId,
              onRetry: onRetry,
              readers: readers),
          PoolMessageType.voiceNote => _VoiceNoteRow(
              message: message,
              onLongPress: () => onLongPress(context),
              onReactionTap: onReactionTap,
              currentUserId: currentUserId,
              isContinuation: isContinuation,
              isCompact: _isCompact,
              onRetry: onRetry,
              player: player,
              onPlayTap: onPlayTap,
              readers: readers),
          _ => _TextMessageRow(
              message: message,
              onLongPress: () => onLongPress(context),
              onReactionTap: onReactionTap,
              currentUserId: currentUserId,
              isContinuation: isContinuation,
              isCompact: _isCompact,
              onRetry: onRetry,
              readers: readers),
        },
      ),
    );
  }
}

// ── Delivery status ───────────────────────────────────────────────────────────

class _DeliveryStatus extends StatelessWidget {
  const _DeliveryStatus({required this.status, required this.onRetry, this.onDark = false});
  final LocalStatus status;
  final VoidCallback? onRetry;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final color = onDark
        ? Colors.white.withValues(alpha: 0.6)
        : ZendTheme.of(context).textSecondary.withValues(alpha: 0.5);
    return switch (status) {
      LocalStatus.sending  => Icon(SolarIconsBold.clockCircle,  size: 11, color: color),
      LocalStatus.delivered => Icon(SolarIconsBold.checkCircle,  size: 11, color: color),
      LocalStatus.failed   => GestureDetector(
        onTap: onRetry,
        child: const Icon(SolarIconsBold.infoCircle, size: 11, color: ZendColors.destructive),
      ),
    };
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

// ── Reaction chips — animated, matches DM style ───────────────────────────────

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
    final zt = ZendTheme.of(context);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: reactions.map((r) {
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap(r.emoji);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: r.reactedByMe
                  ? zt.accent.withValues(alpha: 0.20)
                  : zt.bgSecondary,
              borderRadius: BorderRadius.circular(ZendRadii.pill),
              border: Border.all(
                color: r.reactedByMe
                    ? zt.accent.withValues(alpha: 0.5)
                    : zt.border.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.emoji, style: const TextStyle(fontSize: 13, decoration: TextDecoration.none)),
                if (r.count > 1) ...[
                  const SizedBox(width: 3),
                  Text(
                    '${r.count}',
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 11,
                      color: r.reactedByMe ? zt.accent : zt.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Sender label colours — unique per-user accent ─────────────────────────────

/// Returns a stable accent colour for a sender tag — cycles through a small
/// palette so each participant in the pool gets their own distinct colour.
Color _senderColor(String zendtag, ZendTheme zt) {
  const palette = [
    Color(0xFF4ADE80), // green (matches zt.accent on dark)
    Color(0xFF60A5FA), // blue
    Color(0xFFF472B6), // pink
    Color(0xFFFBBF24), // amber
    Color(0xFFA78BFA), // violet
    Color(0xFF34D399), // emerald
    Color(0xFFFB923C), // orange
  ];
  final idx = zendtag.codeUnits.fold(0, (a, b) => a + b) % palette.length;
  return palette[idx];
}

// ── Text message row ──────────────────────────────────────────────────────────

class _TextMessageRow extends StatelessWidget {
  const _TextMessageRow({
    required this.message,
    required this.onLongPress,
    required this.onReactionTap,
    required this.currentUserId,
    this.isContinuation = false,
    this.isCompact = false,
    this.onRetry,
    this.readers = const {},
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
    final sender   = message.senderZendtag ?? '?';
    final initial  = sender.isNotEmpty ? sender[0].toUpperCase() : '?';
    final isMe     = message.senderUserId != null && message.senderUserId == currentUserId;
    final labelColor = _senderColor(sender, zt);

    // ── Compact (≤ 3 people): iMessage-style bubbles ──────────────────────
    if (isCompact) {
      final decoration = isMe
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [zt.accent, Color.lerp(zt.accent, const Color(0xFF1A9E60), 0.18)!],
              ),
              borderRadius: _bubbleRadius(isMe: true, isFirst: !isContinuation, isLast: true),
            )
          : BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: _bubbleRadius(isMe: false, isFirst: !isContinuation, isLast: true),
            );
      final textColor  = isMe ? Colors.white : zt.textPrimary;
      final timeColor  = isMe ? Colors.white.withValues(alpha: 0.65) : zt.textSecondary;

      return Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Sender label — only on first bubble in a run, for other people
          if (!isContinuation && !isMe)
            Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 2),
              child: Text(
                '@$sender',
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar slot — 32px wide, avatar only on group-end
              if (!isMe) SizedBox(
                width: 32,
                child: !isContinuation
                    ? ZendAvatar(radius: 13, photoUrl: message.senderAvatarUrl, initials: initial)
                    : null,
              ),
              // Bubble
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.74,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: decoration,
                  child: Column(
                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.content ?? '',
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          fontSize: 15,
                          color: textColor,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(message.createdAt),
                            style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: timeColor),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            _DeliveryStatus(status: message.localStatus, onRetry: onRetry, onDark: true),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (isMe) const SizedBox(width: 4),
            ],
          ),
          // Read receipts
          if (readers.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                right: isMe ? 8 : 0,
                left: isMe ? 0 : 36,
                top: 2,
              ),
              child: _ReadReceiptAvatars(readers: readers),
            ),
          // Reaction chips
          if (message.reactions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 4, left: isMe ? 0 : 36, right: isMe ? 8 : 0),
              child: _ReactionRow(reactions: message.reactions, currentUserId: currentUserId, onTap: onReactionTap),
            ),
        ],
      );
    }

    // ── Feed style (> 3 people): left-aligned, avatar + label above ───────
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isContinuation)
          const SizedBox(width: 40)
        else
          ZendAvatar(radius: 18, photoUrl: message.senderAvatarUrl, initials: initial),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isContinuation) ...[
                Row(children: [
                  Text(
                    '@$sender',
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary),
                  ),
                ]),
                const SizedBox(height: 2),
              ],
              Text(
                message.content ?? '',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 15, color: zt.textPrimary, height: 1.4),
              ),
              if (isMe || readers.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isMe) _DeliveryStatus(status: message.localStatus, onRetry: onRetry),
                  if (readers.isNotEmpty) ...[
                    if (isMe) const SizedBox(width: 4),
                    _ReadReceiptAvatars(readers: readers),
                  ],
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

// ── Contribution event row ────────────────────────────────────────────────────
// Displayed as a centered pill — contribution events are system notices,
// not user messages, so they don't get a bubble or sender label.

class _ContributionEventRow extends StatelessWidget {
  const _ContributionEventRow({
    required this.message,
    required this.onLongPress,
    required this.onReactionTap,
    required this.currentUserId,
    this.onRetry,
    this.readers = const {},
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
    return Column(
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: zt.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(ZendRadii.pill),
              border: Border.all(color: zt.accent.withValues(alpha: 0.22), width: 0.8),
            ),
            child: Text(
              message.content ?? '',
              style: TextStyle(
                fontFamily: 'Satoshi',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: zt.accent,
              ),
            ),
          ),
        ),
        if (message.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: _ReactionRow(reactions: message.reactions, currentUserId: currentUserId, onTap: onReactionTap),
            ),
          ),
      ],
    );
  }
}

// ── Voice note row ────────────────────────────────────────────────────────────

class _VoiceNoteRow extends StatelessWidget {
  const _VoiceNoteRow({
    required this.message,
    required this.onLongPress,
    required this.onReactionTap,
    required this.currentUserId,
    this.isContinuation = false,
    this.isCompact = false,
    this.onRetry,
    this.player,
    this.onPlayTap,
    this.readers = const {},
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
    final sender  = message.senderZendtag ?? '?';
    final initial = sender.isNotEmpty ? sender[0].toUpperCase() : '?';
    final isMe    = message.senderUserId != null && message.senderUserId == currentUserId;
    final dur     = message.voiceNoteDurationSeconds ?? 0;

    final isPlaying  = player?.playing ?? false;
    final position   = player?.position ?? Duration.zero;
    final total      = Duration(seconds: dur);
    final progress   = dur > 0 ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final timeLabel  = isPlaying ? _formatDuration(total - position) : _formatDuration(total);

    // The playback pill — same in both compact and feed layouts
    final pill = GestureDetector(
      onTap: message.localStatus == LocalStatus.sending ? null : onPlayTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? zt.accent : zt.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.localStatus == LocalStatus.sending)
              ZendLoader(size: 22, strokeWidth: 2, color: isMe ? Colors.white : zt.accent)
            else
              Icon(
                isPlaying ? SolarIconsBold.pauseCircle : SolarIconsBold.playCircle,
                size: 26,
                color: isMe ? Colors.white : zt.accent,
              ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(ZendRadii.pill),
                child: LinearProgressIndicator(
                  value: progress.toDouble(),
                  minHeight: 3,
                  backgroundColor: (isMe ? Colors.white : zt.accent).withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation<Color>(isMe ? Colors.white : zt.accent),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              timeLabel,
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 11,
                color: isMe ? Colors.white.withValues(alpha: 0.8) : zt.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: isCompact && isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!(isCompact && isMe)) ...[
          if (isContinuation)
            const SizedBox(width: 40)
          else
            ZendAvatar(radius: 18, photoUrl: message.senderAvatarUrl, initials: initial),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: isCompact && isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isContinuation && !(isCompact && isMe))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Text(
                      '@$sender',
                      style: TextStyle(fontFamily: 'DMMono', fontSize: 12, fontWeight: FontWeight.w600, color: _senderColor(sender, zt)),
                    ),
                    const SizedBox(width: 6),
                    Text(_formatTime(message.createdAt), style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary)),
                  ]),
                ),
              pill,
              if (isMe || readers.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isMe) _DeliveryStatus(status: message.localStatus, onRetry: onRetry, onDark: isMe),
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
        if (isCompact && isMe) const SizedBox(width: 4),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'now';
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  if (diff.inDays < 1) return '$h:$m';
  if (diff.inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[(dt.weekday - 1).clamp(0, 6)]} $h:$m';
  }
  return '${dt.month}/${dt.day}';
}

String _formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
