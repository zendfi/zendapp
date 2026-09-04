import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../models/payment_request_notification.dart';
import '../../navigation/zend_shell_controller.dart';
import '../../navigation/notification_navigator.dart';
import '../../services/pending_deep_link_service.dart';
import '../../services/pending_notification_service.dart';
import '../../design/zend_primitives.dart';
import '../request/request_qr_sheet.dart';
import '../send/qr_payment_sheet.dart';
import '../send/send_flow_sheet.dart';
import '../send/transfer_status_controller.dart';
import '../profile/profile_screen.dart';
import '../dm/dm_list_screen.dart';
import '../dm/dm_thread_screen.dart';
import '../../navigation/zend_routes.dart';
import 'feed_screen.dart';
import 'people_screen.dart';
import 'wallet_sheet.dart';
import 'zend_entry_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class ZendShell extends StatefulWidget {
  const ZendShell({super.key});

  @override
  State<ZendShell> createState() => _ZendShellState();
}

class _ZendShellState extends State<ZendShell> {
  // Tab order: 0=Feed, 1=People, 2=Chats, 3=You (ZEND BETA spec §2).
  // Feed is the primary landing screen — "what's happening between me and
  // my people?" (spec §5) — replacing the old default of the Send tab,
  // which no longer exists as a tab at all (Zend is now a floating action).
  int _tabIndex = 0;
  late final PageController _pageController;
  Timer? _bannerTimer;
  // Tracks the last notification ID so re-arrival of a new request
  // forces the banner widget to rebuild and replay the slide-in animation.
  String? _lastBannerRequestId;
  Timer? _reactionBannerTimer;
  String? _lastReactionBannerKey;
  Timer? _commentBannerTimer;
  String? _lastCommentBannerKey;
  // DM banner
  Map<String, dynamic>? _pendingDmBanner;
  Timer? _dmBannerTimer;
  String? _lastDmBannerKey;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _tabIndex, keepPage: true);
    // Register this shell with the controller so notification taps can
    // switch tabs. Route through _setTab (not a bare setState) so this
    // matches every other way of switching tabs exactly — including
    // actually moving the PageView via jumpToPage and clearing the
    // relevant unread badge. Previously this only updated _tabIndex, which
    // moves the bottom bar's highlighted icon but leaves the PageView
    // showing whatever page it was already on — tapping a notification to
    // "go to Activity" would show the Activity tab as selected while the
    // actual visible content stayed on Home/Send/DM.
    ZendShellController.activate((index) {
      if (mounted) _setTab(index);
    });
    // Consume any pending deep link that was stored before the user
    // completed device unlock (PIN screen).
    // Also consume any pending notification tap destination — this covers the
    // cold-launch path where isLocked was never true (no state-change event).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pendingIntent = PendingDeepLinkService.consume();
      if (pendingIntent != null) {
        showQrPaymentSheet(context, intent: pendingIntent);
      }
      final pendingDest = PendingNotificationService.consume();
      if (pendingDest != null) {
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          NotificationNavigator.dispatch(context, pendingDest, ZendScope.of(context)); // ignore: use_build_context_synchronously
        });
      }
    });
  }

  @override
  void dispose() {
    ZendShellController.deactivate();
    _pageController.dispose();
    _bannerTimer?.cancel();
    _reactionBannerTimer?.cancel();
    _commentBannerTimer?.cancel();
    _dmBannerTimer?.cancel();
    super.dispose();
  }

  void _setTab(int index) {
    if (index == _tabIndex) return;
    setState(() {
      _tabIndex = index;
    });
    // Jump instantly — no slide animation for tab-bar taps.
    // Slide animation only fires when the user physically swipes the PageView.
    _pageController.jumpToPage(index);
    // Clear the activity badge when the user actively switches to Feed —
    // Feed is where activity/reaction/comment updates live now, taking
    // over the old Activity tab's role (index 2 previously).
    if (index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ZendScope.of(context).markActivityRead();
      });
    }
    // Clear DM badge when switching to the Chats tab (index 2 now, was 3).
    if (index == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ZendScope.of(context).setDmUnreadTotal(0);
      });
    }
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

  Future<void> _openWallet(BuildContext context) {
    // Wallet is a sheet, not a pushed screen — spec §7/§56 ("pulling
    // something closer, not opening a new application").
    return showWalletSheet(context);
  }

  /// Retries a failed send or request straight from the banner, carrying the
  /// original amount, recipient and note so retrying never means retyping.
  ///
  /// Re-runs the preflight rather than reusing the original decision: the
  /// session keypair may have been evicted since (app lock, timeout), in
  /// which case the retry now needs a PIN. Collecting a PIN is input, and a
  /// banner can't take input — so that case hands back to the full send
  /// sheet instead of failing a second time.
  Future<void> _retryTransferFromBanner(
    BuildContext context,
    ZendAppModel model,
    TransferStatus status,
  ) async {
    if (status.isRequest) {
      await model.transferStatus.request(
        amount: status.amount,
        recipientZendtag: status.recipientZendtag,
        recipientEmail: status.recipientEmail,
        recipientDisplayName: status.recipientDisplayName,
        note: status.note,
      );
      return;
    }

    final tag = status.recipientZendtag;
    if (tag == null || tag.isEmpty) {
      // An email-intent send has no zendtag to retry against; the full
      // sheet owns that flow.
      model.transferStatus.dismiss();
      return;
    }

    // Held before the await: the navigator's own context stays valid
    // independently of whether this element survives the gap.
    final navigator = Navigator.of(context, rootNavigator: true);

    final auth = await TransferAuth.resolve(model, status.amount);
    if (!mounted) return;
    if (auth.needsPin) {
      model.transferStatus.dismiss();
      showSendFlowSheet(
        navigator.context,
        amount: status.amount,
        prefilledRecipient: tag,
        prefilledNote: status.note,
      );
      return;
    }

    await model.transferStatus.send(
      amount: status.amount,
      recipientZendtag: tag,
      auth: auth,
      recipientDisplayName: status.recipientDisplayName,
      note: status.note,
    );
  }

  /// Opens the QR for a request the user just created. A shortcut only —
  /// the request also lives in the Requests list, so a banner that fades
  /// never takes the QR with it.
  void _showRequestQrFromBanner(BuildContext context, TransferStatus status) {
    final request = status.request;
    if (request == null || request.id.isEmpty) return;
    ZendScope.of(context).transferStatus.dismiss();
    showRequestQrSheet(context, request: request);
  }

  @override
  Widget build(BuildContext context) {
    // ── Read only what's needed for the PageView and tab bar ──────────────
    // Using a Builder here would still subscribe this whole build to model
    // changes. Instead we read only the fields that affect the *structure*
    // (tab index, which is local state) and leave banner/badge reads to
    // sub-widgets that have their own element nodes.
    final model = ZendScope.of(context);
    final pending = model.pendingPaymentRequest;
    final pendingReaction = model.pendingActivityReaction;
    final pendingComment = model.pendingActivityComment;
    // Suppress the reaction/comment banners while Feed (which now owns
    // activity content, replacing the old Activity tab at index 2) is
    // already active — mirrors the DM banner's own `_tabIndex != 2` check
    // below (Chats is index 2 now, was 3).
    // Computed once here (rather than inline at each Positioned site) so
    // the top-offset math for the banner stack and the visibility checks
    // can't drift out of sync with each other.
    final showReactionBanner = pendingReaction != null && _tabIndex != 0;
    final showCommentBanner = pendingComment != null && _tabIndex != 0;

    // DM banner logic — show when dmUnreadTotal increases and we're not on DM tab
    // The SSE data is carried via model.lastDmBannerData
    if (model.lastDmBannerData != null) {
      final data = model.lastDmBannerData!;
      final key = data['room_id'] as String? ?? '';
      if (key != _lastDmBannerKey && _tabIndex != 2) {
        _lastDmBannerKey = key;
        _pendingDmBanner = data;
        model.clearLastDmBannerData();
        _dmBannerTimer?.cancel();
        _dmBannerTimer = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => _pendingDmBanner = null);
        });
      }
    }

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

    // Tab order: 0=Feed, 1=People, 2=Chats, 3=You (ZEND BETA spec §2).
    // Send is not a tab — it's the floating Zend action (§4), shown
    // contextually below. Wallet is not a tab either — reached only by
    // tapping the balance inside Feed (§7).
    final pages = <Widget>[
      FeedScreen(onOpenWallet: () => _openWallet(context)),
      const PeopleScreen(),
      const DmListScreen(),
      const ProfileScreen(showBackButton: false),
    ];

    // Wrap each page in AutomaticKeepAlive so the PageView keeps all tabs
    // alive — prevents full rebuilds when switching between tabs.
    // RepaintBoundary isolates each tab's render tree so SSE-driven
    // notifyListeners() calls don't cause cross-tab repaints.
    final keepAlivePages = pages
        .map((p) => _KeepAlive(child: RepaintBoundary(child: p)))
        .toList();

    // Banner stack offsets, computed once so adding or removing a banner
    // doesn't mean hand-editing four cumulative expressions.
    //
    // The transfer banner sits at the top of the stack: it's feedback on
    // something the user did a moment ago, which outranks incoming
    // notifications for their attention.
    final transferStatus = model.transferStatus.status;
    const bannerSlot = 78.0;
    final requestTop = transferStatus != null ? bannerSlot : 0.0;
    final reactionTop = requestTop + (pending != null ? bannerSlot : 0.0);
    final commentTop = reactionTop + (showReactionBanner ? bannerSlot : 0.0);
    final dmTop = commentTop + (showCommentBanner ? bannerSlot : 0.0);

    return Scaffold(
      body: RepaintBoundary(
        child: Stack(
          children: [
          PageView(
            controller: _pageController,
            // Keep all pages alive so switching tabs doesn't rebuild heavy
            // screens (activity feed, DM list) from scratch on every tap.
            physics: const ClampingScrollPhysics(),
            onPageChanged: (i) {
              if (i != _tabIndex) {
                setState(() => _tabIndex = i);
                if (i == 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) ZendScope.of(context).markActivityRead();
                  });
                }
                if (i == 2) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) ZendScope.of(context).setDmUnreadTotal(0);
                  });
                }
              }
            },
            children: keepAlivePages,
          ),
          // Outcome of the user's own send/request — see
          // _TransferStatusBanner. Keyed on the action id, not the status,
          // so `sending → sent` mutates this banner in place instead of
          // tearing it down and replaying the slide-in.
          if (transferStatus != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TransferStatusBanner(
                key: ValueKey('transfer-${transferStatus.actionId}'),
                status: transferStatus,
                onRetry: () => _retryTransferFromBanner(context, model, transferStatus),
                onShowQr: () => _showRequestQrFromBanner(context, transferStatus),
                onDismiss: model.transferStatus.dismiss,
              ),
            ),
          // In-app payment request banner
          if (pending != null)
            Positioned(
              top: requestTop,
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
          // Suppressed while the Activity tab is already active — mirrors
          // the DM banner's `_tabIndex != 3` check below. Previously this
          // had no such check, so a reaction/comment banner would pop up
          // and steal attention even while the user was already sitting on
          // the Activity screen watching that exact update land live.
          if (showReactionBanner)
            Positioned(
              top: reactionTop,
              left: 0,
              right: 0,
              child: _ActivityReactionBanner(
                key: ValueKey(_lastReactionBannerKey),
                notification: pendingReaction,
                onDismiss: () => _dismissReactionBanner(model),
              ),
            ),
          // In-app "someone commented on your activity" banner — stacked
          // below whichever of the above banners are present. Same
          // active-tab suppression as the reaction banner above.
          if (showCommentBanner)
            Positioned(
              top: commentTop,
              left: 0,
              right: 0,
              child: _ActivityCommentBanner(
                key: ValueKey(_lastCommentBannerKey),
                notification: pendingComment,
                onDismiss: () => _dismissCommentBanner(model),
              ),
            ),
          // DM banner — shown when a new message arrives and the Chats tab isn't active
          if (_pendingDmBanner != null && _tabIndex != 2)
            Positioned(
              top: dmTop,
              left: 0,
              right: 0,
              child: _DmMessageBanner(
                key: ValueKey(_lastDmBannerKey),
                senderZendtag: _pendingDmBanner!['sender_zendtag'] as String? ?? '',
                preview: _pendingDmBanner!['preview'] as String? ?? '',
                onTap: () {
                  final roomId = _pendingDmBanner!['room_id'] as String? ?? '';
                  _dmBannerTimer?.cancel();
                  setState(() => _pendingDmBanner = null);
                  _setTab(2);
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (!mounted) return;
                    final thread = model.dmService.cachedThreads
                        .where((t) => t.roomId == roomId)
                        .firstOrNull;
                    if (thread != null) {
                      pushZendSlide(
                        context, // ignore: use_build_context_synchronously
                        DmThreadScreen(roomId: roomId, counterparty: thread.counterparty),
                      );
                    }
                  });
                },
                onDismiss: () {
                  _dmBannerTimer?.cancel();
                  setState(() => _pendingDmBanner = null);
                },
              ),
            ),
        ],
        ),  // close RepaintBoundary
      ),
      // Zend — the primary action (spec §4) — floats over Feed and People
      // only. Not present on Chats (Zend is reachable contextually from
      // inside a conversation instead — spec §27) or You (not an action
      // screen — spec §29's "this is me, manage me").
      floatingActionButton: (_tabIndex == 0 || _tabIndex == 1)
          ? _ZendFab(onTap: () => showZendEntrySheet(context))
          : null,
      bottomNavigationBar: ZendBottomBar(
        currentIndex: _tabIndex,
        onChanged: _setTab,
        feedBadgeCount: model.activityUnreadCount,
        chatsBadgeCount: model.dmUnreadTotal,
      ),
    );
  }
}

