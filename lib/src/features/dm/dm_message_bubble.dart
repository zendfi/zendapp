import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';
import '../vibes/vibe_message_bubble.dart';

// ── Corner radius constants ─────────────────────────────────────────────────

/// Outer (far) corner — large, fully rounded.
const double _kOuter = 18.0;

/// Inner (joining) corner — tight, visually fuses grouped bubbles together.
const double _kInner = 4.0;

/// Tail protrusion dimensions.
const double _kTailW = 8.0;   // horizontal extent of the beak triangle
const double _kTailH = 7.0;   // vertical height — shorter = subtler beak

// ── CustomPainter that draws a bubble with a real protruding beak ─────────────
//
// Design rules (from WhatsApp reference + analysis):
//
// 1. Tail position: LAST bubble in a run for BOTH sender and receiver.
//    The tail sits closest to the compose bar — newest message in a turn.
//
// 2. Per-corner radii respond to grouping:
//    Sender (right side):
//      first-in-group: TL=outer, TR=outer (tail here on non-last, inner on non-first)
//      middle: TL=outer, TR=inner, BL=outer, BR=inner
//      last-in-group (tail): TL=outer, TR=inner, BL=outer, BR=0 (tail corner, no arc)
//    Receiver (left side):
//      first-in-group: TL=outer, TR=outer, BL=inner, BR=outer
//      middle: TL=inner, TR=outer, BL=inner, BR=outer
//      last-in-group (tail): TL=inner, TR=outer, BL=0 (tail corner, no arc), BR=outer
//
// 3. Self-intersection fix: the tail corner uses radius 0 (no arc). This
//    prevents the path from drawing an arc and then overlapping it with the
//    beak lines, which produced a faint seam / zero-winding artifact in Skia.

class _BubblePainter extends CustomPainter {
  const _BubblePainter({
    required this.color,
    required this.isMe,
    required this.isFirst,
    required this.isLast,
    this.gradient,
    this.borderColor,
    this.borderWidth = 0,
  });

  final Color color;
  final bool isMe, isFirst, isLast;
  final Gradient? gradient;
  final Color? borderColor;
  final double borderWidth;

  // In a reversed ListView (index 0 = newest = visually BOTTOM):
  // • isFirst = newest in group = visually BOTTOM of the group
  // • isLast  = oldest in group = visually TOP of the group
  //
  // Sender beak: top of the group → isLast (oldest = top)
  // Receiver beak: bottom of the group (next to avatar) → isFirst (newest = bottom)
  bool get _showTail => isMe ? isLast : isFirst;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final showTail = _showTail;

    // The bubble body occupies [bL, bR] horizontally.
    // The gutter (_kTailW) is ALWAYS reserved on the tail side, even on non-tail
    // bubbles — this keeps body edges flush across the whole group.
    // The beak triangle is only drawn when showTail is true; otherwise that
    // strip is left transparent.
    final double bL = !isMe ? _kTailW : 0.0;
    final double bR = isMe  ? w - _kTailW : w;

    // Per-corner radii — inner side tightens for grouped bubbles.
    final double rTL, rTR, rBL, rBR;
    if (isMe) {
      // Sent: right side is the "inner" side.
      // Tail (beak) is on isLast = oldest = visually topmost sent bubble.
      rTL = _kOuter;
      rTR = isLast ? 0.0 : _kInner; // tail corner = 0 on last (top), inner on rest
      rBL = _kOuter;
      rBR = isFirst ? _kOuter : _kInner; // bottom of group stays outer
    } else {
      // Received: left side is the inner side.
      // Tail (beak) is on isFirst = newest = visually bottommost, where avatar is.
      rTL = isLast ? _kOuter : _kInner;  // top of group stays outer
      rTR = _kOuter;
      rBL = isFirst ? 0.0 : _kInner; // tail corner = 0 on first (bottom)
      rBR = _kOuter;
    }

    final path = Path();

