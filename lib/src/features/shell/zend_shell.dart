import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../models/payment_request_notification.dart';
import '../../services/pending_deep_link_service.dart';
import '../activity/activity_screen.dart';
import '../receive/receive_screen.dart';
import '../send/qr_payment_sheet.dart';
import '../send/send_flow_sheet.dart';
import '../send/send_screen.dart';
import '../send/withdraw_sheet.dart';
import '../money/home_screen.dart';
import 'package:solar_icons/solar_icons.dart';

class ZendShell extends StatefulWidget {
  const ZendShell({super.key});

  @override
  State<ZendShell> createState() => _ZendShellState();
}

class _ZendShellState extends State<ZendShell> {
  // Start on the Send tab (index 1) — the primary action in Zend.
  int _tabIndex = 1;
  Timer? _bannerTimer;
  // Tracks the last notification ID so re-arrival of a new request
  // forces the banner widget to rebuild and replay the slide-in animation.
  String? _lastBannerRequestId;
  Timer? _reactionBannerTimer;
  String? _lastReactionBannerKey;
  Timer? _commentBannerTimer;
  String? _lastCommentBannerKey;

  @override
  void initState() {
    super.initState();
    // Consume any pending deep link that was stored before the user
    // completed device unlock (PIN screen). The shell is the first
    // authenticated screen, so this is the right place to pick it up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pendingIntent = PendingDeepLinkService.consume();
      if (pendingIntent == null) return;
      showQrPaymentSheet(context, intent: pendingIntent);
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _reactionBannerTimer?.cancel();
    _commentBannerTimer?.cancel();
    super.dispose();
  }

  void _setTab(int index) {
    if (index == _tabIndex) return;
    setState(() {
      _tabIndex = index;
    });
  }

  void _dismissBanner(ZendAppModel model) {
    _bannerTimer?.cancel();
    model.clearPendingPaymentRequest();
  }

  void _dismissReactionBanner(ZendAppModel model) {
    _reactionBannerTimer?.cancel();
    model.clearPendingActivityReaction();
  }

  void _dismissCommentBanner(ZendAppModel model) {
    _commentBannerTimer?.cancel();
    model.clearPendingActivityComment();
  }

  void _payFromBanner(BuildContext context, ZendAppModel model, PaymentRequestNotification notification) {
    _dismissBanner(model);
    showSendFlowSheet(
      context,
      amount: notification.amountUsdc,
      prefilledRecipient: notification.requesterZendtag,
      prefilledNote: notification.description,
    );
  }

  Future<void> _openRecipientSheet(BuildContext context, double amount) {
    return showSendFlowSheet(context, amount: amount);
  }

