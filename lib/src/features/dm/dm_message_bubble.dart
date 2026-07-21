import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';
import '../vibes/vibe_message_bubble.dart';

/// Renders a single DM message — text, payment bubble, or Vibe.
///
/// Always uses iMessage-style layout (DM threads are always 2 people):
/// - Mine (isMe): right-aligned, accent bubble
/// - Theirs (!isMe): left-aligned, bgSecondary bubble
class DmMessageBubble extends StatelessWidget {
  const DmMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isContinuation = false,
    this.onRetry,
  });

  final DmMessage message;
  final bool isMe;
  final bool isContinuation;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: isContinuation ? 2 : 6,
        bottom: 2,
      ),
      child: switch (message.type) {
        DmMessageType.payment => DmPaymentBubble(
            message: message, isMe: isMe),
        DmMessageType.vibe => _buildVibeBubble(),
        _ => _TextBubble(
            message: message,
            isMe: isMe,
            isContinuation: isContinuation,
            onRetry: onRetry,
          ),
      },
    );
  }

  Widget _buildVibeBubble() {
    final vd = message.vibeData;
    if (vd == null) {
      return DmPaymentBubble(message: message, isMe: isMe);
    }
    return VibeMessageBubble(
      emoji: vd.stickerSlug.isNotEmpty ? vd.stickerSlug : '✨',
      amountUsdc: double.tryParse(vd.amountUsdc) ?? 0.0,
      senderLabel: message.senderZendtag ?? '',
      isMine: isMe,
      createdAt: message.createdAt,
    );
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.message,
    required this.isMe,
    required this.isContinuation,
    this.onRetry,
  });

  final DmMessage message;
  final bool isMe;
  final bool isContinuation;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final bubbleColor = isMe ? zt.accent : zt.bgSecondary;
    final textColor = isMe ? Colors.white : zt.textPrimary;
    final timeColor = isMe
        ? Colors.white.withValues(alpha: 0.7)
        : zt.textSecondary;

    // Tail corner: bottom-right for mine, bottom-left for theirs
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : (isContinuation ? 10 : 4)),
      bottomRight: Radius.circular(isMe ? (isContinuation ? 10 : 4) : 18),
    );

    return Row(
      mainAxisAlignment:
          isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMe) const SizedBox(width: 8),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: borderRadius,
            ),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.content?.isNotEmpty == true)
                  Text(
                    message.content!,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 14.5,
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
                      style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 10,
                        color: timeColor,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _StatusIcon(
                          status: message.localStatus,
                          onRetry: onRetry),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        if (isMe) const SizedBox(width: 8),
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, this.onRetry});
  final DmLocalStatus status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case DmLocalStatus.sending:
        return Icon(SolarIconsBold.clockCircle,
            size: 11, color: Colors.white.withValues(alpha: 0.6));
      case DmLocalStatus.delivered:
        return Icon(SolarIconsBold.checkCircle,
            size: 11, color: Colors.white.withValues(alpha: 0.6));
      case DmLocalStatus.failed:
        return GestureDetector(
          onTap: onRetry,
          child: const Icon(SolarIconsBold.closeCircle,
              size: 11, color: ZendColors.destructive),
        );
    }
  }
}

/// Payment and Vibe bubble — used for `payment` and `vibe` message types.
class DmPaymentBubble extends StatelessWidget {
  const DmPaymentBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  final DmMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final pd = message.paymentData;
    final amountStr = pd?.amountUsdc ?? '0.00';
    final note = pd?.note;
    final isSent = pd?.direction == 'sent' || isMe;

    return Row(
      mainAxisAlignment:
          isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!isMe) const SizedBox(width: 8),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: zt.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(ZendRadii.xl),
              border: Border.all(
                color: zt.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSent
                          ? SolarIconsBold.squareArrowRightUp
                          : SolarIconsBold.squareArrowLeftDown,
                      size: 16,
                      color: isSent ? zt.textSecondary : ZendColors.positive,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isSent ? 'Sent' : 'Received',
                      style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 11,
                        color: zt.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '\$$amountStr',
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 24,
                    fontStyle: FontStyle.italic,
                    color: zt.textPrimary,
                  ),
                ),
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: zt.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 10,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isMe) const SizedBox(width: 8),
      ],
    );
  }
}

String _formatTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'now';
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  if (diff.inDays < 1) return '$h:$m';
  if (diff.inDays < 7) return '${_weekday(dt.weekday)} $h:$m';
  return '${dt.month}/${dt.day}';
}

String _weekday(int w) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return days[(w - 1).clamp(0, 6)];
}