    if (isMe) {
      // ── Sent bubble (right-aligned) ──────────────────────────────────
      // Traverse clockwise from top-left:
      path.moveTo(bL + rTL, 0);
      // Top edge →
      path.lineTo(bR - rTR, 0);
      // rTR == 0 when this is the tail bubble — no arc, straight into beak
      if (showTail) {
        // Beak at top-right: protrudes rightward from the top corner
        path.lineTo(bR, 0);        // top-right corner (square, rTR==0)
        path.lineTo(w, 0);         // beak tip at very top-right
        path.lineTo(bR, _kTailH);  // back down to bubble right edge
      } else if (rTR > 0) {
        path.arcToPoint(Offset(bR, rTR),
            radius: Radius.circular(rTR), clockwise: true);
      }
      // Right edge ↓ (starts at _kTailH if tail, else rTR)
      path.lineTo(bR, h - rBR);
      if (rBR > 0) {
        path.arcToPoint(Offset(bR - rBR, h),
            radius: Radius.circular(rBR), clockwise: true);
      }
      // Bottom edge ←
      path.lineTo(bL + rBL, h);
      if (rBL > 0) {
        path.arcToPoint(Offset(bL, h - rBL),
            radius: Radius.circular(rBL), clockwise: true);
      }
      // Left edge ↑
      path.lineTo(bL, rTL);
      if (rTL > 0) {
        path.arcToPoint(Offset(bL + rTL, 0),
            radius: Radius.circular(rTL), clockwise: true);
      }
      path.close();
    } else {
      // ── Received bubble (left-aligned) ──────────────────────────────
      // Traverse clockwise from top-left:
      path.moveTo(bL + rTL, 0);
      // Top edge →
      path.lineTo(bR - rTR, 0);
      if (rTR > 0) {
        path.arcToPoint(Offset(bR, rTR),
            radius: Radius.circular(rTR), clockwise: true);
      }
      // Right edge ↓
      path.lineTo(bR, h - rBR);
      if (rBR > 0) {
        path.arcToPoint(Offset(bR - rBR, h),
            radius: Radius.circular(rBR), clockwise: true);
      }
      // Bottom edge ←
      path.lineTo(bL, h);

      if (showTail) {
        // Tail at bottom-left: beak protrudes leftward from bL
        path.lineTo(bL, h);              // bottom of bubble left edge
        path.lineTo(0, h);               // beak tip (bottom-left)
        path.lineTo(bL, h - _kTailH);   // back up to where beak starts
      }

      // Left edge ↑
      path.lineTo(bL, rTL);
      if (rTL > 0) {
        path.arcToPoint(Offset(bL + rTL, 0),
            radius: Radius.circular(rTL), clockwise: true);
      }
      path.close();
    }

    // Fill
    final fillRect = Rect.fromLTRB(bL, 0, bR, h);
    final paint = Paint()..style = PaintingStyle.fill;
    if (gradient != null) {
      paint.shader = gradient!.createShader(fillRect);
    } else {
      paint.color = color;
    }
    canvas.drawPath(path, paint);

    // Optional border
    if (borderColor != null && borderWidth > 0) {
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..color = borderColor!
        ..strokeWidth = borderWidth);
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.color != color || old.isMe != isMe ||
      old.isFirst != isFirst || old.isLast != isLast ||
      old.gradient != gradient;
}

/// Wraps [child] in a painted bubble with a protruding beak on the correct side.
/// Expands the layout by [_kTailW] on the tail side so the protrusion doesn't
/// overlap the content or get clipped.
class _BubbleShape extends StatelessWidget {
  const _BubbleShape({
    required this.isMe,
    required this.isFirst,
    required this.isLast,
    required this.child,
    required this.color,
    this.gradient,
    this.borderColor,
    this.borderWidth = 0,
  });