/// The floating "Zend" action — the app's one verb (spec §4). A round
/// button using the same Z mark as the old Send tab's icon, so the brand
/// gesture carries over even though Send is no longer a destination of
/// its own.
class _ZendFab extends StatelessWidget {
  const _ZendFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: ZendColors.bgDeep,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Center(
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(ZendColors.accentPop, BlendMode.srcIn),
            child: Image.asset(
              'assets/icons/zend-icon-navbar.png',
              width: 26,
              height: 26,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tab bar for Feed / People / Chats / You (spec §2). Every tab now follows
/// the app's own light/dark theme uniformly — the old Send tab's permanent
/// dark-brand-surface styling is gone, since no tab is "the Send tab"
/// anymore (Zend moved to a floating action, see [_ZendFab]).
class ZendBottomBar extends StatelessWidget {
  const ZendBottomBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    this.feedBadgeCount = 0,
    this.chatsBadgeCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;
  final int feedBadgeCount;
  final int chatsBadgeCount;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final activeColor = zt.accent;
    final inactiveColor = zt.textSecondary.withValues(alpha: 0.7);
    final badgeBorderColor = zt.bgPrimary;

    return ColoredBox(
      color: zt.bgPrimary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: zt.border),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _BottomNavIcon(
                    icon: PhosphorIconsRegular.houseLine,
                    activeIcon: PhosphorIconsFill.houseLine,
                    label: 'Feed',
                    active: currentIndex == 0,
                    onTap: () => onChanged(0),
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    badgeBorderColor: badgeBorderColor,
                    badgeCount: feedBadgeCount,
                  ),
                  _BottomNavIcon(
                    icon: PhosphorIconsRegular.usersThree,
                    activeIcon: PhosphorIconsFill.usersThree,
                    label: 'People',
                    active: currentIndex == 1,
                    onTap: () => onChanged(1),
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    badgeBorderColor: badgeBorderColor,
                  ),
                  _BottomNavIcon(
                    icon: PhosphorIconsRegular.chatCircleText,
                    activeIcon: PhosphorIconsFill.chatCircleText,
                    label: 'Chats',
                    active: currentIndex == 2,
                    onTap: () => onChanged(2),
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    badgeBorderColor: badgeBorderColor,
                    badgeCount: chatsBadgeCount,
                  ),
                  _BottomNavIcon(
                    icon: PhosphorIconsRegular.userCircle,
                    activeIcon: PhosphorIconsFill.userCircle,
                    label: 'You',
                    active: currentIndex == 3,
                    onTap: () => onChanged(3),
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    badgeBorderColor: badgeBorderColor,
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
  const _BottomNavIcon({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.activeColor,
    required this.inactiveColor,
    required this.badgeBorderColor,
    this.badgeCount = 0,
  });

  /// Regular-weight glyph shown when this tab isn't active.
  final IconData icon;
  /// Fill-weight glyph shown when this tab is active — gives active/inactive
  /// its own visual language on top of the color change (quiet outline vs
  /// solid, matching the "simple, quiet, rounded" icon brief).
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;
  final Color inactiveColor;
  final Color badgeBorderColor;
  /// Unread count to display as a badge. 0 = no badge.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : inactiveColor;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Icon(active ? activeIcon : icon, color: color, size: 24),
                  ),
                  if (badgeCount > 0 && !active)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: ZendColors.destructive,
                          borderRadius: BorderRadius.circular(ZendRadii.pill),
                          border: Border.all(color: badgeBorderColor, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white, height: 1.0),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: color,
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
            child: _GlassBannerBox(
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
                      PhosphorIconsRegular.currencyDollar,
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
                            fontFamily: 'Geist',
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
                              fontFamily: 'Geist',
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
                          fontFamily: 'Geist',
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
                      PhosphorIconsRegular.xCircle,
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
            child: _GlassBannerBox(
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
                      style: const TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF0F0F0)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: const Icon(PhosphorIconsRegular.xCircle, size: 16, color: Color(0x66F0F0F0)),
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
            child: _GlassBannerBox(
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0x1A4ADE80), shape: BoxShape.circle),
                    child: const Icon(PhosphorIconsRegular.chatDots, size: 16, color: ZendColors.accentPop),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '@${n.authorZendtag} commented on your activity',
                          style: const TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF0F0F0)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          n.body,
                          style: const TextStyle(fontFamily: 'Geist', fontSize: 11, color: Color(0x99F0F0F0)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: const Icon(PhosphorIconsRegular.xCircle, size: 16, color: Color(0x66F0F0F0)),
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

// ── In-app DM message banner ─────────────────────────────────────────────────

class _DmMessageBanner extends StatefulWidget {
  // ignore: use_super_parameters
  const _DmMessageBanner({
    Key? key,
    required this.senderZendtag,
    required this.preview,
    required this.onTap,
    required this.onDismiss,
  }) : super(key: key);

  final String senderZendtag;
  final String preview;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_DmMessageBanner> createState() => _DmMessageBannerState();
}

class _DmMessageBannerState extends State<_DmMessageBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Material(
              color: Colors.transparent,
              child: _GlassBannerBox(
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0x1A4ADE80), shape: BoxShape.circle),
                      child: const Icon(PhosphorIconsRegular.chatDots,
                          size: 18, color: ZendColors.accentPop),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '@${widget.senderZendtag}',
                            style: const TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFF0F0F0)),
                          ),
                          if (widget.preview.isNotEmpty)
                            Text(
                              widget.preview,
                              style: const TextStyle(
                                  fontFamily: 'Geist',
                                  fontSize: 11,
                                  color: Color(0x99F0F0F0)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: const Icon(PhosphorIconsRegular.xCircle,
                          size: 16, color: Color(0x66F0F0F0)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── In-app transfer status banner ────────────────────────────────────────────
//
// The visible half of the instant send/request flow: the sheet closes the
// moment the user commits, and this reports the outcome. Its state lives on
// [TransferStatusController] (above the navigator), not here, because the
// outcome resolves after the sheet is gone — see that class for why.
//
// Unlike the four banners above, the dismiss timer is NOT owned by the
// shell. Whether a status lingers is a property of the status itself
// (`sent` fades, `failed` never does), so the controller owns it.

class _TransferStatusBanner extends StatefulWidget {
  const _TransferStatusBanner({
    super.key,
    required this.status,
    required this.onRetry,
    required this.onShowQr,
    required this.onDismiss,
  });

  final TransferStatus status;
  final VoidCallback onRetry;
  final VoidCallback onShowQr;
  final VoidCallback onDismiss;

  @override
  State<_TransferStatusBanner> createState() => _TransferStatusBannerState();
}

class _TransferStatusBannerState extends State<_TransferStatusBanner>
    with SingleTickerProviderStateMixin {
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

  bool get _isFailure => widget.status.kind == TransferStatusKind.failed;
  bool get _inFlight => widget.status.kind == TransferStatusKind.sending;

  /// Headline. Always names the amount and the person, including on
  /// failure — "Couldn't send" on its own leaves the user guessing which
  /// payment we're talking about.
  String get _title {
    final s = widget.status;
    final isRequest = s.isRequest;
    switch (s.kind) {
      case TransferStatusKind.sending:
        return isRequest
            ? 'Requesting ${s.amountLabel} from ${s.recipientLabel}'
            : 'Sending ${s.amountLabel} to ${s.recipientLabel}';
      case TransferStatusKind.sent:
        return 'Sent ${s.amountLabel} to ${s.recipientLabel}';
      case TransferStatusKind.requested:
        return 'Requested ${s.amountLabel} from ${s.recipientLabel}';
      case TransferStatusKind.failed:
        return isRequest
            ? "Couldn't request ${s.amountLabel} from ${s.recipientLabel}"
            : "Couldn't send ${s.amountLabel} to ${s.recipientLabel}";
      case TransferStatusKind.uncertain:
        return 'Still confirming ${s.amountLabel} to ${s.recipientLabel}';
    }
  }

  /// Only failure and uncertainty carry a second line — the specific
  /// reason. Success needs no elaboration.
  String? get _subtitle => switch (widget.status.kind) {
        TransferStatusKind.failed || TransferStatusKind.uncertain => widget.status.message,
        _ => null,
      };

  Color get _tint => switch (widget.status.kind) {
        TransferStatusKind.sent || TransferStatusKind.requested => ZendColors.positive,
        TransferStatusKind.failed => ZendColors.destructive,
        TransferStatusKind.uncertain => ZendColors.accentPop,
        TransferStatusKind.sending => ZendColors.accentPop,
      };

  Widget _buildIcon() {
    if (_inFlight) {
      return ZendLoader(size: 18, strokeWidth: 2, color: _tint);
    }
    final icon = switch (widget.status.kind) {
      TransferStatusKind.sent || TransferStatusKind.requested => PhosphorIconsRegular.check,
      TransferStatusKind.failed => PhosphorIconsRegular.warningCircle,
      TransferStatusKind.uncertain => PhosphorIconsRegular.clockCountdown,
      TransferStatusKind.sending => PhosphorIconsRegular.check,
    };
    return Icon(icon, size: 20, color: _tint);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final showQr = s.kind == TransferStatusKind.requested && s.request != null;
    final showRetry = _isFailure && s.canRetry;
    final subtitle = _subtitle;

    return SlideTransition(
      position: _slide,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              // Tapping a completed request opens it. The QR button is a
              // shortcut, not the only door — the request also stays in the
              // Requests list, so a banner that fades doesn't take the QR
              // with it.
              onTap: showQr ? widget.onShowQr : null,
              child: _GlassBannerBox(
                // Height changes as the subtitle appears on failure. Animate
                // it so the banner appears to resolve in place rather than
                // snapping to a new size.
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _tint.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: _buildIcon()),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _title,
                              style: const TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFF0F0F0),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle != null && subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontFamily: 'Geist',
                                  fontSize: 11,
                                  color: Color(0x99F0F0F0),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (showRetry || showQr) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: showRetry ? widget.onRetry : widget.onShowQr,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: ZendColors.accentPop,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              showRetry ? 'Retry' : 'Show QR',
                              style: const TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: ZendColors.bgDeep,
                              ),
                            ),
                          ),
                        ),
                      ],
                      // Nothing to dismiss mid-flight — it resolves on its
                      // own in a moment, and an X there would imply the
                      // payment could be called back.
                      if (!_inFlight) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: widget.onDismiss,
                          child: const Icon(
                            PhosphorIconsRegular.xCircle,
                            size: 16,
                            color: Color(0x66F0F0F0),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared glass banner container ────────────────────────────────────────────
//
// All five in-app notification banners use this wrapper so they share
// identical frosted-glass treatment: real BackdropFilter blur, semi-opaque
// elevated surface, and a hairline white bevel on top.

class _GlassBannerBox extends StatelessWidget {
  const _GlassBannerBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF252525).withValues(alpha: 0.80),
            borderRadius: BorderRadius.circular(14),
            border: Border(
              top:    BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 0.5),
              left:   BorderSide(color: Colors.white.withValues(alpha: 0.04), width: 0.5),
              right:  BorderSide(color: Colors.white.withValues(alpha: 0.04), width: 0.5),
              bottom: BorderSide(color: Colors.black.withValues(alpha: 0.15), width: 0.5),
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── Keep-alive wrapper ────────────────────────────────────────────────────────
//
// Wrapping each PageView child in this widget tells Flutter to keep the page
// in the widget tree even when it's not the active tab. Without this, every
// tab switch tears down and rebuilds the entire screen — which is the root
// cause of the lag when switching between Activity, Home, and Messages tabs.

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return widget.child;
  }
}
