import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';
import '../vibes/vibe_message_bubble.dart';

// ── Corner radius constants ─────────────────────────────────────────────────
//
// Modern WhatsApp/iMessage bubbles no longer use a protruding "beak" tail —
// grouping is communicated purely through asymmetric corner radii: the outer
// (far) corners stay fully rounded, while the inner (joining) corner between
// two bubbles from the same sender tightens up to visually fuse the group
// together. This is both simpler to render (a single RoundedRectangleBorder,
// no CustomPainter/Path math) and closer to what the reference apps actually
// look like today — see the WhatsApp/iMessage screenshots this was checked
// against, neither has a beak anymore.

/// Outer (far) corner — large, fully rounded.
const double _kOuter = 18.0;

/// Inner (joining) corner — tight, visually fuses grouped bubbles together.
const double _kInner = 5.0;

/// Returns the per-corner [BorderRadius] for a bubble at a given position in
/// its sender group.
///
/// In the reversed ListView (index 0 = newest = visually BOTTOM):
///  • isFirst = newest in the group = visually BOTTOM
///  • isLast  = oldest in the group = visually TOP
///
/// The inner corner (the one facing the *next* bubble from the same sender)
/// tightens for any bubble that isn't alone at that edge of the group.
BorderRadius _groupedBorderRadius({required bool isMe, required bool isFirst, required bool isLast}) {
  if (isMe) {
    // Sent: right side is the "inner" side (facing the screen edge is outer
    // on the left, tightened grouping shows on the right).
    return BorderRadius.only(
      topLeft: const Radius.circular(_kOuter),
      topRight: Radius.circular(isLast ? _kOuter : _kInner),
      bottomLeft: const Radius.circular(_kOuter),
      bottomRight: Radius.circular(isFirst ? _kOuter : _kInner),
    );
  }
  // Received: left side is the inner side.
  return BorderRadius.only(
    topLeft: Radius.circular(isLast ? _kOuter : _kInner),
    topRight: const Radius.circular(_kOuter),
    bottomLeft: Radius.circular(isFirst ? _kOuter : _kInner),
    bottomRight: const Radius.circular(_kOuter),
  );
}