  final bool isMe, isFirst, isLast;
  final Widget child;
  final Color color;
  final Gradient? gradient;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    // Gutter is ALWAYS reserved on the tail side for every bubble — not just
    // the tailed one — so all body edges line up flush. The painter only draws
    // the actual beak triangle when showTail is true.
    final leftPad  = !isMe ? _kTailW : 0.0;
    final rightPad = isMe  ? _kTailW : 0.0;
    return CustomPaint(
      painter: _BubblePainter(
        color: color, isMe: isMe, isFirst: isFirst, isLast: isLast,
        gradient: gradient, borderColor: borderColor, borderWidth: borderWidth,
      ),
      child: Padding(
        padding: EdgeInsets.only(left: leftPad, right: rightPad),
        child: child,
      ),
    );
  }
}

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
    this.onReplyTap,
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
  /// Called when the user taps the in-bubble quote block to jump to the
  /// original message. The [DmMessage.replyToContent] is passed for matching.
  final void Function(DmMessage)? onReplyTap;
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
    // Immediate squish on press, springy elastic release.
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),  // fast press-down
    );
    _pressAnim = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.91)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 100),
    ]).animate(_pressCtrl);
  }

  void _onTapDown(TapDownDetails _) {
    _pressCtrl.forward(from: 0);
  }

  void _onTapUp(TapUpDetails _) {
    // Spring back with elastic overshoot on release
    _pressCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 380),
      curve: Curves.elasticOut,
    );
  }

  void _onTapCancel() {
    _pressCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticOut,
    );
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
    final hasReactions = widget.message.reactions.isNotEmpty;

    Widget child = switch (widget.message.type) {
      DmMessageType.payment => DmPaymentBubble(
          message: widget.message, isMe: widget.isMe,
          isFirst: widget.isFirst, isLast: widget.isLast),
      DmMessageType.vibe => _buildVibeBubble(),
      DmMessageType.paymentRequest => DmPaymentRequestBubble(
          message: widget.message, isMe: widget.isMe,
          isFirst: widget.isFirst, isLast: widget.isLast,
          onPay: widget.message.paymentRequestData != null && !widget.isMe
              ? () => widget.onPayRequest?.call(widget.message.paymentRequestData!)
              : null),
      _ => _TextBubble(
          message: widget.message, isMe: widget.isMe,
          isFirst: widget.isFirst, isLast: widget.isLast,
          onRetry: widget.onRetry,
          onReplyTap: widget.onReplyTap != null
              ? () => widget.onReplyTap!(widget.message)
              : null),
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

    // ── WhatsApp-style reaction badge — floats at the BOTTOM corner of the
    // bubble, overlapping its bottom edge by a few px and mostly sitting in
    // the gap toward the next (newer) message below it.
    //
    // IMPORTANT: this Stack must NOT reserve extra layout space for the
    // badge (e.g. via bottom padding on `child`) — this widget is placed
    // inside an `Expanded` cell of a Row that also holds the avatar, and
    // that Row uses `crossAxisAlignment: CrossAxisAlignment.end`. Any extra
    // height added here shifts where "the bottom" is for the whole Row,
    // which drags the avatar down with it, detaching it from the bubble.
    // Using a Positioned child with a *negative* bottom offset lets the
    // badge visually overlap past the bubble's edge without changing the
    // Stack's (and therefore the Row's) reported size — Stack sizes itself
    // to its non-positioned child only.
    //
    // Horizontal anchoring: this widget's own coordinate space starts at its
    // Row's leading gap (4px) then the bubble's tail gutter (_kTailW, 8px)
    // before the visible rounded body — it does NOT include the avatar
    // gutter, which lives in a sibling widget one level up. So both sides
    // use the same `_kTailW + 4` inset from their respective edge.
    if (hasReactions) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            bottom: -10,
            // Anchor to the tail-side corner — bottom-right for sent
            // messages, bottom-left for received.
            right: widget.isMe ? _kTailW + 4 : null,
            left:  widget.isMe ? null : _kTailW + 4,
            child: _ReactionRow(
              reactions: widget.message.reactions,
              onTap: (emoji) => widget.onReactionTap?.call(widget.message, emoji),
            ),
          ),
        ],
      );
    }

    // Swipe-right offset transform — pulls bubble right with spring-back
    if (_swipeDx > 0) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          // Reply icon: always on the LEFT — user drags right, icon peeks out
          // from behind the left edge. Tint accent when threshold reached.
          Positioned(
            left: 0,
            top: 0, bottom: 0,
            child: Opacity(
              opacity: (_swipeDx / 56.0).clamp(0.0, 1.0),
              child: Center(
                child: Icon(
                  SolarIconsBold.reply,
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
    this.onReplyTap,
  });

  final DmMessage message;
  final bool isMe, isFirst, isLast;
  final VoidCallback? onRetry;
  final VoidCallback? onReplyTap;

  bool get _hasReply =>
      (message.replyToContent?.isNotEmpty ?? false) ||
      (message.replyToSenderZendtag?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    final sentGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [zt.accent, Color.lerp(zt.accent, const Color(0xFF1A9E60), 0.18)!],
    );

    // Accent bar colour: white on sent, theme accent on received
    final barColor = isMe ? Colors.white.withValues(alpha: 0.55) : zt.accent;
    // Quote block background
    final quoteBg = isMe
        ? Colors.black.withValues(alpha: 0.28)
        : zt.border.withValues(alpha: 0.5);

    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMe) const SizedBox(width: 4),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
            child: _BubbleShape(
              isMe: isMe,
              isFirst: isFirst,
              isLast: isLast,
              color: isMe ? zt.accent : zt.bgSecondary,
              gradient: isMe ? sentGradient : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Column(
                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_hasReply) ...[
                      _QuoteBlock(
                        senderZendtag: message.replyToSenderZendtag,
                        content: message.replyToContent,
                        barColor: barColor,
                        bgColor: quoteBg,
                        textColor: isMe ? Colors.white.withValues(alpha: 0.85) : zt.textPrimary,
                        labelColor: isMe ? Colors.white.withValues(alpha: 0.7) : zt.accent,
                        isMe: isMe,
                        onTap: onReplyTap,
                      ),
                      const SizedBox(height: 5),
                    ],
                    if (message.displayContent?.isNotEmpty == true)
                      Text(
                        message.displayContent!,
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 16.5,
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
          ),
        ),
        if (isMe) const SizedBox(width: 4),
      ],
    );
  }
}

