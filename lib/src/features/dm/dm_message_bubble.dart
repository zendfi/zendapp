import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';
import '../vibes/vibe_message_bubble.dart';

// ── Corner radius constants ─────────────────────────────────────────────────

/// Full outer radius — always applied to all corners.
const double _kOuter = 20.0;

/// Tail radius — the sharp "beak" corner that points toward the sender.
const double _kTail = 4.0;

/// Computes the 4-corner BorderRadius for a bubble given its position in a
/// message group — asymmetric per the design spec:
///
/// Sender (right):
///   • FIRST bubble in the run → sharp top-right corner (the "beak/tail")
///   • All other bubbles in the run → all corners fully rounded
///
/// Receiver (left):
///   • LAST bubble in the run → sharp bottom-left corner (the "beak/tail"),
///     aligned with the avatar that only appears on this bubble
///   • All other bubbles in the run → all corners fully rounded
///
/// Non-grouped (solo) messages are both isFirst AND isLast simultaneously,
/// so they get the tail on the correct corner with everything else rounded.
BorderRadius _bubbleRadius({
  required bool isMe,
  required bool isFirst,
  required bool isLast,
}) {
  if (isMe) {
    // Sent: tail (sharp corner) only at top-right of the FIRST bubble
    return BorderRadius.only(
      topLeft:     const Radius.circular(_kOuter),
      topRight:    Radius.circular(isFirst ? _kTail : _kOuter),
      bottomLeft:  const Radius.circular(_kOuter),
      bottomRight: const Radius.circular(_kOuter),
    );
  } else {
    // Received: tail (sharp corner) only at bottom-left of the LAST bubble
    return BorderRadius.only(
      topLeft:     const Radius.circular(_kOuter),
      topRight:    const Radius.circular(_kOuter),
      bottomLeft:  Radius.circular(isLast ? _kTail : _kOuter),
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
    this.onReply,
    this.onReactionTap,
    this.showTimestamp = false,
  });

  final DmMessage message;
  final bool isMe;
  final bool isContinuation;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onRetry;
  final void Function(DmPaymentRequestData)? onPayRequest;
  final void Function(BuildContext, DmMessage, Offset)? onLongPress;
  /// Called when the user swipes right to reply to this message.
  final void Function(DmMessage)? onReply;
  /// Called when the user taps a reaction chip directly — carries the emoji
  /// so the caller can toggle it without reopening the full emoji tray.
  final void Function(DmMessage, String emoji)? onReactionTap;
  /// When true, the exact timestamp is shown (revealed by left-edge swipe).
  final bool showTimestamp;

  @override
  State<DmMessageBubble> createState() => _DmMessageBubbleState();
}

