import 'dart:ui';

import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../activity/transaction_receipt_sheet.dart';
import '../pools/pool_list_drawer.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenReceive,
    required this.onOpenSend,
    required this.onViewAll,
  });

  final VoidCallback onOpenReceive;
  final VoidCallback onOpenSend;
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

  @override
  void initState() {
    super.initState();
    // Fetch balance after the first frame to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZendScope.of(context).fetchBalance();
    });
  }

  @override
  void dispose() {
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
                      Text(
                        '${model.greetingPrefix} ${_displayName(model.username)}',
                        style: const TextStyle(fontFamily: 'InstrumentSerif', color: ZendColors.textOnDeep, fontSize: 26, fontWeight: FontWeight.w600),
                      ),
                      Row(children: [
                        GestureDetector(
                          onTap: () => pushZendSlide(context, const ProfileScreen()),
                          child: const CircleAvatar(radius: 18, backgroundColor: Color(0x332D6A4F), child: Icon(Icons.person, color: ZendColors.textOnDeep, size: 18)),
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
                                  color: Color(0x80E8F4EC),
                                  fontSize: 11,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    model.balanceHidden ? '••••••' : '\$${model.balance.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontFamily: 'InstrumentSerif',
                                      color: ZendColors.textOnDeep,
                                      fontSize: balanceSize,
                                      height: 1.0,
                                      fontStyle: FontStyle.italic,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  GestureDetector(
                                    onTap: model.toggleBalanceHidden,
                                    child: Icon(
                                      model.balanceHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      color: const Color(0x99E8F4EC),
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
                                  model.balanceHidden ? '••••••' : '\$${model.balance.toStringAsFixed(2)}',
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
                                    model.balanceHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                    color: const Color(0x99E8F4EC),
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
                                  Expanded(child: OutlineActionButton(label: 'Fund', onPressed: widget.onOpenReceive)),
                                  const SizedBox(width: 12),
                                  Expanded(child: OutlineActionButton(label: 'Send', onPressed: widget.onOpenSend)),
                                ]),
                                const SizedBox(height: 18),
                                Row(children: [const Expanded(child: _YieldCard()), const SizedBox(width: 12), Expanded(child: _PoolsCard(model: model, onTap: () => showPoolListDrawer(context)))]),
                                const SizedBox(height: 18),
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
                                for (var i = 0; i < model.recentTransactions.take(5).length; i++) ...[
                                  _TransactionRow.fromTransaction(
                                    model.recentTransactions[i],
                                    onTap: model.recentTransactions[i].entry != null
                                        ? () => showTransactionReceipt(
                                              context,
                                              tx: model.recentTransactions[i],
                                            )
                                        : null,
                                  ),
                                  if (i != model.recentTransactions.take(5).length - 1) const Divider(color: ZendColors.border),
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


String _displayName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'there';
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.name, required this.note, required this.amount, required this.time, required this.avatarLabel, this.amountColor, this.onTap});
  final String name;
  final String note;
  final String amount;
  final String time;
  final String avatarLabel;
  final Color? amountColor;
  final VoidCallback? onTap;

  factory _TransactionRow.fromTransaction(ZendTransaction tx, {VoidCallback? onTap}) =>
      _TransactionRow(name: tx.name, note: tx.note, amount: tx.amount, time: tx.time, avatarLabel: tx.avatarLabel, amountColor: tx.amountColor, onTap: onTap);

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          CircleAvatar(radius: 20, backgroundColor: zt.bgCard, child: Text(avatarLabel, style: TextStyle(color: zt.textPrimary))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600, color: zt.textPrimary)),
            const SizedBox(height: 3),
            Text(note, style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textSecondary)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(amount, style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 24, fontStyle: FontStyle.italic, color: amountColor ?? zt.textPrimary)),
            const SizedBox(height: 4),
            Text(time, style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary)),
          ]),
        ]),
      ),
    );
  }
}

class _YieldCard extends StatelessWidget {
  const _YieldCard();
  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Container(
      height: 118, padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: zt.bgCard, borderRadius: BorderRadius.circular(14)),
      child: Stack(children: [
        Positioned(top: 0, right: 0, child: Container(width: 64, height: 48, decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0x55A9D7BF), Color(0x00A9D7BF)])))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Earnings', style: TextStyle(fontSize: 14, color: zt.textSecondary)),
            Icon(Icons.settings_outlined, size: 16, color: zt.textSecondary),
          ]),
          const SizedBox(height: 3),
          Text('4.2%', style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 50, height: 0.92, color: zt.textPrimary)),
          const Spacer(),
          Text('CURRENT APY', style: TextStyle(fontFamily: 'DMMono', fontSize: 12, color: zt.textSecondary)),
        ]),
      ]),
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
            color: zt.bgCard, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Pools',
                style: TextStyle(fontSize: 14, color: zt.textSecondary)),
            Icon(Icons.groups_2_outlined,
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
          color: ZendColors.bgDeep, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(label,
          style: const TextStyle(
              fontFamily: 'DMMono',
              fontSize: 10,
              color: ZendColors.textOnDeep)),
    );
  }
}
