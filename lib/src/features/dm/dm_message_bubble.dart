import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';
import '../vibes/vibe_message_bubble.dart';

// ── Corner radius constants ─────────────────────────────────────────────────

/// Full outer radius — always applied to the "far" corners.
const double _kOuter = 20.0;

/// Compressed inner radius — for the "near" corners in a grouped run.
/// Gives the iMessage look: soft overall, but tight at group joints.
const double _kInner = 5.0;

/// Tail radius — the very bottom corner that "points" toward the sender avatar.
const double _kTail = 4.0;

/// Computes the 4-corner BorderRadius for a bubble given its position in a
/// message group:
///   [isMe]    — right-aligned (sent) if true
///   [isFirst] — first (topmost) bubble in a consecutive run from same sender
///   [isLast]  — last (bottommost) bubble — gets the tail corner
///
/// When grouped, inner corners compress to [_kInner] so adjacent bubbles in
/// the same run visually merge. The tail only appears on [isLast].
BorderRadius _bubbleRadius({
  required bool isMe,
  required bool isFirst,
  required bool isLast,
}) {
  if (isMe) {
    // Right side: tail is bottom-right, inner side is right
    return BorderRadius.only(
      topLeft: const Radius.circular(_kOuter),
      topRight: Radius.circular(isFirst ? _kOuter : _kInner),
      bottomLeft: const Radius.circular(_kOuter),
      bottomRight: Radius.circular(isLast ? _kTail : _kInner),
    );
  } else {
    // Left side: tail is bottom-left, inner side is left
    return BorderRadius.only(
      topLeft: Radius.circular(isFirst ? _kOuter : _kInner),
      topRight: const Radius.circular(_kOuter),
      bottomLeft: Radius.circular(isLast ? _kTail : _kInner),
      bottomRight: const Radius.circular(_kOuter),
    );
  }
}

// ── Main bubble widget ───────────────────────────────────────────────────────

/// Renders a single DM message with iMessage-style grouped corners,
/// gradient fills, bounce animation on arrival, and press feedback.
class DmMessageBubble extends StatefulWidget {
  const DmMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isContinuation = false,
    this.isFirst = true,
    this.isLast = true,
    this.onRetry,
    this.onPayRequest,
    this.onLongPress,
  });

  final DmMessage message;
  final bool isMe;

  /// True if this is NOT the first in a run (i.e. same sender, short gap above).
  /// When true the top inner corner is compressed.
  final bool isContinuation;

  /// True if this is the first bubble in a consecutive run (topmost).
  final bool isFirst;

  /// True if this is the last bubble in a consecutive run (gets the tail).
  final bool isLast;

  final VoidCallback? onRetry;
  final void Function(DmPaymentRequestData)? onPayRequest;
  final void Function(BuildContext, DmMessage, Offset)? onLongPress;

  @override
  State<DmMessageBubble> createState() => _DmMessageBubbleState();
}

class _DmMessageBubbleState extends State<DmMessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arrivalCtrl;
  late final Animation<double> _scaleAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _arrivalCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    // Spring-like bounce: overshoot then settle
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.05).chain(CurveTween(curve: Curves.easeOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 0.97).chain(CurveTween(curve: Curves.easeInOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.97, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 25),
    ]).animate(_arrivalCtrl);

    // Animate only on fresh (sending) messages
    if (widget.message.localStatus == DmLocalStatus.sending) {
      _arrivalCtrl.forward();
    } else {
      _arrivalCtrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _arrivalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = widget.isContinuation ? 2.0 : 8.0;

    Widget child = switch (widget.message.type) {
      DmMessageType.payment => DmPaymentBubble(
          message: widget.message, isMe: widget.isMe,
          isFirst: widget.isFirst, isLast: widget.isLast),
      DmMessageType.vibe => _buildVibeBubble(),
      DmMessageType.paymentRequest => DmPaymentRequestBubble(
          message: widget.message, isMe: widget.isMe,
          onPay: widget.message.paymentRequestData != null && !widget.isMe
              ? () => widget.onPayRequest?.call(widget.message.paymentRequestData!)
              : null),
      _ => _TextBubble(
          message: widget.message, isMe: widget.isMe,
          isFirst: widget.isFirst, isLast: widget.isLast,
          onRetry: widget.onRetry),
    };

    // Press feedback + long-press → reactions
    child = GestureDetector(
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        widget.onLongPress?.call(context, widget.message, details.globalPosition);
      },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), () { if (mounted) setState(() => _pressed = false); }),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: child,
      ),
    );

    // Arrival bounce
    child = AnimatedBuilder(
      animation: _scaleAnim,
      builder: (ctx, c) => Transform.scale(
        scale: _scaleAnim.value,
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: c,
      ),
      child: child,
    );

    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: 1),
      child: child,
    );
  }

  Widget _buildVibeBubble() {
    final vd = widget.message.vibeData;
    if (vd == null) return DmPaymentBubble(message: widget.message, isMe: widget.isMe, isFirst: widget.isFirst, isLast: widget.isLast);
    return VibeMessageBubble(
      emoji: vd.displayEmoji,
      amountUsdc: double.tryParse(vd.amountUsdc) ?? 0.0,
      isMine: widget.isMe,
      createdAt: widget.message.createdAt,
      isDelivering: widget.message.localStatus == DmLocalStatus.sending,
    );
  }
}

