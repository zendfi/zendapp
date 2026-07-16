import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/pocket_models.dart';
import 'pocket_screen.dart' show GoalProgressPainter;
import 'savings_deposit_sheet.dart';
import 'savings_withdraw_sheet.dart';
import 'package:solar_icons/solar_icons.dart';

class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({super.key, required this.pocket});

  final SavingsPocket pocket;

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  late SavingsPocket _pocket;

  @override
  void initState() {
    super.initState();
    _pocket = widget.pocket;
  }

  Future<void> _refresh() async {
    try {
      final model = ZendScope.of(context);
      final updated = await model.pocketService.getPocket(_pocket.id);
      if (!mounted) return;
      setState(() => _pocket = updated);
    } catch (_) {
      // Non-fatal
    }
  }

  Future<void> _openDepositSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SavingsDepositSheet(
        pocketId: _pocket.id,
        pocketLabel: '${_pocket.goalEmoji ?? ''} ${_pocket.goalName ?? ''}',
      ),
    );
    if (mounted) unawaited(_refresh());
  }

  Future<void> _openWithdrawSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SavingsWithdrawSheet(
        pocketId: _pocket.id,
        availableAmount: _pocket.balanceUsd,
        pocketType: _pocket.pocketType,
        isGoalLocked: _pocket.isGoalLocked,
      ),
    );
    if (mounted) unawaited(_refresh());
  }

  String get _deadlineLabel {
    final deadline = _pocket.goalDeadline;
    if (deadline == null) return '';
    try {
      final date = DateTime.parse(deadline);
      final now = DateTime.now();
      final diff = date.difference(now).inDays;
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final dateStr = '${months[date.month - 1]} ${date.day}, ${date.year}';
      if (diff < 0) return '$dateStr · Deadline passed';
      if (diff == 0) return '$dateStr · Due today';
      return '$dateStr · $diff days left';
    } catch (_) {
      return deadline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final progress = (_pocket.goalProgress ?? 0.0) / 100.0;
    final balance = _pocket.balanceUsd;
    final target = _pocket.goalTargetUsd ?? 0.0;
    final yield_ = _pocket.pocketYieldUsd;
    final isLocked = _pocket.isGoalLocked;
    final canWithdraw = !isLocked && balance > 0;

    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── App bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: IconButton(
                icon: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                children: [
                  const SizedBox(height: ZendSpacing.md),

                  // ── Header: emoji + name ──────────────────────────────
                  Center(
                    child: Text(
                      _pocket.goalEmoji ?? '🎯',
                      style: const TextStyle(fontSize: 56),
                    ),
                  ),
                  const SizedBox(height: ZendSpacing.sm),
                  Center(
                    child: Text(
                      _pocket.goalName ?? 'Goal',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: ZendSpacing.xl),

                  // ── Circular progress chart ───────────────────────────
                  Center(
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(80, 80),
                            painter: GoalProgressPainter(
                              progress: progress,
                              bgColor: zt.border,
                              fgColor: ZendColors.accentBright,
                              strokeWidth: 6,
                            ),
                          ),
                          Text(
                            '${(_pocket.goalProgress ?? 0.0).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontFamily: 'DMMono',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: zt.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: ZendSpacing.xl),

                  // ── Stats ─────────────────────────────────────────────
                  _StatRow(
                    label: 'Saved',
                    value: '\$${balance.toStringAsFixed(2)}',
                    zt: zt,
                  ),
                  Divider(color: zt.border, height: 24),
                  _StatRow(
                    label: 'Target',
                    value: '\$${target.toStringAsFixed(2)}',
                    zt: zt,
                  ),
                  Divider(color: zt.border, height: 24),
                  _StatRow(
                    label: 'Earned',
                    value: '\$${yield_.toStringAsFixed(2)}',
                    valueColor: ZendColors.accentBright,
                    zt: zt,
                  ),
                  if (_pocket.goalDeadline != null) ...[
                    Divider(color: zt.border, height: 24),
                    _StatRow(
                      label: 'Deadline',
                      value: _deadlineLabel,
                      zt: zt,
                    ),
                  ],
                  Divider(color: zt.border, height: 24),
                  _StatRow(
                    label: 'Mode',
                    value: _pocket.goalMode == 'strict' ? 'Strict' : 'Flexible',
                    zt: zt,
                  ),
                  if (isLocked) ...[
                    const SizedBox(height: ZendSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(ZendSpacing.sm),
                      decoration: BoxDecoration(
                        color: ZendColors.accentBright.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(ZendRadii.md),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            SolarIconsBold.lockKeyhole,
                            size: 16,
                            color: ZendColors.accentBright,
                          ),
                          const SizedBox(width: ZendSpacing.xs),
                          Expanded(
                            child: Text(
                              'Withdrawals are locked until you reach your target.',
                              style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 13,
                                color: zt.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: ZendSpacing.xxl),

                  // ── Action buttons ────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: 'Add money',
                      onPressed: _openDepositSheet,
                    ),
                  ),
                  const SizedBox(height: ZendSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: canWithdraw ? _openWithdrawSheet : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: zt.textPrimary,
                        side: BorderSide(color: zt.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(ZendRadii.lg),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Withdraw',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.zt,
    this.valueColor,
  });

  final String label;
  final String value;
  final ZendTheme zt;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 14,
            color: zt.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'DMMono',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: valueColor ?? zt.textPrimary,
          ),
        ),
      ],
    );
  }
}
