import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../activity/transaction_receipt_sheet.dart';
import '../onboarding/zendtag_prompt_sheet.dart';
import '../receive/receive_screen.dart';
import '../savings/pocket_screen.dart';
import '../send/withdraw_sheet.dart';
import 'zend_entry_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Wallet — ZEND BETA spec §7-9: reached only by tapping the balance on
/// Feed. "The one place Zend can comfortably become a financial dashboard,
/// because the user intentionally entered it. But even here: restraint
/// over density."
///
/// Presented as a sheet, not a pushed screen — spec §56 groups "contextual
/// actions, lightweight controls" under things that should feel like
/// "pulling something closer, not opening a new application," and the
/// balance-tap gesture on Feed is exactly that kind of contextual reveal
/// rather than a navigation destination in its own right.
Future<void> showWalletSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.92,
      child: WalletSheet(),
    ),
  );
}

class WalletSheet extends StatefulWidget {
  const WalletSheet({super.key});

  @override
  State<WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends State<WalletSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = ZendScope.of(context);
      if (model.balance == 0.0 && !model.balanceLoading) model.fetchBalance();
      if (model.recentTransactions.isEmpty && !model.historyLoading) model.fetchHistory();
    });
  }

  Future<void> _openWithdraw(BuildContext context, double available) async {
    // Spec §9 — "Withdraw isn't available right now" when the rail can't
    // service it. WithdrawSheet already knows this (RailUnavailableException
    // handling lives there); this sheet just needs to hand off cleanly and
    // stay open underneath rather than popping itself first, so the user
    // isn't dropped back to Feed if they cancel out of Withdraw.
    await showWithdrawSheet(context);
  }

  /// Receiving money (QR/handle share) — the closest existing capability to
  /// "Add money" until a real deposit/onramp flow exists. Moved here
  /// unchanged from the old shell-owned Home tab's Receive button,
  /// including the zendtag-placeholder guard: a `zdfi.me/@handle` link is
  /// useless (and would leak the user's email placeholder) until they've
  /// claimed a real handle.
  Future<void> _openReceive(BuildContext context) async {
    final model = ZendScope.of(context);
    if (model.zendtagIsPlaceholder) {
      await showZendtagPromptSheet(context);
      if (!context.mounted || model.zendtagIsPlaceholder) return;
    }
    if (!context.mounted) return;

    final openSend = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReceiveScreen(username: model.username),
      ),
    );
    if (openSend == true && context.mounted) {
      showZendEntrySheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

    return Container(
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header: ←  ... × (spec §8 wireframe) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40), // balances the × on the right so the title stays centered
                  const Center(child: ZendSheetHandle()),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(PhosphorIconsRegular.x, color: zt.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    // ── "Your money" / balance / "Available" ──
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Your money',
                            style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: model.toggleBalanceHidden,
                            child: Text(
                              model.balanceHidden ? '••••••' : '\$${model.spendableBalance.toStringAsFixed(2)}',
                              style: TextStyle(fontFamily: 'Geist', fontSize: 40, fontWeight: FontWeight.w700, color: zt.textPrimary),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Available',
                            style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Divider(color: zt.border, height: 1),
                    const SizedBox(height: 4),

                    // ── Savings / Cards / Add money / Withdraw rows ──
                    _WalletRow(
                      label: 'Savings',
                      trailing: model.savingsLoading
                          ? null
                          : Text(
                              '\$${model.savingsBalance.toStringAsFixed(model.savingsBalance == model.savingsBalance.roundToDouble() ? 0 : 2)}',
                              style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: zt.textPrimary),
                            ),
                      onTap: () {
                        Navigator.of(context).pop();
                        pushZendSlide(context, const PocketScreen());
                      },
                    ),
                    _WalletRow(
                      label: 'Cards',
                      onTap: () => _showCardsSheet(context, zt),
                    ),
                    _WalletRow(
                      label: 'Add money',
                      // No dedicated bank/card deposit flow exists in the
                      // app yet — the closest existing capability to "add
                      // money" is receiving it from someone else (QR/handle
                      // share), which is what this previously hung off of
                      // Home's own Receive button. Routing there instead of
                      // a dead-end stub keeps that capability reachable;
                      // flagging that a real deposit/onramp entry point,
                      // if one ships, should probably take over this row.
                      onTap: () {
                        Navigator.of(context).pop();
                        _openReceive(context);
                      },
                    ),
                    _WalletRow(
                      label: 'Withdraw',
                      onTap: () => _openWithdraw(context, model.balance),
                    ),

                    const SizedBox(height: 20),
                    Divider(color: zt.border, height: 1),
                    const SizedBox(height: 18),

                    // ── Recent ──
                    Text(
                      'Recent',
                      style: TextStyle(fontFamily: 'Geist', fontSize: 14, fontWeight: FontWeight.w600, color: zt.textPrimary),
                    ),
                    const SizedBox(height: 10),
                    if (model.historyLoading && model.recentTransactions.isEmpty)
                      const WalletRecentSkeleton()
                    else if (model.recentTransactions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Nothing here yet.',
                          style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
                        ),
                      )
                    else
                      for (var i = 0; i < model.recentTransactions.take(5).length; i++) ...[
                        _RecentRow(
                          tx: model.recentTransactions[i],
                          onTap: model.recentTransactions[i].entry != null || model.recentTransactions[i].bankOrder != null
                              ? () => showTransactionReceipt(context, tx: model.recentTransactions[i])
                              : null,
                        ),
                        if (i != model.recentTransactions.take(5).length - 1) Divider(color: zt.border.withValues(alpha: 0.5), height: 1),
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

  void _showCardsSheet(BuildContext context, ZendTheme zt) {
    // Spec §9 — "No cards yet. [ Add card ]" for a User with none, no
    // functional card issuance exists in the app today, so the button
    // states its own limitation rather than pretending to work.
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        decoration: BoxDecoration(
          color: zt.bgPrimary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Cards', style: TextStyle(fontFamily: 'Geist', fontSize: 18, fontWeight: FontWeight.w700, color: zt.textPrimary)),
            const SizedBox(height: 12),
            Text('No cards yet.', style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlineActionButton(
                label: 'Add card',
                onPressed: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cards are coming soon', style: TextStyle(fontFamily: 'Geist'))),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({required this.label, required this.onTap, this.trailing});

  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textPrimary)),
              ),
              trailing ?? Icon(PhosphorIconsRegular.caretRight, size: 18, color: zt.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.tx, this.onTap});

  final ZendTransaction tx;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ZendAvatar(radius: 16, photoUrl: tx.avatarUrl, initials: tx.avatarLabel),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tx.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Geist', fontSize: 14, fontWeight: FontWeight.w500, color: zt.textPrimary),
              ),
            ),
            Text(
              tx.amount,
              style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w600, color: tx.amountColor ?? zt.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
