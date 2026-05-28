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
import '../money/home_screen.dart';

class ZendShell extends StatefulWidget {
  const ZendShell({super.key});

  @override
  State<ZendShell> createState() => _ZendShellState();
}

class _ZendShellState extends State<ZendShell> {
  int _tabIndex = 0;
  Timer? _bannerTimer;

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

    // Start auto-dismiss timer when a new notification arrives
    if (pending != null) {
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) model.clearPendingPaymentRequest();
      });
    }

    final pages = <Widget>[
      HomeScreen(
        onOpenReceive: () => _openReceiveScreen(context),
        onOpenSend: () => _setTab(1),
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
                notification: pending,
                onPay: () => _payFromBanner(context, model, pending),
                onDismiss: () => _dismissBanner(model),
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
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        // Bottom nav on neutral black — blends with system nav bar
        color: Color(0xFF0D0D0D),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _BottomNavIcon(
              icon: Icons.account_balance_wallet_outlined,
              active: currentIndex == 0,
              onTap: () => onChanged(0),
            ),
            _BottomNavIcon(
              icon: Icons.attach_money,
              active: currentIndex == 1,
              onTap: () => onChanged(1),
            ),
            _BottomNavIcon(
              icon: Icons.access_time,
              active: currentIndex == 2,
              onTap: () => onChanged(2),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavIcon extends StatelessWidget {
  const _BottomNavIcon({required this.icon, required this.active, required this.onTap});

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? ZendColors.accentPop : const Color(0x66F0F0F0), size: 24),
            const SizedBox(height: 4),
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: ZendColors.accentPop, shape: BoxShape.circle),
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
  const _PaymentRequestBanner({
    required this.notification,
    required this.onPay,
    required this.onDismiss,
  });

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
                      Icons.attach_money,
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
                      Icons.close,
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