/// Wraps [child] in a bubble shape with grouped corner radii. No tail/beak —
/// see the note above [_kOuter].
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
    final radius = _groupedBorderRadius(isMe: isMe, isFirst: isFirst, isLast: isLast);
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: radius,
        border: borderColor != null && borderWidth > 0
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: child,
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
  /// Called on long-press with the bubble's own on-screen bounds (global
  /// coordinates) — used by the caller to anchor the long-press action
  /// overlay's "lift and bounce" animation at the bubble's actual position.
  final void Function(BuildContext, DmMessage, Rect)? onLongPress;
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
  DateTime? _lastTapTime;

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
    // Manual double-tap detection — replaces onDoubleTap to avoid
    // gesture arena delay that made swipe-to-reply feel stuck.
    final now = DateTime.now();
    if (_lastTapTime != null && now.difference(_lastTapTime!).inMilliseconds < 300) {
      HapticFeedback.lightImpact();
      _showHeartPop(context);
      _lastTapTime = null;
    } else {
      _lastTapTime = now;
    }
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
          onRetry: widget.onRetry),
    };

    // ── Reply context (header + quote pill) rendered OUTSIDE/ABOVE the
    // bubble in a vertical stack when the message is a reply.
    final hasReply =
        (widget.message.replyToContent?.isNotEmpty ?? false) ||
        (widget.message.replyToSenderZendtag?.isNotEmpty ?? false);
    if (hasReply) {
      child = Column(
        crossAxisAlignment:
            widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ReplyHeader(
            senderZendtag: widget.message.replyToSenderZendtag,
            isMe: widget.isMe,
          ),
          const SizedBox(height: 4),
          _QuotePill(
            content: widget.message.replyToContent,
            isMe: widget.isMe,
            onTap: widget.onReplyTap != null
                ? () => widget.onReplyTap!(widget.message)
                : null,
          ),
          const SizedBox(height: 4),
          child,
        ],
      );
    }

    // Press feedback + long-press → full reactions
    child = GestureDetector(
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null) return;
        final origin = renderBox.localToGlobal(Offset.zero);
        final rect = Rect.fromLTWH(origin.dx, origin.dy, renderBox.size.width, renderBox.size.height);
        widget.onLongPress?.call(context, widget.message, rect);
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
    // Row's leading gap (4px) — the bubble no longer reserves a tail gutter
    // (see _BubbleShape), so that's the only inset needed before the visible
    // rounded body. It does NOT include the avatar gutter, which lives in a
    // sibling widget one level up.
    if (hasReactions) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            bottom: -10,
            // Anchor to the bubble's near corner: left for received, right for sent.
            left: widget.isMe ? null : 4,
            right: widget.isMe ? 4 : null,
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
                  PhosphorIconsBold.arrowBendUpLeft,
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

    // Timestamp reveal — shown when parent sets showTimestamp = true.
    if (widget.showTimestamp) {
      child = Row(
        mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(child: child),
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Text(
              _exactTime(widget.message.createdAt),
              style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 10, color: ZendTheme.of(context).textSecondary.withValues(alpha: 0.6)),
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
      isFailed: widget.message.localStatus == DmLocalStatus.failed,
      onRetry: widget.onRetry,
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

  /// Whether to show the "Not encrypted" badge. This flags genuinely
  /// plaintext messages — either historical messages from before E2EE
  /// shipped, or messages sent while the counterparty had no pubkey on file.
  ///
  /// Guards against two false positives:
  ///  - `localStatus == sending`: outgoing messages sit optimistically in
  ///    the list while the encryption promise (and E2EE key exchange it
  ///    waits on — see DmThreadScreen._awaitE2eeResolution) is still
  ///    resolving. [DmMessage.isEncrypted] isn't final yet, so don't flag.
  ///  - content still carrying the raw `e2ee:` wire prefix: this message IS
  ///    encrypted but hasn't been decrypted for display yet (async
  ///    key-fetch/history-load race — same one `displayContent` guards
  ///    against). Showing "Not encrypted" here would be actively wrong.
  bool get _showNotEncryptedBadge =>
      !message.isEncrypted &&
      message.localStatus != DmLocalStatus.sending &&
      !(message.content?.startsWith('e2ee:') ?? false);

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    final sentGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [zt.accent, Color.lerp(zt.accent, const Color(0xFF1A9E60), 0.18)!],
    );

    // Sender bubbles align right, recipient bubbles align left.
    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(width: 4),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
            child: _BubbleShape(
              isMe: isMe,
              isFirst: isFirst,
              isLast: isLast,
              color: isMe ? zt.accent : zt.bubbleReceived,
              gradient: isMe ? sentGradient : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isForwarded && !message.isDeleted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIconsBold.arrowBendUpRight,
                              size: 11,
                              color: isMe ? Colors.white.withValues(alpha: 0.65) : zt.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Forwarded',
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                fontSize: 11.5,
                                fontStyle: FontStyle.italic,
                                color: isMe ? Colors.white.withValues(alpha: 0.65) : zt.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (message.isDeleted)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsBold.prohibitInset,
                            size: 13,
                            color: isMe ? Colors.white.withValues(alpha: 0.6) : zt.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'This message was deleted',
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: isMe ? Colors.white.withValues(alpha: 0.6) : zt.textSecondary,
                            ),
                          ),
                        ],
                      )
                    else ...[
                    if (message.displayContent?.isNotEmpty == true)
                      // Timestamp + status float inline at the end of the
                      // text via a trailing WidgetSpan (WhatsApp/iMessage
                      // pattern) instead of always reserving their own row
                      // below the message — a one-line message now stays a
                      // genuinely compact one-line bubble; the meta only
                      // drops to its own line when the text doesn't leave
                      // room on the last line.
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: message.displayContent!,
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                fontSize: 15.5,
                                color: isMe ? Colors.white : zt.textPrimary,
                                height: 1.35,
                                // Message content is arbitrary user text and
                                // can be pure emoji (e.g. "🔥🔥🔥") — without
                                // an explicit decoration/decorationColor,
                                // some platforms render a stray underline
                                // under emoji glyphs.
                                decoration: TextDecoration.none,
                                decorationColor: Colors.transparent,
                              ),
                            ),
                            const WidgetSpan(child: SizedBox(width: 8)),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: _MessageMeta(
                                message: message,
                                isMe: isMe,
                                showNotEncrypted: _showNotEncryptedBadge,
                                onRetry: onRetry,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      // No text content (edge case) — meta still needs
                      // somewhere to render.
                      _MessageMeta(
                        message: message,
                        isMe: isMe,
                        showNotEncrypted: _showNotEncryptedBadge,
                        onRetry: onRetry,
                      ),
                    ], // close the `else` branch of `if (message.isDeleted)`
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