// ── Quote block — WhatsApp-style in-bubble reply ──────────────────────────────
//
// Design goals (from the screenshot feedback):
// - Fills the full bubble width — no narrow card floating on the left
// - Subtle background tint, not a heavy opaque box
// - Left accent bar is the main visual indicator of "this is a quote"
// - Compact: sender label + 1-2 lines preview, no excessive padding

class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({
    required this.senderZendtag,
    required this.content,
    required this.barColor,
    required this.bgColor,
    required this.textColor,
    required this.labelColor,
    required this.isMe,
    this.onTap,
  });

  final String? senderZendtag;
  final String? content;
  final Color barColor;
  final Color bgColor;
  final Color textColor;
  final Color labelColor;
  /// When true (this is the sender's own bubble), the quote mirrors to the
  /// right: accent bar on the right edge, text right-aligned — matching the
  /// sent-bubble's own right alignment instead of always defaulting to left.
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bar = Container(width: 3, color: barColor);
    final textAlign = isMe ? TextAlign.right : TextAlign.left;
    final crossAlign = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final content_ = Container(
      color: bgColor,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Column(
        crossAxisAlignment: crossAlign,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (senderZendtag != null && senderZendtag!.isNotEmpty)
            Text(
              '@$senderZendtag',
              textAlign: textAlign,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: labelColor,
                height: 1.2,
              ),
            ),
          if (content != null && content!.isNotEmpty) ...[
            if (senderZendtag != null && senderZendtag!.isNotEmpty)
              const SizedBox(height: 1),
            Text(
              content!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
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
    );

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: IntrinsicHeight(
          child: Row(
            // MainAxisSize.min is the key fix here — without it, a Row
            // always reports its OWN width as the full incoming max width
            // regardless of whether its children use Expanded, which forced
            // every reply quote (and therefore the whole bubble, since the
            // bubble's Column sizes to its widest child) to stretch to the
            // maximum allowed bubble width even for short messages. With
            // `min`, the Row (and its non-flex Container child below) sizes
            // to its actual text content instead, capped by the same ambient
            // max-width constraint so long quotes still ellipsize correctly.
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            // Mirror the bar to the trailing edge for the sender's own bubble.
            children: isMe ? [content_, bar] : [bar, content_],
          ),
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 110,
              maxWidth: MediaQuery.of(context).size.width * 0.62,
            ),
            child: _BubbleShape(
              isMe: isMe, isFirst: isFirst, isLast: isLast,
              color: bg,
              borderColor: sentBorder != null ? zt.accent.withValues(alpha: 0.25) : null,
              borderWidth: sentBorder != null ? 0.8 : 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                      style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 28, fontStyle: FontStyle.italic, color: amountColor, height: 1.0),
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
  const DmPaymentRequestBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isFirst = true,
    this.isLast = true,
    this.onPay,
  });
  final DmMessage message;
  final bool isMe;
  final bool isFirst, isLast;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final rd = message.paymentRequestData;
    final amountStr = rd?.amountUsdc ?? '0.00';
    final amountFormatted = '\$${double.tryParse(amountStr)?.toStringAsFixed(2) ?? amountStr}';
    final isPending = rd?.isPending ?? true;

    final bg = isMe ? zt.bgAccentSurface : zt.bgSecondary;
    final hasBorder = isMe;
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 120,
              maxWidth: MediaQuery.of(context).size.width * 0.65,
            ),
            child: _BubbleShape(
              isMe: isMe, isFirst: isFirst, isLast: isLast,
              color: bg,
              borderColor: hasBorder ? zt.accent.withValues(alpha: 0.25) : null,
              borderWidth: hasBorder ? 0.8 : 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(isMe ? SolarIconsBold.billCheck : SolarIconsBold.bill, size: 11, color: accentColor),
                      const SizedBox(width: 3),
                      Text(isMe ? 'you requested' : 'payment request',
                          style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: labelColor, letterSpacing: 0.4)),
                    ]),
                    const SizedBox(height: 2),
                    Text(amountFormatted,
                        style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 28, fontStyle: FontStyle.italic, color: amountColor, height: 1.0)),
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
                            backgroundColor: accentColor, foregroundColor: Colors.white, elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: Text('Pay $amountFormatted', style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      )
                    else if (isMe && isPending)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(SolarIconsBold.clockCircle, size: 11, color: labelColor),
                        const SizedBox(width: 4),
                        Text('Waiting…', style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: labelColor)),
                      ])
                    else if (!isPending)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(SolarIconsBold.checkCircle, size: 13, color: ZendColors.positive),
                        const SizedBox(width: 4),
                        Text('Paid', style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: ZendColors.positive, fontWeight: FontWeight.w600)),
                      ]),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(_formatTime(message.createdAt), style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: labelColor)),
                    ),
                  ],
                ),
              ),
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