  void _openReceiveScreen(BuildContext context) {
    final model = ZendScope.of(context);
    Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReceiveScreen(username: model.username),
      ),
    ).then((openSend) {
      if (openSend == true && mounted) {
        _setTab(1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final pending = model.pendingPaymentRequest;
    final pendingReaction = model.pendingActivityReaction;

    // Start auto-dismiss timer when a new notification arrives
    if (pending != null) {
      // Only reset the timer when it's a genuinely new request — avoids
      // restarting the countdown on every rebuild triggered by other state changes.
      if (pending.requestId != _lastBannerRequestId) {
        _lastBannerRequestId = pending.requestId;
        _bannerTimer?.cancel();
        // 12 s gives users enough time to notice and act.
        _bannerTimer = Timer(const Duration(seconds: 12), () {
          if (mounted) model.clearPendingPaymentRequest();
        });
      }
    } else {
      _lastBannerRequestId = null;
    }

    if (pendingReaction != null) {
      final key = '${pendingReaction.edgeKind}:${pendingReaction.edgeId}:${pendingReaction.emoji}:${pendingReaction.reactorZendtag}';
      if (key != _lastReactionBannerKey) {
        _lastReactionBannerKey = key;
        _reactionBannerTimer?.cancel();
        _reactionBannerTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) model.clearPendingActivityReaction();
        });
      }
    } else {
      _lastReactionBannerKey = null;
    }

    final pendingComment = model.pendingActivityComment;
    if (pendingComment != null) {
      final key = '${pendingComment.edgeKind}:${pendingComment.edgeId}:${pendingComment.body}';
      if (key != _lastCommentBannerKey) {
        _lastCommentBannerKey = key;
        _commentBannerTimer?.cancel();
        _commentBannerTimer = Timer(const Duration(seconds: 6), () {
          if (mounted) model.clearPendingActivityComment();
        });
      }
    } else {
      _lastCommentBannerKey = null;
    }

    final pages = <Widget>[
      HomeScreen(
        onOpenReceive: () => _openReceiveScreen(context),
        onOpenWithdraw: () => showWithdrawSheet(context),
        onViewAll: () => _setTab(2),
      ),
      SendScreen(
        onOpenRecipients: (amount) => _openRecipientSheet(context, amount),
      ),
      const ActivityScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _tabIndex,
            children: pages,
          ),
          // In-app payment request banner
          if (pending != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _PaymentRequestBanner(
                // Key on requestId so a new request always replays the animation
                key: ValueKey(pending.requestId),
                notification: pending,
                onPay: () => _payFromBanner(context, model, pending),
                onDismiss: () => _dismissBanner(model),
              ),
            ),
          // In-app "someone reacted to your activity" banner — stacked
          // below the payment-request banner if both are present.
          if (pendingReaction != null)
            Positioned(
              top: pending != null ? 78 : 0,
              left: 0,
              right: 0,
              child: _ActivityReactionBanner(
                key: ValueKey(_lastReactionBannerKey),
                notification: pendingReaction,
                onDismiss: () => _dismissReactionBanner(model),
              ),
            ),
          // In-app "someone commented on your activity" banner — stacked
          // below whichever of the above banners are present.
          if (pendingComment != null)
            Positioned(
              top: (pending != null ? 78 : 0) + (pendingReaction != null ? 78 : 0),
              left: 0,
              right: 0,
              child: _ActivityCommentBanner(
                key: ValueKey(_lastCommentBannerKey),
                notification: pendingComment,
                onDismiss: () => _dismissCommentBanner(model),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ZendBottomBar(
        currentIndex: _tabIndex,
        onChanged: _setTab,
      ),
    );
  }
}

class ZendBottomBar extends StatelessWidget {
  const ZendBottomBar({super.key, required this.currentIndex, required this.onChanged});

  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // On the send tab (index 1), the screen background is forest green (bgDeep).
    // Match the nav bar to it so there's no jarring color break at the bottom.
    final onSendTab = currentIndex == 1;
    final bgColor = onSendTab ? ZendColors.bgDeep : const Color(0xFF0D0D0D);
    final borderColor = onSendTab ? Colors.transparent : const Color(0xFF2A2A2A);

