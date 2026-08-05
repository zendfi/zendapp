import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';

/// Emoji set for the quick-reaction row — matches the existing DM reaction
/// tray so long-press reactions stay consistent across both entry points.
const _kReactionEmojis = ['🔥', '❤️', '😂', '👏', '🙏', '😭', '💸', '✅'];

/// Actions available from the long-press action menu. Not every action is
/// always shown — e.g. Copy only appears for text messages, Delete only for
/// the current user's own messages.
class DmMessageActions {
  const DmMessageActions({
    this.onReply,
    this.onForward,
    this.onCopy,
    this.onInfo,
    this.onDelete,
  });

  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onCopy;
  final VoidCallback? onInfo;
  final VoidCallback? onDelete;
}

/// Shows the iMessage/WhatsApp-style long-press action overlay for a
/// message bubble: the tapped bubble lifts and bounces to a focused
/// position, the background blurs, a quick-reaction row appears above it,
/// and an action menu (Reply / Forward / Copy / Info / Delete) appears
/// below it.
///
/// [originRect] is the on-screen rect of the bubble at the moment of the
/// long-press (from the RenderBox the gesture fired on) — the animation
/// starts there and settles into a position that leaves room for the
/// reaction row and menu, rather than jumping straight to a fixed spot.
/// [previewBuilder] renders the actual bubble content (typically the same
/// bubble widget used inline, wrapped so it's non-interactive here).
void showMessageActionOverlay(
  BuildContext context, {
  required DmMessage message,
  required bool isMe,
  required Rect originRect,
  required WidgetBuilder previewBuilder,
  required void Function(String emoji) onReactionTap,
  required DmMessageActions actions,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayCtx) => _MessageActionOverlay(
      message: message,
      isMe: isMe,
      originRect: originRect,
      previewBuilder: previewBuilder,
      onReactionTap: onReactionTap,
      actions: actions,
      onDismiss: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _MessageActionOverlay extends StatefulWidget {
  const _MessageActionOverlay({
    required this.message,
    required this.isMe,
    required this.originRect,
    required this.previewBuilder,
    required this.onReactionTap,
    required this.actions,
    required this.onDismiss,
  });

  final DmMessage message;
  final bool isMe;
  final Rect originRect;
  final WidgetBuilder previewBuilder;
  final void Function(String emoji) onReactionTap;
  final DmMessageActions actions;
  final VoidCallback onDismiss;

  @override
  State<_MessageActionOverlay> createState() => _MessageActionOverlayState();
}

class _MessageActionOverlayState extends State<_MessageActionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _entrance; // bubble position/scale + blur
  late final Animation<double> _menuFade; // reaction row + menu fade/slide
  bool _dismissing = false;

  // Layout constants for the menu/reaction row — used both for building
  // them and for computing the target bubble rect so everything fits
  // on-screen without clipping.
  static const double _reactionRowHeight = 52.0;
  static const double _reactionRowGap = 10.0;
  static const double _menuGap = 10.0;
  static const double _menuItemHeight = 46.0;
  static const double _screenEdgePadding = 14.0;

  int get _menuItemCount {
    final a = widget.actions;
    var count = 0;
    if (a.onReply != null) count++;
    if (a.onForward != null) count++;
    if (a.onCopy != null) count++;
    if (a.onInfo != null) count++;
    if (a.onDelete != null) count++;
    return count;
  }

  double get _menuHeight => _menuItemCount * _menuItemHeight;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 320), vsync: this);
    _entrance = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _menuFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );
    HapticFeedback.mediumImpact();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss([VoidCallback? then]) async {
    if (_dismissing) return;
    _dismissing = true;
    await _ctrl.animateBack(0, duration: const Duration(milliseconds: 220), curve: Curves.easeInCubic);
    widget.onDismiss();
    then?.call();
  }

  /// Computes the bubble's target rect — same horizontal position/width as
  /// [originRect] (so it doesn't jump sideways), but with a vertical
  /// position adjusted so the reaction row above and the action menu below
  /// both fit on-screen with [_screenEdgePadding] of breathing room.
  Rect _targetRect(Size screenSize, double topSafeArea, double bottomSafeArea) {
    final origin = widget.originRect;
    final minTop = topSafeArea + _screenEdgePadding + _reactionRowHeight + _reactionRowGap;
    final maxTop = screenSize.height -
        bottomSafeArea -
        _screenEdgePadding -
        _menuGap -
        _menuHeight -
        origin.height;
    var top = origin.top;
    if (minTop > maxTop) {
      // Not enough vertical room for both — prioritize keeping the menu
      // fully visible (more important than perfectly preserving position).
      top = maxTop.clamp(topSafeArea + _screenEdgePadding, screenSize.height);
    } else {
      top = top.clamp(minTop, maxTop);
    }
    return Rect.fromLTWH(origin.left, top, origin.width, origin.height);
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final target = _targetRect(screenSize, safeTop, safeBottom);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _entrance.value;
        final rect = Rect.lerp(widget.originRect, target, t)!;
        // Slight overshoot scale for the "bounce" feel — peaks just before
        // settling, mirrors the bubble's own arrival-bounce curve elsewhere
        // in this feature.
        final bounce = t < 1.0 ? 1.0 + (0.04 * (1 - t) * t * 4) : 1.0;

        return Stack(
          children: [
            // ── Blurred + dimmed backdrop ──────────────────────────────
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _dismiss(),
                behavior: HitTestBehavior.opaque,
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 18 * t,
                    sigmaY: 18 * t,
                  ),
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.18 * t)),
                ),
              ),
            ),

            // ── Reaction row — anchored above the bubble's target position ──
            Positioned(
              left: 16,
              right: 16,
              top: target.top - _reactionRowGap - _reactionRowHeight,
              child: Opacity(
                opacity: _menuFade.value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.85 + 0.15 * _menuFade.value.clamp(0.0, 1.0),
                  alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: _ReactionPickerRow(
                    message: widget.message,
                    onTap: (emoji) {
                      widget.onReactionTap(emoji);
                      _dismiss();
                    },
                  ),
                ),
              ),
            ),

            // ── The bubble itself — animates from origin to target ──────
            Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: Transform.scale(
                scale: bounce,
                child: IgnorePointer(child: widget.previewBuilder(context)),
              ),
            ),

            // ── Action menu — anchored below the bubble's target position ──
            Positioned(
              left: widget.isMe ? null : target.left,
              right: widget.isMe ? screenSize.width - target.right : null,
              top: target.top + target.height + _menuGap,
              width: 220,
              child: Opacity(
                opacity: _menuFade.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 8 * (1 - _menuFade.value.clamp(0.0, 1.0))),
                  child: _ActionMenu(
                    zt: zt,
                    actions: widget.actions,
                    onAction: (action) => _dismiss(action),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Quick-reaction row ───────────────────────────────────────────────────────

class _ReactionPickerRow extends StatelessWidget {
  const _ReactionPickerRow({required this.message, required this.onTap});
  final DmMessage message;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: zt.bgElevated,
          borderRadius: BorderRadius.circular(ZendRadii.pill),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _kReactionEmojis.map((e) {
            final alreadyReacted = message.reactions.any((r) => r.emoji == e && r.reactedByMe);
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap(e);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                decoration: alreadyReacted
                    ? BoxDecoration(color: zt.accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(ZendRadii.pill))
                    : null,
                child: Text(e, style: TextStyle(fontSize: alreadyReacted ? 22 : 24)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Action menu ──────────────────────────────────────────────────────────────

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({required this.zt, required this.actions, required this.onAction});
  final ZendTheme zt;
  final DmMessageActions actions;
  final void Function(VoidCallback action) onAction;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    void addItem(String label, IconData icon, VoidCallback? action, {bool destructive = false}) {
      if (action == null) return;
      if (items.isNotEmpty) items.add(Divider(height: 1, color: zt.border.withValues(alpha: 0.5)));
      final color = destructive ? ZendColors.destructive : zt.textPrimary;
      items.add(
        InkWell(
          onTap: () => onAction(action),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 15, color: color),
                  ),
                ),
                Icon(icon, size: 18, color: color),
              ],
            ),
          ),
        ),
      );
    }

    addItem('Reply', PhosphorIconsBold.arrowBendUpLeft, actions.onReply);
    addItem('Forward', PhosphorIconsBold.arrowBendUpRight, actions.onForward);
    addItem('Copy', PhosphorIconsBold.copy, actions.onCopy);
    addItem('Info', PhosphorIconsBold.info, actions.onInfo);
    addItem('Delete', PhosphorIconsBold.trash, actions.onDelete, destructive: true);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: zt.bgElevated,
          borderRadius: BorderRadius.circular(ZendRadii.lg),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: items),
      ),
    );
  }
}