/// Timestamp + encryption badge + delivery status — rendered as a compact
/// inline cluster. Embedded as a trailing [WidgetSpan] inside the message
/// text (see [_TextBubble.build]) so it floats at the end of the last line
/// instead of forcing every bubble to reserve a full extra row, matching how
/// WhatsApp/iMessage keep single-line messages genuinely single-line.
class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    required this.message,
    required this.isMe,
    required this.showNotEncrypted,
    this.onRetry,
  });

  final DmMessage message;
  final bool isMe;
  final bool showNotEncrypted;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showNotEncrypted) ...[
          Icon(
            PhosphorIconsBold.lockKeyOpen,
            size: 10,
            color: isMe ? Colors.white.withValues(alpha: 0.65) : ZendColors.destructive,
          ),
          const SizedBox(width: 3),
          Text(
            'Not encrypted',
            style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 9.5, color: isMe ? Colors.white.withValues(alpha: 0.65) : ZendColors.destructive),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          _formatTime(message.createdAt),
          style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 10, color: isMe ? Colors.white.withValues(alpha: 0.65) : zt.textSecondary),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          _StatusIcon(status: message.localStatus, onRetry: onRetry),
        ],
      ],
    );
  }
}

// ── Reply header — "↩ @bolu replied to you" line above the quote pill ────────

class _ReplyHeader extends StatelessWidget {
  const _ReplyHeader({
    required this.senderZendtag,
    required this.isMe,
  });

  final String? senderZendtag;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final tag = senderZendtag ?? '';

    // Sent: "You replied to @{zendtag}", Received: "@{zendtag} replied to you"
    final label = isMe
        ? 'You replied to @$tag'
        : '@$tag replied to you';

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsBold.arrowBendUpLeft,
            size: 12,
            color: zt.textSecondary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Satoshi',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: zt.textSecondary,
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quote pill — outline-only rounded rect showing the original message ──────

class _QuotePill extends StatelessWidget {
  const _QuotePill({
    required this.content,
    required this.isMe,
    this.onTap,
  });

