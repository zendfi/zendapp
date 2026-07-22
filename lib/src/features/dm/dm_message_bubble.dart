  import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';
import '../vibes/vibe_message_bubble.dart';

/// Renders a single DM message — text, payment bubble, Vibe, or payment request.
class DmMessageBubble extends StatelessWidget {
  const DmMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isContinuation = false,
    this.onRetry,
    this.onPayRequest,
  });

  final DmMessage message;
  final bool isMe;
  final bool isContinuation;
  final VoidCallback? onRetry;
  /// Called when the recipient taps "Pay" on a payment request bubble.
  final void Function(DmPaymentRequestData)? onPayRequest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: isContinuation ? 2 : 6,
        bottom: 2,
      ),
      child: switch (message.type) {
        DmMessageType.payment => DmPaymentBubble(message: message, isMe: isMe),
        DmMessageType.vibe => _buildVibeBubble(),
        DmMessageType.paymentRequest => DmPaymentRequestBubble(
            message: message,
            isMe: isMe,
            onPay: message.paymentRequestData != null && !isMe
                ? () => onPayRequest?.call(message.paymentRequestData!)
                : null,
          ),
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
      emoji: vd.displayEmoji,
      amountUsdc: double.tryParse(vd.amountUsdc) ?? 0.0,
      isMine: isMe,
      createdAt: message.createdAt,
      isDelivering: message.localStatus == DmLocalStatus.sending,
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

/// Payment bubble — clean, minimal card for payment messages.
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
    final isSent = isMe;
    final amountFormatted = '\$${double.tryParse(amountStr)?.toStringAsFixed(2) ?? amountStr}';

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isSent ? 60 : 12,
          right: isSent ? 12 : 60,
          top: 4,
          bottom: 4,
        ),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
          decoration: BoxDecoration(
            color: isSent
                ? zt.accent.withValues(alpha: 0.1)
                : zt.bgSecondary,
            borderRadius: BorderRadius.circular(ZendRadii.xl),
            border: Border.all(
              color: isSent
                  ? zt.accent.withValues(alpha: 0.3)
                  : zt.border.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Direction label
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSent
                        ? SolarIconsBold.squareArrowRightUp
                        : SolarIconsBold.squareArrowLeftDown,
                    size: 13,
                    color: isSent ? zt.textSecondary : ZendColors.positive,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isSent ? 'Sent' : 'Received',
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 11,
                      color: isSent ? zt.textSecondary : ZendColors.positive,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Amount
              Text(
                amountFormatted,
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 28,
                  fontStyle: FontStyle.italic,
                  color: zt.textPrimary,
                  height: 1.1,
                ),
              ),
              // Note
              if (note != null && note.isNotEmpty && note != 'vibe') ...[
                const SizedBox(height: 4),
                Text(
                  note,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: zt.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // Timestamp
              const SizedBox(height: 6),
              Text(
                _formatTime(message.createdAt),
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 10,
                  color: zt.textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Payment request bubble — sent by requester, shows "Pay" CTA to recipient.
class DmPaymentRequestBubble extends StatelessWidget {
  const DmPaymentRequestBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onPay,
  });

  final DmMessage message;
  final bool isMe;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final rd = message.paymentRequestData;
    final amountStr = rd?.amountUsdc ?? '0.00';
    final amountFormatted = '\$${double.tryParse(amountStr)?.toStringAsFixed(2) ?? amountStr}';
    final isPending = rd?.isPending ?? true;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 60 : 12,
          right: isMe ? 12 : 60,
          top: 4,
          bottom: 4,
        ),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(ZendRadii.xl),
            border: Border.all(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Label
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(SolarIconsBold.squareArrowRightDown, size: 13, color: Color(0xFF6C63FF)),
                  const SizedBox(width: 4),
                  Text(
                    isMe ? 'You requested' : 'Payment request',
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 11,
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Amount
              Text(
                amountFormatted,
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 28,
                  fontStyle: FontStyle.italic,
                  color: zt.textPrimary,
                  height: 1.1,
                ),
              ),
              if (rd?.note != null && rd!.note!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  rd.note!,
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: zt.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              // Pay button (only for recipient on pending requests)
              if (!isMe && isPending && onPay != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onPay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      'Pay $amountFormatted',
                      style: const TextStyle(fontFamily: 'DMSans', fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              else if (isMe && isPending)
                Text(
                  'Waiting for payment…',
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary),
                )
              else if (!isPending)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(SolarIconsBold.checkCircle, size: 13, color: ZendColors.positive),
                    const SizedBox(width: 4),
                    Text(
                      'Paid',
                      style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: ZendColors.positive, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Text(
                _formatTime(message.createdAt),
                style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: zt.textSecondary.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
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