    // Use SafeArea-driven height so the bar sits above the system nav gesture
    // area on all devices — both gesture-nav and 3-button-nav, with or without
    // the system nav bar visible.
    return ColoredBox(
      color: bgColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: borderColor),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _BottomNavIcon(
                    icon: SolarIconsBold.wallet,
                    active: currentIndex == 0,
                    onTap: () => onChanged(0),
                    onDeepBg: onSendTab,
                  ),
                  _BottomNavIcon(
                    icon: SolarIconsBold.dollar,
                    active: currentIndex == 1,
                    onTap: () => onChanged(1),
                    onDeepBg: onSendTab,
                  ),
                  _BottomNavIcon(
                    icon: SolarIconsBold.clockCircle,
                    active: currentIndex == 2,
                    onTap: () => onChanged(2),
                    onDeepBg: onSendTab,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavIcon extends StatelessWidget {
  const _BottomNavIcon({required this.icon, required this.active, required this.onTap, required this.onDeepBg});

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  /// Whether this icon sits on the forest-green bgDeep background (send tab).
  final bool onDeepBg;

  @override
  Widget build(BuildContext context) {
    final activeColor = onDeepBg ? ZendColors.accentPop : ZendColors.accentPop;
    final inactiveColor = onDeepBg
        ? const Color(0x66F0F0F0)
        : const Color(0x66F0F0F0);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? activeColor : inactiveColor, size: 26),
            const SizedBox(height: 5),
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── In-app payment request banner ────────────────────────────────────────────

class _PaymentRequestBanner extends StatefulWidget {
  // ignore: use_super_parameters
  const _PaymentRequestBanner({
    Key? key,
    required this.notification,
    required this.onPay,
    required this.onDismiss,
  }) : super(key: key);

  final PaymentRequestNotification notification;
  final VoidCallback onPay;
  final VoidCallback onDismiss;

  @override
  State<_PaymentRequestBanner> createState() => _PaymentRequestBannerState();
}

class _PaymentRequestBannerState extends State<_PaymentRequestBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    return SlideTransition(
      position: _slide,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                // Banner uses elevated dark surface — neutral, not green
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2A2A2A)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x60000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0x1A4ADE80),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      SolarIconsBold.dollar,
                      size: 20,
                      color: ZendColors.accentPop,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '@${n.requesterZendtag} is requesting ${n.formattedAmount}',
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF0F0F0),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (n.description != null && n.description!.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            n.description!,
                            style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 11,
                              color: Color(0x99F0F0F0),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Pay now button
                  GestureDetector(
                    onTap: widget.onPay,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: ZendColors.accentPop,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Pay',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ZendColors.bgDeep,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Dismiss
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: const Icon(
                      SolarIconsBold.closeCircle,
                      size: 16,
                      color: Color(0x66F0F0F0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── In-app Activity_Edge reaction banner ────────────────────────────────────

class _ActivityReactionBanner extends StatefulWidget {
  // ignore: use_super_parameters
  const _ActivityReactionBanner({
    Key? key,
    required this.notification,
    required this.onDismiss,
  }) : super(key: key);

  final ActivityReactionNotification notification;
  final VoidCallback onDismiss;

  @override
  State<_ActivityReactionBanner> createState() => _ActivityReactionBannerState();
}

class _ActivityReactionBannerState extends State<_ActivityReactionBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    return SlideTransition(
      position: _slide,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2A2A2A)),
                boxShadow: const [BoxShadow(color: Color(0x60000000), blurRadius: 16, offset: Offset(0, 4))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0x1A4ADE80), shape: BoxShape.circle),
                    child: Text(n.emoji, style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '@${n.reactorZendtag} reacted ${n.emoji} to your activity',
                      style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF0F0F0)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: const Icon(SolarIconsBold.closeCircle, size: 16, color: Color(0x66F0F0F0)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── In-app Activity_Edge comment banner ─────────────────────────────────────

class _ActivityCommentBanner extends StatefulWidget {
  // ignore: use_super_parameters
  const _ActivityCommentBanner({
    Key? key,
    required this.notification,
    required this.onDismiss,
  }) : super(key: key);

  final ActivityCommentNotification notification;
  final VoidCallback onDismiss;

  @override
  State<_ActivityCommentBanner> createState() => _ActivityCommentBannerState();
}

class _ActivityCommentBannerState extends State<_ActivityCommentBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    return SlideTransition(
      position: _slide,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2A2A2A)),
                boxShadow: const [BoxShadow(color: Color(0x60000000), blurRadius: 16, offset: Offset(0, 4))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0x1A4ADE80), shape: BoxShape.circle),
                    child: const Icon(SolarIconsBold.chatDots, size: 16, color: ZendColors.accentPop),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '@${n.authorZendtag} commented on your activity',
                          style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF0F0F0)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          n.body,
                          style: const TextStyle(fontFamily: 'DMSans', fontSize: 11, color: Color(0x99F0F0F0)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: const Icon(SolarIconsBold.closeCircle, size: 16, color: Color(0x66F0F0F0)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
