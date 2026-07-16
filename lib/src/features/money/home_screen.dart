import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_country_flag.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../activity/transaction_receipt_sheet.dart';
import '../pools/pool_list_drawer.dart';
import '../profile/profile_screen.dart';
import '../savings/pocket_screen.dart';
import 'card_carousel.dart';
import 'card_dismissal_store.dart';
import 'carousel_card_model.dart';
import 'educational_modal.dart';
import 'package:solar_icons/solar_icons.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenReceive,
    required this.onOpenWithdraw,
    required this.onViewAll,
  });

  final VoidCallback onOpenReceive;
  final VoidCallback onOpenWithdraw;
  final VoidCallback onViewAll;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  static const double _minSheetSize = 0.55;
  static const double _maxSheetGap = 52;
  static const double _headerRowHeight = 40;
  static const double _headerRowPadding = 14;

  // Animated balance — tracks the previous and current value for smooth counter animation.
  double _displayedBalance = 0.0;
  double _previousBalance = 0.0;
  StreamSubscription<Map<String, dynamic>>? _dropConfirmedSub;

  // Card_Dismissal_State (Req 25.6) — whether the Debit_Card_Teaser has
  // been dismissed by this User in a previous session. Loaded once in
  // initState(), mirroring how activity_screen.dart loads
  // _notificationsMuted in _loadMutePreference().
  bool _teaserDismissed = false;
  final CardDismissalStore _cardDismissalStore = CardDismissalStore();

  @override
  void initState() {
    super.initState();
    _loadTeaserDismissalState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = ZendScope.of(context);
      _displayedBalance = model.spendableBalance;
      _previousBalance = model.spendableBalance;
      if (model.balance == 0.0 && !model.balanceLoading) {
        model.fetchBalance();
      }
      // Listen to ALL model changes for balance sync, not just drop events.
      // This ensures regular transfers, payins, and any balance update properly
      // animates the counter — the in-build mutation was silent and unreliable.
      model.addListener(_onModelChanged);

      // Subscribe to Drop confirmed events for the spring animation path.
      _dropConfirmedSub = model.dropConfirmedEvents.listen((data) {
        final role = data['role'] as String?;
        if (role != 'receiver') return;
        // For drops: force-animate from old → new balance with spring.
        // The model listener will catch the new value on the next notify.
        // Mark _previousBalance = current so the tween starts from the right place.
        if (mounted) {
          setState(() {
            _previousBalance = _displayedBalance;
            // _displayedBalance will be updated by _onModelChanged on next notify
          });
        }
      });
    });
  }

  void _onModelChanged() {
    if (!mounted) return;
    final model = ZendScope.of(context);
    final newBalance = model.spendableBalance;
    // Only trigger a setState if the balance actually changed — avoids rebuilding
    // on every model notify (e.g. history loading state changes).
    if (newBalance != _displayedBalance) {
      setState(() {
        _previousBalance = _displayedBalance;
        _displayedBalance = newBalance;
      });
    }
  }

  void _onModelBalanceChanged() {
    // Kept for compatibility — delegates to _onModelChanged.
    _onModelChanged();
  }

  Future<void> _loadTeaserDismissalState() async {
    final dismissed = await _cardDismissalStore.isDismissed();
    if (mounted) setState(() => _teaserDismissed = dismissed);
  }

  Future<void> _dismissTeaser() async {
    await _cardDismissalStore.dismiss();
    if (mounted) setState(() => _teaserDismissed = true);
  }

  @override
  void dispose() {
    _dropConfirmedSub?.cancel();
    try {
      final model = ZendScope.of(context);
      model.removeListener(_onModelChanged);
      model.removeListener(_onModelBalanceChanged);
    } catch (_) {}
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final safeTop = MediaQuery.of(context).padding.top;
        final height = constraints.maxHeight;
        final appBarBottom = safeTop + _headerRowPadding + _headerRowHeight;
        final maxSheetTop = appBarBottom + _maxSheetGap;
        final maxChildSize = (1 - (maxSheetTop / height)).clamp(_minSheetSize + 0.05, 0.92);

        return Stack(
          children: [
            // Home header background — intentional deep green brand surface
            Container(color: ZendColors.bgDeep),

            // ── Header row ──
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: _headerRowPadding),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      RichText(
                        text: TextSpan(
                          children: [
                            const TextSpan(
                              text: 'hi ',
                              style: TextStyle(
                                fontFamily: 'InstrumentSerif',
                                color: ZendColors.textOnDeep,
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '@${model.username}',
                              style: const TextStyle(
                                fontFamily: 'InstrumentSerif',
                                color: ZendColors.textOnDeep,
                                fontSize: 26,
                                fontWeight: FontWeight.w400,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(children: [
                        // Drop discoverable indicator — subtle dot + tap to go to settings
                        ListenableBuilder(
                          listenable: model.dropDiscoverabilityService,
                          builder: (context, _) {
                            final isOn = model.dropDiscoverabilityService.isDiscoverable;
                            if (!isOn) return const SizedBox.shrink();
                            return GestureDetector(
                              onTap: () => pushZendSlide(context, const ProfileScreen()),
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: ZendColors.accentBright
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: ZendColors.accentBright
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: ZendColors.accentBright,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Discoverable',
                                      style: TextStyle(
                                        fontFamily: 'DMMono',
                                        fontSize: 10,
                                        color: ZendColors.accentBright,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        GestureDetector(
                          onTap: () => pushZendSlide(context, const ProfileScreen()),
                          child: ZendAvatar(
                            radius: 18,
                            photoUrl: model.currentAvatarUrl,
                            initials: model.currentDisplayName?.isNotEmpty == true
                                ? model.currentDisplayName![0].toUpperCase()
                                : model.username.isNotEmpty
                                    ? model.username[0].toUpperCase()
                                    : null,
                            backgroundColor: const Color(0x3095D5B2),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),

            // ── Balance hero — truly centered in the gap between header and sheet ──
            AnimatedBuilder(
              animation: _sheetController,
              builder: (context, _) {
                final sheetSize = _sheetController.isAttached
                    ? _sheetController.size.clamp(_minSheetSize, maxChildSize)
                    : _minSheetSize;
                final t = ((sheetSize - _minSheetSize) / (maxChildSize - _minSheetSize)).clamp(0.0, 1.0);
                final sheetTopY = height * (1 - sheetSize);
                final balanceSize = lerpDouble(88, 32, t) ?? 88;
                final yieldOpacity = (1 - t).clamp(0.0, 1.0);

                return Positioned(
                  top: appBarBottom,
                  left: 0,
                  right: 0,
                  bottom: height - sheetTopY,
                  child: t < 0.5
                      // Expanded: truly centered in the gap
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Zend Balance',
                                style: TextStyle(
                                  fontFamily: 'DMMono',
                                  color: Color(0x99F0F0F0),
                                  fontSize: 11,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TweenAnimationBuilder<double>(
                                    tween: Tween<double>(
                                      begin: _previousBalance,
                                      end: _displayedBalance,
                                    ),
                                    duration: const Duration(milliseconds: 1200),
                                    curve: Curves.elasticOut,
                                    builder: (context, value, _) {
                                      return Text(
                                        model.balanceHidden ? '••••••' : '\$${value.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontFamily: 'InstrumentSerif',
                                          color: ZendColors.textOnDeep,
                                          fontSize: balanceSize,
                                          height: 1.0,
                                          fontStyle: FontStyle.italic,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  GestureDetector(
                                    onTap: model.toggleBalanceHidden,
                                    child: Icon(
                                      model.balanceHidden ? SolarIconsBold.eyeClosed : SolarIconsBold.eye,
                                      color: const Color(0x80F0F0F0),
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Opacity(
                                opacity: yieldOpacity,
                                child: Text(
                                  '${model.monthlyYield.toStringAsFixed(1)}% earned this month',
                                  style: const TextStyle(color: ZendColors.accentPop, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        )
                      // Collapsed: left-aligned, pinned near top
                      : Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, left: 20, right: 20),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  model.balanceHidden ? '••••••' : '\$${model.spendableBalance.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontFamily: 'InstrumentSerif',
                                    color: ZendColors.textOnDeep,
                                    fontSize: balanceSize,
                                    height: 1.0,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: model.toggleBalanceHidden,
                                  child: Icon(
                                    model.balanceHidden ? SolarIconsBold.eyeClosed : SolarIconsBold.eye,
                                    color: const Color(0x80F0F0F0),
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                );
              },
            ),
            // ── Draggable sheet ──
            DraggableScrollableSheet(
              controller: _sheetController,
              minChildSize: _minSheetSize,
              maxChildSize: maxChildSize,
              initialChildSize: _minSheetSize,
              snap: true,
              snapSizes: [_minSheetSize, maxChildSize],
              builder: (context, scrollController) {
                return RepaintBoundary(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
                      boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, -4))],
                    ),
                    child: SafeArea(
                      top: false,
                      child: CustomScrollView(
                        controller: scrollController,
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate([
                                Row(children: [
                                  Expanded(child: OutlineActionButton(label: 'Receive', onPressed: widget.onOpenReceive)),
                                  const SizedBox(width: 12),
                                  Expanded(child: OutlineActionButton(label: 'Withdraw', onPressed: widget.onOpenWithdraw)),
                                ]),
                                const SizedBox(height: 18),
                                Row(children: [Expanded(child: _SavingsCard(model: model)), const SizedBox(width: 12), Expanded(child: _PoolsCard(model: model, onTap: () => showPoolListDrawer(context)))]),
                                const SizedBox(height: 18),
                                // --- Card_Carousel (Req 24.1 — directly below Savings/Pools row, directly above Recent_Section) ---
                                CardCarousel(
                                  cards: buildCarouselCards(teaserDismissed: _teaserDismissed),
                                  onCardTap: (card) => showEducationalModal(context, card: card),
                                  onDismissTeaser: _dismissTeaser,
                                ),
                                const SizedBox(height: 18),
                                // --- end Card_Carousel ---
                                const Divider(),
                                const SizedBox(height: 14),
                                Builder(builder: (context) {
                                  final zt = ZendTheme.of(context);
                                  return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                    Text('Recent', style: TextStyle(fontFamily: 'DMSans', fontSize: 14, fontWeight: FontWeight.w600, color: zt.textPrimary)),
                                    GestureDetector(
                                      onTap: widget.onViewAll,
                                      child: Text('view all', style: TextStyle(fontFamily: 'DMMono', fontSize: 12, color: zt.accent)),
                                    ),
                                  ]);
                                }),
                                const SizedBox(height: 14),
                                // Req 23.2: reduced from 5 to 3 items. Tap-through wiring (Req 23.4)
                                // and the "view all" header above (Req 23.3) are otherwise unchanged.
                                for (var i = 0; i < model.recentTransactions.take(3).length; i++) ...[
                                  _TransactionRow.fromTransaction(
                                    model.recentTransactions[i],
                                    onTap: model.recentTransactions[i].entry != null || model.recentTransactions[i].bankOrder != null
                                        ? () => showTransactionReceipt(
                                              context,
                                              tx: model.recentTransactions[i],
                                            )
                                        : null,
                                  ),
                                  if (i != model.recentTransactions.take(3).length - 1) Divider(color: ZendTheme.of(context).border.withValues(alpha: 0.5), height: 1),
                                ],
                                const SizedBox(height: 26),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}


class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.name,
    required this.note,
    required this.amount,
    required this.time,
    required this.avatarLabel,
    this.avatarUrl,
    this.countryCode,
    this.amountColor,
    this.onTap,
  });
  final String name;
  final String note;
  final String amount;
  final String time;
  final String avatarLabel;
  final String? avatarUrl;
  final String? countryCode;
  final Color? amountColor;
  final VoidCallback? onTap;

  factory _TransactionRow.fromTransaction(ZendTransaction tx, {VoidCallback? onTap}) =>
      _TransactionRow(
        name: tx.name,
        note: tx.note,
        amount: tx.amount,
        time: tx.time,
        avatarLabel: tx.avatarLabel,
        avatarUrl: tx.avatarUrl,
        countryCode: tx.countryCode,
        amountColor: tx.amountColor,
        onTap: onTap,
      );

  ZendCountry? get _country => switch (countryCode) {
        'ng' => ZendCountry.ng,
        'us' => ZendCountry.us,
        'gb' => ZendCountry.gb,
        'eu' => ZendCountry.eu,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final country = _country;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          country != null
              ? ZendCountryFlag(country: country, size: 44)
              : ZendAvatar(
                  radius: 22,
                  photoUrl: avatarUrl,
                  initials: avatarLabel,
                ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600, color: zt.textPrimary)),
            const SizedBox(height: 3),
            Text(note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textSecondary)),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Text(amount, style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 22, fontStyle: FontStyle.italic, color: amountColor ?? zt.textPrimary)),
            const SizedBox(height: 4),
            Text(time, style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary)),
          ]),
        ]),
      ),
    );
  }
}

class _SavingsCard extends StatelessWidget {
  const _SavingsCard({required this.model});
  final ZendAppModel model;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final apyStr = model.savingsApy > 0
        ? '${model.savingsApy.toStringAsFixed(1)}%'
        : '—';
    final balanceStr = model.savingsBalance > 0
        ? '\$${model.savingsBalance.toStringAsFixed(2)}'
        : '\$0.00';

    return GestureDetector(
      onTap: () => pushZendSlide(context, const PocketScreen()),
      child: Container(
        height: 118,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          // In dark mode use bgDeep (forest green) — matches the send screen background
          color: zt.isDark ? ZendColors.bgDeep : zt.bgCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Savings', style: TextStyle(fontSize: 14, color: zt.textSecondary)),
              Icon(SolarIconsBold.walletMoney, size: 16, color: zt.textSecondary),
            ]),
            const SizedBox(height: 3),
            Text(
              apyStr,
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 50,
                height: 0.92,
                color: zt.textPrimary,
              ),
            ),
            const Spacer(),
            model.savingsLoading
                ? ZendLoader(size: 14, strokeWidth: 1.5, color: zt.textSecondary)
                : Text(
                    balanceStr,
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 12,
                      color: zt.textSecondary,
                    ),
                  ),
          ]),
        ]),
      ),
    );
  }
}

class _PoolsCard extends StatelessWidget {
  const _PoolsCard({required this.model, required this.onTap});

  final ZendAppModel model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final total = model.totalPoolsGathered;
    final totalStr = '\$${total.toStringAsFixed(2)}';
    final participants = model.recentPoolParticipants;
    final displayedCount = participants.length > 2 ? 2 : participants.length;
    final overflow = participants.length - displayedCount;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 118,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
            // In dark mode use bgDeep (forest green) — matches the send screen background
            color: zt.isDark ? ZendColors.bgDeep : zt.bgCard,
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Pools',
                style: TextStyle(fontSize: 14, color: zt.textSecondary)),
            Icon(SolarIconsBold.usersGroupTwoRounded,
                size: 16, color: zt.textSecondary),
          ]),
          const SizedBox(height: 3),
          if (participants.isNotEmpty)
            SizedBox(
              width: (displayedCount * 16 + 6) + (overflow > 0 ? 20 : 0),
              height: 22,
              child: Stack(children: [
                for (var i = 0; i < displayedCount; i++)
                  Positioned(
                      left: i * 16.0,
                      child: _PoolAvatar(
                          label: participants[i].avatarLabel)),
                if (overflow > 0)
                  Positioned(
                    left: displayedCount * 16.0 + 4,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                          color: zt.bgSecondary,
                          shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('+$overflow',
                          style: TextStyle(
                              fontSize: 10,
                              color: zt.textSecondary)),
                    ),
                  ),
              ]),
            ),
          const Spacer(),
          Text(totalStr,
              style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 50,
                  height: 0.92,
                  color: zt.textPrimary)),
        ]),
      ),
    );
  }
}

class _PoolAvatar extends StatelessWidget {
  const _PoolAvatar({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
          color: Color(0xFF122018), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(label,
          style: const TextStyle(
              fontFamily: 'DMMono',
              fontSize: 10,
              color: ZendColors.textOnDeep)),
    );
  }
}