class _DmMessageBubbleState extends State<DmMessageBubble>
    with TickerProviderStateMixin {
  late final AnimationController _arrivalCtrl;
  late final Animation<double> _scaleAnim;
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressAnim;
  double _swipeDx = 0.0;
  bool _replyTriggered = false;
  OverlayEntry? _heartOverlay;

  void _showHeartPop(BuildContext ctx) {
    _heartOverlay?.remove();
    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final center = Offset(offset.dx + size.width / 2, offset.dy + size.height / 2);
    final overlay = Overlay.of(ctx);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _HeartPopup(
      position: center,
      onDone: () { entry.remove(); _heartOverlay = null; },
    ));
    _heartOverlay = entry;
    overlay.insert(entry);
  }

  @override
  void initState() {
    super.initState();

    // ── Arrival bounce ────────────────────────────────────────────────────
    // Plays on:
    //   • Outgoing optimistic messages (localStatus == sending)
    //   • Incoming WS messages (id does NOT start with 'local-', newly created)
    // Skipped for messages loaded from history (isContinuation implied by
    // the fact that they were already in the cache when the screen opened).
    _arrivalCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    // Spring pop: fast scale-up with overshoot, then settle.
    // Starts from 0.0 so the bubble literally pops in from nothing.
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.08)
              .chain(CurveTween(curve: Curves.easeOutCubic)),
          weight: 60),
      TweenSequenceItem(
          tween: Tween(begin: 1.08, end: 0.95)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 20),
      TweenSequenceItem(
          tween: Tween(begin: 0.95, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 20),
    ]).animate(_arrivalCtrl);

    final shouldAnimate = widget.message.localStatus == DmLocalStatus.sending ||
        (!widget.message.id.startsWith('local-') &&
         widget.message.createdAt.isAfter(DateTime.now().subtract(const Duration(seconds: 3))));

    if (shouldAnimate) {
      _arrivalCtrl.forward();
    } else {
      _arrivalCtrl.value = 1.0;
    }

    // ── Press spring ──────────────────────────────────────────────────────
    // Quick squish down then springy release — feels physical.
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _pressAnim = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.93)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: 0.93, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 50),
    ]).animate(_pressCtrl);
  }

  void _onTapDown(TapDownDetails _) {
    _pressCtrl.forward(from: 0);
  }

  void _onTapUp(TapUpDetails _) {
    // Spring releases naturally through the animation
  }

  void _onTapCancel() {
    _pressCtrl.reverse();
  }

  @override
  void dispose() {
    _arrivalCtrl.dispose();
    _pressCtrl.dispose();
    _heartOverlay?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = widget.isContinuation ? 1.0 : 5.0;

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

    // Press feedback + double-tap heart + long-press → full reactions
    child = GestureDetector(
      onDoubleTap: () {
        HapticFeedback.lightImpact();
        _showHeartPop(context);
      },
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        widget.onLongPress?.call(context, widget.message, details.globalPosition);
      },
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      // Swipe right → reply
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx > 0 && widget.onReply != null) {
          setState(() {
            _swipeDx = (_swipeDx + details.delta.dx).clamp(0.0, 72.0);
          });
          if (_swipeDx >= 56 && !_replyTriggered) {
            _replyTriggered = true;
            HapticFeedback.lightImpact();
          }
        }
      },
      onHorizontalDragEnd: (_) {
        if (_replyTriggered) {
          widget.onReply?.call(widget.message);
        }
        setState(() {
          _swipeDx = 0.0;
          _replyTriggered = false;
        });
      },
      onHorizontalDragCancel: () => setState(() { _swipeDx = 0.0; _replyTriggered = false; }),
      // Press spring wraps the child directly
      child: AnimatedBuilder(
        animation: _pressAnim,
        builder: (ctx, c) => Transform.scale(
          scale: _pressAnim.value,
          alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: c,
        ),
        child: child,
      ),
    );

    // Swipe-right offset transform — pulls bubble right with spring-back
    if (_swipeDx > 0) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          // Reply icon revealed behind the bubble
          Positioned(
            left: widget.isMe ? null : 0,
            right: widget.isMe ? 0 : null,
            top: 0, bottom: 0,
            child: Opacity(
              opacity: (_swipeDx / 56.0).clamp(0.0, 1.0),
              child: Center(
                child: Icon(
                  SolarIconsBold.altArrowLeft,
                  size: 18,
                  color: _replyTriggered
                      ? ZendTheme.of(context).accent
                      : ZendTheme.of(context).textSecondary,
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_swipeDx, 0),
            child: child,
          ),
        ],
      );
    }

    // Timestamp reveal — shown when parent sets showTimestamp = true
    if (widget.showTimestamp) {
      child = Row(
        mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (widget.isMe)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: Text(
                _exactTime(widget.message.createdAt),
                style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: ZendTheme.of(context).textSecondary.withValues(alpha: 0.6)),
              ),
            ),
          Flexible(child: child),
          if (!widget.isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(
                _exactTime(widget.message.createdAt),
                style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: ZendTheme.of(context).textSecondary.withValues(alpha: 0.6)),
              ),
            ),
        ],
      );
    }

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
      child: Column(
        crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          // ── Reaction chips ─────────────────────────────────────────────
          if (widget.message.reactions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: 4,
                left: widget.isMe ? 0 : 36,
                right: widget.isMe ? 8 : 0,
              ),
              child: _ReactionRow(
                reactions: widget.message.reactions,
                // Direct toggle — no tray, just flip the emoji immediately
                onTap: (emoji) => widget.onReactionTap?.call(widget.message, emoji),
              ),
            ),
        ],
      ),
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

  bool get _hasReply =>
      (message.replyToContent?.isNotEmpty ?? false) ||
      (message.replyToSenderZendtag?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final radius = _bubbleRadius(isMe: isMe, isFirst: isFirst, isLast: isLast);

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

    // Accent bar colour: white on sent, theme accent on received
    final barColor = isMe
        ? Colors.white.withValues(alpha: 0.55)
        : zt.accent;

    // Quote block background: enough contrast to be readable inside the bubble
    final quoteBg = isMe
        ? Colors.black.withValues(alpha: 0.28)
        : zt.border.withValues(alpha: 0.5);

    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMe) const SizedBox(width: 4),
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Quote block ──────────────────────────────────────────
                if (_hasReply) ...[
                  SizedBox(
                    width: double.infinity,
                    child: _QuoteBlock(
                      senderZendtag: message.replyToSenderZendtag,
                      content: message.replyToContent,
                      barColor: barColor,
                      bgColor: quoteBg,
                      textColor: isMe
                          ? Colors.white.withValues(alpha: 0.85)
                          : zt.textPrimary,
                      labelColor: isMe
                          ? Colors.white.withValues(alpha: 0.6)
                          : zt.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                // ── Message body ─────────────────────────────────────────
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

// ── Quote block — WhatsApp-style in-bubble reply ──────────────────────────────

class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({
    required this.senderZendtag,
    required this.content,
    required this.barColor,
    required this.bgColor,
    required this.textColor,
    required this.labelColor,
  });

  final String? senderZendtag;
  final String? content;
  final Color barColor;
  final Color bgColor;
  final Color textColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent bar — the hallmark of a quoted reply
            Container(width: 3, color: barColor),
            // Quote content
            Flexible(
              child: Container(
                color: bgColor,
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (senderZendtag != null && senderZendtag!.isNotEmpty)
                      Text(
                        '@$senderZendtag',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: labelColor,
                          height: 1.2,
                        ),
                      ),
                    if (content != null && content!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        content!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: textColor,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
    final zt = ZendTheme.of(context);
    final pd = message.paymentData;
    final amountStr = pd?.amountUsdc ?? '0.00';
    final note = pd?.note;
    final amountFormatted = '\$${double.tryParse(amountStr)?.toStringAsFixed(2) ?? amountStr}';
    final borderRadius = _bubbleRadius(isMe: isMe, isFirst: isFirst, isLast: isLast);

    // Monochromatic: sent uses the accent surface with a hairline accent border,
    // received uses bgSecondary. The border on sent creates clear visual
    // separation even when bgAccentSurface is very dark in dark mode.
    final bg = isMe ? zt.bgAccentSurface : zt.bgSecondary;
    final sentBorder = isMe
        ? Border.all(color: zt.accent.withValues(alpha: 0.25), width: 0.8)
        : null;
    final amountColor = zt.textPrimary;
    final labelColor = zt.textSecondary;
    final noteColor = zt.textPrimary.withValues(alpha: 0.75);
    final iconColor = isMe ? zt.accent : zt.textSecondary;

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
            decoration: BoxDecoration(
              color: bg,
              borderRadius: borderRadius,
              border: sentBorder,
            ),
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Direction — icon + label
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMe ? SolarIconsBold.squareArrowRightUp : SolarIconsBold.squareArrowRightDown,
                      size: 11, color: iconColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isMe ? 'sent' : 'received',
                      style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: labelColor, letterSpacing: 0.4),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  amountFormatted,
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 28,
                    fontStyle: FontStyle.italic,
                    color: amountColor,
                    height: 1.0,
                  ),
                ),
                if (note != null && note.isNotEmpty && note != 'vibe') ...[
                  const SizedBox(height: 3),
                  Text(note, style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: noteColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 4),
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
//
// Matches the visual weight of DmPaymentBubble: opaque fill, amount dominant,
// same tail-corner geometry. Purple accent for "request" vs green for "sent".

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
    final borderRadius = _bubbleRadius(isMe: isMe, isFirst: true, isLast: true);

    // Monochromatic: same surface as payment bubble, with accent border on sent
    final bg = isMe ? zt.bgAccentSurface : zt.bgSecondary;
    final sentBorder = isMe
        ? Border.all(color: zt.accent.withValues(alpha: 0.25), width: 0.8)
        : null;
    final amountColor = zt.textPrimary;
    final labelColor = zt.textSecondary;
    final noteColor = zt.textPrimary.withValues(alpha: 0.75);
    final accentColor = zt.accent;

    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMe) const SizedBox(width: 4),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              minWidth: 120,
              maxWidth: MediaQuery.of(context).size.width * 0.65,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: borderRadius,
              border: sentBorder,
            ),
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Direction label with icon
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMe ? SolarIconsBold.billCheck : SolarIconsBold.bill,
                      size: 11, color: accentColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isMe ? 'you requested' : 'payment request',
                      style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: labelColor, letterSpacing: 0.4),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  amountFormatted,
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 28,
                    fontStyle: FontStyle.italic,
                    color: amountColor,
                    height: 1.0,
                  ),
                ),
                if (rd?.note != null && rd!.note!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(rd.note!, style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: noteColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),
                if (!isMe && isPending && onPay != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onPay,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text('Pay $amountFormatted', style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  )
                else if (isMe && isPending)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(SolarIconsBold.clockCircle, size: 11, color: labelColor),
                      const SizedBox(width: 4),
                      Text('Waiting…', style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: labelColor)),
                    ],
                  )
                else if (!isPending)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(SolarIconsBold.checkCircle, size: 13, color: ZendColors.positive),
                      const SizedBox(width: 4),
                      Text('Paid', style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: ZendColors.positive, fontWeight: FontWeight.w600)),
                    ],
                  ),
                const SizedBox(height: 4),
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

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Exact HH:MM timestamp for the "swipe left to reveal" feature.
String _exactTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
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

// ── Reaction row ──────────────────────────────────────────────────────────────

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.reactions, required this.onTap});

  final List<DmReaction> reactions;
  final void Function(String emoji) onTap;

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
                  ? zt.accent.withValues(alpha: 0.2)
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

// ── Heart popup — double-tap reaction ────────────────────────────────────────

class _HeartPopup extends StatefulWidget {
  const _HeartPopup({required this.position, required this.onDone});
  final Offset position;
  final VoidCallback onDone;

  @override
  State<_HeartPopup> createState() => _HeartPopupState();
}

class _HeartPopupState extends State<_HeartPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  late final Animation<double> _rise;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3).chain(CurveTween(curve: Curves.elasticOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
    ]).animate(_ctrl);
    _opacity = TweenSequence([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 40),
    ]).animate(_ctrl);
    _rise = Tween<double>(begin: 0, end: -40)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.4, 1.0, curve: Curves.easeOut)));

    _ctrl.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.position.dx - 24,
      top: widget.position.dy - 24,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (ctx, _) => Transform.translate(
            offset: Offset(0, _rise.value),
            child: Opacity(
              opacity: _opacity.value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: _scale.value,
                child: const Text('❤️', style: TextStyle(fontSize: 42, decoration: TextDecoration.none)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