// ── Text bubble ──────────────────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.message, required this.isMe,
    required this.isFirst, required this.isLast,
    this.onRetry,
  });

  final DmMessage message;
  final bool isMe, isFirst, isLast;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final radius = _bubbleRadius(isMe: isMe, isFirst: isFirst, isLast: isLast);

    // Sent: subtle gradient from accent top to slightly darker bottom
    // Received: flat surface
    final decoration = isMe
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                zt.accent,
                Color.lerp(zt.accent, const Color(0xFF1A9E60), 0.18)!,
              ],
            ),
            borderRadius: radius,
          )
        : BoxDecoration(color: zt.bgSecondary, borderRadius: radius);

    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMe) const SizedBox(width: 4),
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.content?.isNotEmpty == true)
                  Text(
                    message.content!,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      color: isMe ? Colors.white : zt.textPrimary,
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
                        color: isMe ? Colors.white.withValues(alpha: 0.65) : zt.textSecondary,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _StatusIcon(status: message.localStatus, onRetry: onRetry),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        if (isMe) const SizedBox(width: 4),
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
        return Icon(SolarIconsBold.clockCircle, size: 11, color: Colors.white.withValues(alpha: 0.6));
      case DmLocalStatus.delivered:
        return Icon(SolarIconsBold.checkCircle, size: 11, color: Colors.white.withValues(alpha: 0.6));
      case DmLocalStatus.failed:
        return GestureDetector(
          onTap: onRetry,
          child: const Icon(SolarIconsBold.closeCircle, size: 11, color: ZendColors.destructive),
        );
    }
  }
}

// ── Payment bubble — iMessage-style ──────────────────────────────────────────
//
// The bubble *is* the payment. Same tail corner geometry as a text bubble.
// Strong opaque fill so the amount pops against the chat background.
// Sent: deep forest green. Received: near-black charcoal.
// Amount is the dominant element — everything else whispers.

class DmPaymentBubble extends StatelessWidget {
  const DmPaymentBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isFirst = true,
    this.isLast = true,
  });

  final DmMessage message;
  final bool isMe, isFirst, isLast;

  @override
  Widget build(BuildContext context) {
    final pd = message.paymentData;
    final amountStr = pd?.amountUsdc ?? '0.00';
    final note = pd?.note;
    final amountFormatted = '\$${double.tryParse(amountStr)?.toStringAsFixed(2) ?? amountStr}';

    // Same tail corner logic as text bubbles — uses the shared _bubbleRadius helper
    final borderRadius = _bubbleRadius(isMe: isMe, isFirst: isFirst, isLast: isLast);

    // Sent: deep forest green. Received: near-black with blue undertone.
    final bg = isMe
        ? const Color(0xFF1B5E35)
        : const Color(0xFF1A1A2E);
    const amountColor = Colors.white;
    final labelColor = Colors.white.withValues(alpha: 0.5);
    final noteColor = Colors.white.withValues(alpha: 0.75);

    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMe) const SizedBox(width: 4),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              minWidth: 110,
              maxWidth: MediaQuery.of(context).size.width * 0.62,
            ),
            decoration: BoxDecoration(color: bg, borderRadius: borderRadius),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Direction — small, muted, top
                Text(
                  isMe ? '↗ sent' : '↙ received',
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: labelColor, letterSpacing: 0.4),
                ),
                const SizedBox(height: 3),
                // Amount — the whole point, large and white
                Text(
                  amountFormatted,
                  style: const TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 36,
                    fontStyle: FontStyle.italic,
                    color: amountColor,
                    height: 1.0,
                  ),
                ),
                // Note — only if user-authored
                if (note != null && note.isNotEmpty && note != 'vibe') ...[
                  const SizedBox(height: 4),
                  Text(note, style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: noteColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(_formatTime(message.createdAt), style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: labelColor)),
                ),
              ],
            ),
          ),
        ),
        if (isMe) const SizedBox(width: 4),
      ],
    );
  }
}

// ── Payment request bubble ───────────────────────────────────────────────────

class DmPaymentRequestBubble extends StatelessWidget {
  const DmPaymentRequestBubble({super.key, required this.message, required this.isMe, this.onPay});
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
    const purple = Color(0xFF6C63FF);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: isMe ? 60 : 4, right: isMe ? 4 : 60, top: 2, bottom: 2),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
          decoration: BoxDecoration(
            color: purple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(_kOuter),
            border: Border.all(color: purple.withValues(alpha: 0.28), width: 1),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(SolarIconsBold.squareArrowRightDown, size: 13, color: purple),
                const SizedBox(width: 4),
                Text(isMe ? 'You requested' : 'Payment request',
                  style: const TextStyle(fontFamily: 'DMMono', fontSize: 11, color: purple, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              Text(amountFormatted, style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 28,
                fontStyle: FontStyle.italic, color: zt.textPrimary, height: 1.1)),
              if (rd?.note != null && rd!.note!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(rd.note!, style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: zt.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 10),
              if (!isMe && isPending && onPay != null)
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: onPay,
                  style: ElevatedButton.styleFrom(backgroundColor: purple, foregroundColor: Colors.white, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
                    padding: const EdgeInsets.symmetric(vertical: 10)),
                  child: Text('Pay $amountFormatted', style: const TextStyle(fontFamily: 'DMSans', fontSize: 14, fontWeight: FontWeight.w700)),
                ))
              else if (isMe && isPending)
                Text('Waiting for payment…', style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary))
              else if (!isPending)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(SolarIconsBold.checkCircle, size: 13, color: ZendColors.positive),
                  const SizedBox(width: 4),
                  Text('Paid', style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: ZendColors.positive, fontWeight: FontWeight.w600)),
                ]),
              const SizedBox(height: 6),
              Text(_formatTime(message.createdAt), style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: zt.textSecondary.withValues(alpha: 0.6))),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

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