/// WhatsApp-inspired reaction badge — a single floating pill/circle anchored
/// to the bottom corner of the bubble, rather than a row of separate chips.
///
/// - Exactly one distinct emoji with a single reactor → a small circle
///   containing just that emoji (matches the 1-on-1 DM screenshots: a plain
///   dark circle with the heart, no count).
/// - Multiple reactors and/or multiple distinct emojis → a pill showing up
///   to 3 emoji glyphs followed by the total reaction count.
///
/// The badge uses the chat background colour (not the bubble colour) with a
/// thin border and soft shadow, so it reads as "punched into" the wallpaper
/// behind the bubble — the same visual trick WhatsApp uses.
class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.reactions, required this.onTap});

  final List<DmReaction> reactions;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final zt = ZendTheme.of(context);
    final totalCount = reactions.fold<int>(0, (sum, r) => sum + r.count);
    final reactedByMe = reactions.any((r) => r.reactedByMe);
    final isSingle = reactions.length == 1 && totalCount == 1;

    final badgeDecoration = BoxDecoration(
      color: zt.bgPrimary,
      borderRadius: BorderRadius.circular(ZendRadii.pill),
      border: Border.all(
        color: reactedByMe
            ? zt.accent.withValues(alpha: 0.55)
            : zt.border.withValues(alpha: 0.5),
        width: reactedByMe ? 1.2 : 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ],
    );

    void handleTap(String emoji) {
      HapticFeedback.selectionClick();
      onTap(emoji);
    }

    if (isSingle) {
      final r = reactions.first;
      return GestureDetector(
        onTap: () => handleTap(r.emoji),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: badgeDecoration,
          child: Text(
            r.emoji,
            style: const TextStyle(fontSize: 14, decoration: TextDecoration.none),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => handleTap(reactions.first.emoji),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: badgeDecoration,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in reactions.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 1),
                child: Text(
                  r.emoji,
                  style: const TextStyle(fontSize: 13, decoration: TextDecoration.none),
                ),
              ),
            const SizedBox(width: 3),
            Text(
              '$totalCount',
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: reactedByMe ? zt.accent : zt.textSecondary,
              ),
            ),
          ],
        ),
      ),
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