  final String? content;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    final borderColor = isMe
        ? zt.accent.withValues(alpha: 0.15)
        : zt.border;

    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            content ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Satoshi',
              fontSize: 14,
              color: zt.textSecondary,
              decoration: TextDecoration.none,
              decorationColor: Colors.transparent,
            ),
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
        return Icon(PhosphorIconsBold.clock, size: 11, color: Colors.white.withValues(alpha: 0.6));
      case DmLocalStatus.delivered:
        // Single check — sent/delivered but not yet read. WhatsApp/iMessage
        // both use a single tick for this state, reserving the double tick
        // for "read".
        return Icon(PhosphorIconsBold.check, size: 12, color: Colors.white.withValues(alpha: 0.6));
      case DmLocalStatus.read:
        // Double tick, tinted — the read-receipt state. Uses the app's
        // accentPop colour (not WhatsApp's blue) so it still reads as
        // "seen" while staying on-brand.
        return const Icon(PhosphorIconsBold.checks, size: 13, color: ZendColors.accentPop);
      case DmLocalStatus.failed:
        return GestureDetector(
          onTap: onRetry,
          child: const Icon(PhosphorIconsBold.xCircle, size: 11, color: ZendColors.destructive),
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
    // received uses the same elevated bubbleReceived fill as text bubbles so
    // payment bubbles pop off the chat canvas exactly like text ones. The
    // border on sent creates clear visual separation even when
    // bgAccentSurface is very dark in dark mode.
    final bg = isMe ? zt.bgAccentSurface : zt.bubbleReceived;
    final sentBorder = isMe
        ? Border.all(color: zt.accent.withValues(alpha: 0.25), width: 0.8)
        : null;
    final amountColor = zt.textPrimary;
    final labelColor = zt.textSecondary;
    final noteColor = zt.textPrimary.withValues(alpha: 0.75);
    final iconColor = isMe ? zt.accent : zt.textSecondary;

    // Sender bubbles align right, recipient bubbles align left.
    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(width: 4),
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
                          isMe ? PhosphorIconsBold.arrowSquareUp : PhosphorIconsBold.arrowSquareDown,
                          size: 11, color: iconColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isMe ? 'sent' : 'received',
                          style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 10, color: labelColor, letterSpacing: 0.4),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      amountFormatted,
                      style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 28, color: amountColor, height: 1.0),
                    ),
                    if (note != null && note.isNotEmpty && note != 'vibe') ...[
                      const SizedBox(height: 3),
                      Text(
                        note,
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 12, color: noteColor, decoration: TextDecoration.none, decorationColor: Colors.transparent),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(_formatTime(message.createdAt), style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 10, color: labelColor)),
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

    final bg = isMe ? zt.bgAccentSurface : zt.bubbleReceived;
    final hasBorder = isMe;
    final amountColor = zt.textPrimary;
    final labelColor = zt.textSecondary;
    final noteColor = zt.textPrimary.withValues(alpha: 0.75);
    final accentColor = zt.accent;

    // Sender bubbles align right, recipient bubbles align left.
    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(width: 4),
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
                      Icon(isMe ? PhosphorIconsBold.receiptX : PhosphorIconsBold.receipt, size: 11, color: accentColor),
                      const SizedBox(width: 3),
                      Text(isMe ? 'you requested' : 'payment request',
                          style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 10, color: labelColor, letterSpacing: 0.4)),
                    ]),
                    const SizedBox(height: 2),
                    Text(amountFormatted,
                        style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 28, color: amountColor, height: 1.0)),
                    if (rd?.note != null && rd!.note!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        rd.note!,
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 12, color: noteColor, decoration: TextDecoration.none, decorationColor: Colors.transparent),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                          child: Text('Pay $amountFormatted', style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      )
                    else if (isMe && isPending)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(PhosphorIconsBold.clock, size: 11, color: labelColor),
                        const SizedBox(width: 4),
                        Text('Waiting…', style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 10, color: labelColor)),
                      ])
                    else if (!isPending)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(PhosphorIconsBold.checkCircle, size: 13, color: ZendColors.positive),
                        const SizedBox(width: 4),
                        Text('Paid', style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 11, color: ZendColors.positive, fontWeight: FontWeight.w600)),
                      ]),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(_formatTime(message.createdAt), style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 10, color: labelColor)),
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
///
/// Redesigned to match Telegram's reaction pattern: each distinct emoji
/// gets its OWN small pill chip (not one combined pill listing up to 3
/// emoji + a total count) — a chip shows the emoji alone when only one
/// person reacted with it, or "emoji count" once 2+ people share that
/// reaction. Chips the current user has reacted with get a tinted
/// accent-colored fill; everyone else's get a neutral fill. Multiple
/// distinct emojis lay out as a horizontal row of chips (wrapping if the
/// bubble is narrow), all still anchored to the bubble's bottom corner.
class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.reactions, required this.onTap});

  final List<DmReaction> reactions;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final zt = ZendTheme.of(context);

    void handleTap(String emoji) {
      HapticFeedback.selectionClick();
      onTap(emoji);
    }

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: reactions.map((r) {
        final decoration = BoxDecoration(
          color: r.reactedByMe
              ? zt.accent.withValues(alpha: zt.isDark ? 0.28 : 0.16)
              : zt.chatBg,
          borderRadius: BorderRadius.circular(ZendRadii.pill),
          border: Border.all(
            color: r.reactedByMe
                ? zt.accent.withValues(alpha: 0.6)
                : zt.border.withValues(alpha: 0.5),
            width: r.reactedByMe ? 1.2 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        );

        return GestureDetector(
          onTap: () => handleTap(r.emoji),
          child: Container(
            height: 24,
            padding: EdgeInsets.symmetric(horizontal: r.count > 1 ? 7 : 6),
            decoration: decoration,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r.emoji,
                  style: const TextStyle(fontSize: 13, decoration: TextDecoration.none, decorationColor: Colors.transparent),
                ),
                if (r.count > 1) ...[
                  const SizedBox(width: 3),
                  Text(
                    '${r.count}',
                    style: ZendTextStyles.tabularNumeric.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: r.reactedByMe ? zt.accent : zt.textSecondary,
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
