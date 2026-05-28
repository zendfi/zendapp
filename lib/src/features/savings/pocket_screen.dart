import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/pocket_models.dart';
import '../../models/savings_models.dart';
import '../../navigation/zend_routes.dart';
import 'goal_creation_sheet.dart';
import 'goal_detail_screen.dart';
import 'lock_creation_sheet.dart';
import 'savings_deposit_sheet.dart';
import 'savings_withdraw_sheet.dart';

class PocketScreen extends StatefulWidget {
  const PocketScreen({super.key});

  @override
  State<PocketScreen> createState() => _PocketScreenState();
}

class _PocketScreenState extends State<PocketScreen> {
  List<SavingsPocket>? _pockets;
  SavingsMetrics? _metrics;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final model = ZendScope.of(context);
      final results = await Future.wait([
        model.pocketService.listPockets(),
        model.savingsService.getSavingsMetrics(),
      ]);
      if (!mounted) return;
      setState(() {
        _pockets = results[0] as List<SavingsPocket>;
        _metrics = results[1] as SavingsMetrics;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  double get _totalBalance {
    final pockets = _pockets;
    if (pockets == null) return 0.0;
    return pockets.fold(0.0, (sum, p) => sum + p.balanceUsd + p.pocketYieldUsd);
  }

  SavingsPocket? get _freePocket {
    return _pockets?.where((p) => p.isFree).firstOrNull;
  }

  List<SavingsPocket> get _goalPockets {
    return _pockets?.where((p) => p.isGoal).toList() ?? [];
  }

  SavingsPocket? get _lockPocket {
    return _pockets?.where((p) => p.isLock).firstOrNull;
  }

  Future<void> _openDepositSheet({String? pocketId, String? pocketLabel}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SavingsDepositSheet(
        pocketId: pocketId,
        pocketLabel: pocketLabel,
      ),
    );
    if (mounted) unawaited(_loadData());
  }

  Future<void> _openWithdrawSheet(SavingsPocket pocket) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SavingsWithdrawSheet(
        pocketId: pocket.id,
        availableAmount: pocket.balanceUsd,
        pocketType: pocket.pocketType,
        lockUnlockDate: pocket.lockUnlockDate,
        isGoalLocked: pocket.isGoalLocked,
      ),
    );
    if (mounted) unawaited(_loadData());
  }

  Future<void> _openGoalCreation() async {
    final result = await showModalBottomSheet<SavingsPocket>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GoalCreationSheet(),
    );
    if (result != null && mounted) unawaited(_loadData());
  }

  Future<void> _openLockCreation() async {
    final freePocket = _freePocket;
    if (freePocket == null) return;
    final result = await showModalBottomSheet<SavingsPocket>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LockCreationSheet(freePocketBalance: freePocket.balanceUsd),
    );
    if (result != null && mounted) unawaited(_loadData());
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── App bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: zt.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    'Savings',
                    style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? _buildSkeleton(zt)
                  : _error != null
                      ? _buildError(zt)
                      : _buildContent(zt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton(ZendTheme zt) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        _SkeletonBox(width: 160, height: 24, zt: zt),
        const SizedBox(height: 8),
        _SkeletonBox(width: 220, height: 64, zt: zt),
        const SizedBox(height: 8),
        _SkeletonBox(width: 100, height: 28, zt: zt),
        const SizedBox(height: 24),
        _SkeletonBox(width: double.infinity, height: 120, zt: zt),
        const SizedBox(height: 16),
        _SkeletonBox(width: double.infinity, height: 120, zt: zt),
        const SizedBox(height: 16),
        _SkeletonBox(width: double.infinity, height: 100, zt: zt),
      ],
    );
  }

  Widget _buildError(ZendTheme zt) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: zt.textSecondary),
            const SizedBox(height: ZendSpacing.md),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: ZendSpacing.xs),
            Text(
              "We couldn't load your savings. Please try again.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                height: 1.45,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: ZendSpacing.xl),
            SizedBox(
              width: 160,
              child: PrimaryButton(label: 'Try again', onPressed: _loadData),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ZendTheme zt) {
    final metrics = _metrics;
    final apyStr = metrics != null
        ? '${metrics.apy.toStringAsFixed(1)}% a year'
        : '—';

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        const SizedBox(height: ZendSpacing.md),

        // ── "Total savings" label ─────────────────────────────────────
        Text(
          'Total savings',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: zt.textSecondary,
          ),
        ),
        const SizedBox(height: ZendSpacing.xxs),

        // ── Total balance ─────────────────────────────────────────────
        Text(
          '\$${_totalBalance.toStringAsFixed(2)}',
          style: TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 56,
            height: 1.04,
            fontWeight: FontWeight.w700,
            color: zt.textPrimary,
          ),
        ),
        const SizedBox(height: ZendSpacing.sm),

        // ── APY chip ──────────────────────────────────────────────────
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: zt.accentBright.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(ZendRadii.pill),
            ),
            child: Text(
              apyStr,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: zt.accentBright,
              ),
            ),
          ),
        ),
        const SizedBox(height: ZendSpacing.xxl),

        // ── Stash section ──────────────────────────────────────
        _SectionHeader(label: 'Stash', zt: zt),
        const SizedBox(height: ZendSpacing.sm),
        _FreeSavingsCard(
          pocket: _freePocket,
          zt: zt,
          onAddMoney: () => _openDepositSheet(),
          onCashOut: () {
            final p = _freePocket;
            if (p != null) _openWithdrawSheet(p);
          },
        ),
        const SizedBox(height: ZendSpacing.xxl),

        // ── Goals section ─────────────────────────────────────────────
        _SectionHeader(label: 'Goals', zt: zt),
        const SizedBox(height: ZendSpacing.sm),
        if (_goalPockets.isEmpty)
          _EmptyState(
            zt: zt,
            message: 'No goals yet. Create one to start saving with purpose.',
          )
        else
          for (final goal in _goalPockets) ...[
            GoalCard(
              pocket: goal,
              zt: zt,
              onAddMoney: () => _openDepositSheet(
                pocketId: goal.id,
                pocketLabel: '${goal.goalEmoji ?? ''} ${goal.goalName ?? ''}',
              ),
              onWithdraw: () => _openWithdrawSheet(goal),
              onTap: () => pushZendSlide(
                context,
                GoalDetailScreen(pocket: goal),
              ).then((_) => _loadData()),
            ),
            const SizedBox(height: ZendSpacing.sm),
          ],
        const SizedBox(height: ZendSpacing.sm),
        OutlinedButton.icon(
          onPressed: _openGoalCreation,
          icon: const Icon(Icons.add, size: 18),
          label: const Text(
            'New goal',
            style: TextStyle(fontFamily: 'DMSans', fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: zt.accentBright,
            side: BorderSide(color: zt.accentBright),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ZendRadii.lg),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: ZendSpacing.xxl),

        // ── Locked section ────────────────────────────────────────────
        _SectionHeader(label: 'Locked', zt: zt),
        const SizedBox(height: ZendSpacing.sm),
        if (_lockPocket == null)
          _EmptyState(
            zt: zt,
            message: 'Lock savings for a set period to stay committed.',
            action: _freePocket != null && (_freePocket!.balanceUsd > 0)
                ? TextButton.icon(
                    onPressed: _openLockCreation,
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: const Text(
                      'Lock savings',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: zt.accentBright,
                    ),
                  )
                : null,
          )
        else
          LockCard(
            pocket: _lockPocket!,
            zt: zt,
            onWithdraw: () => _openWithdrawSheet(_lockPocket!),
          ),
      ],
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.zt});
  final String label;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: zt.textPrimary,
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.zt, required this.message, this.action});
  final ZendTheme zt;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZendSpacing.md),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              color: zt.textSecondary,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: ZendSpacing.xs),
            action!,
          ],
        ],
      ),
    );
  }
}

// ── Stash card ─────────────────────────────────────────────────────────────────

class _FreeSavingsCard extends StatelessWidget {
  const _FreeSavingsCard({
    required this.pocket,
    required this.zt,
    required this.onAddMoney,
    required this.onCashOut,
  });
  final SavingsPocket? pocket;
  final ZendTheme zt;
  final VoidCallback onAddMoney;
  final VoidCallback onCashOut;

  @override
  Widget build(BuildContext context) {
    final balance = pocket?.balanceUsd ?? 0.0;
    final yield_ = pocket?.pocketYieldUsd ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(ZendSpacing.md),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💰', style: TextStyle(fontSize: 20)),
              const SizedBox(width: ZendSpacing.xs),
              Text(
                'Stash',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: zt.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZendSpacing.sm),
          Text(
            '\$${balance.toStringAsFixed(2)}',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xxs),
          Text(
            'Earned \$${yield_.toStringAsFixed(2)} · Withdraw anytime',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: zt.textSecondary,
            ),
          ),
          const SizedBox(height: ZendSpacing.md),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Add money',
                  onPressed: onAddMoney,
                ),
              ),
              const SizedBox(width: ZendSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: balance > 0 ? onCashOut : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: zt.textPrimary,
                    side: BorderSide(color: zt.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZendRadii.lg),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Cash out',
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
        ],
      ),
    );
  }
}

// ── Goal card ─────────────────────────────────────────────────────────────────

class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.pocket,
    required this.zt,
    required this.onAddMoney,
    required this.onWithdraw,
    required this.onTap,
  });

  final SavingsPocket pocket;
  final ZendTheme zt;
  final VoidCallback onAddMoney;
  final VoidCallback onWithdraw;
  final VoidCallback onTap;

  String get _deadlineLabel {
    final deadline = pocket.goalDeadline;
    if (deadline == null) return '';
    try {
      final date = DateTime.parse(deadline);
      final now = DateTime.now();
      final diff = date.difference(now).inDays;
      if (diff < 0) return 'Deadline passed';
      if (diff == 0) return 'Due today';
      return '$diff days left';
    } catch (_) {
      return deadline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (pocket.goalProgress ?? 0.0) / 100.0;
    final balance = pocket.balanceUsd;
    final target = pocket.goalTargetUsd ?? 0.0;
    final isLocked = pocket.isGoalLocked;
    final canWithdraw = !isLocked;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(ZendSpacing.md),
        decoration: BoxDecoration(
          color: zt.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // ── Circular progress arc ──────────────────────────────
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(52, 52),
                        painter: GoalProgressPainter(
                          progress: progress,
                          bgColor: zt.border,
                          fgColor: ZendColors.accentBright,
                          strokeWidth: 4,
                        ),
                      ),
                      Text(
                        pocket.goalEmoji ?? '🎯',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ZendSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              pocket.goalName ?? 'Goal',
                              style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: zt.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isLocked)
                            Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: zt.textSecondary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '\$${balance.toStringAsFixed(2)} / \$${target.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 13,
                          color: zt.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZendSpacing.xs),
            Row(
              children: [
                _ModeChip(
                  label: pocket.goalMode == 'strict' ? 'Strict' : 'Flexible',
                  zt: zt,
                ),
                if (pocket.goalDeadline != null) ...[
                  const SizedBox(width: ZendSpacing.xs),
                  Text(
                    _deadlineLabel,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      color: zt.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: ZendSpacing.md),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Add money',
                    onPressed: onAddMoney,
                  ),
                ),
                const SizedBox(width: ZendSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: canWithdraw && balance > 0 ? onWithdraw : null,
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
          ],
        ),
      ),
    );
  }
}

// ── Lock card ─────────────────────────────────────────────────────────────────

class LockCard extends StatelessWidget {
  const LockCard({
    super.key,
    required this.pocket,
    required this.zt,
    required this.onWithdraw,
  });

  final SavingsPocket pocket;
  final ZendTheme zt;
  final VoidCallback onWithdraw;

  String get _unlockDateLabel {
    final date = pocket.lockUnlockDate;
    if (date == null) return '';
    try {
      final d = DateTime.parse(date);
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = pocket.isLockExpired;
    final daysRemaining = pocket.lockDaysRemaining ?? 0;

    return Container(
      padding: const EdgeInsets.all(ZendSpacing.md),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isExpired ? Icons.lock_open_outlined : Icons.lock_outline,
                size: 20,
                color: isExpired ? ZendColors.accentBright : zt.textSecondary,
              ),
              const SizedBox(width: ZendSpacing.xs),
              Text(
                isExpired ? 'Ready to withdraw' : 'Locked',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isExpired ? ZendColors.accentBright : zt.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZendSpacing.sm),
          Text(
            '\$${pocket.balanceUsd.toStringAsFixed(2)}',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xxs),
          if (!isExpired)
            Text(
              'Until $_unlockDateLabel · $daysRemaining days left',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: zt.textSecondary,
              ),
            )
          else
            Text(
              'Unlocked on $_unlockDateLabel',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: zt.textSecondary,
              ),
            ),
          if (isExpired) ...[
            const SizedBox(height: ZendSpacing.md),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Withdraw',
                onPressed: onWithdraw,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Mode chip ─────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.zt});
  final String label;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: BorderRadius.circular(ZendRadii.pill),
        border: Border.all(color: zt.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: zt.textSecondary,
        ),
      ),
    );
  }
}

// ── Skeleton box ──────────────────────────────────────────────────────────────

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.zt,
  });
  final double width;
  final double height;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.md),
      ),
    );
  }
}

// ── Goal Progress Painter ─────────────────────────────────────────────────────

class GoalProgressPainter extends CustomPainter {
  const GoalProgressPainter({
    required this.progress,
    required this.bgColor,
    required this.fgColor,
    this.strokeWidth = 5,
  });

  final double progress; // 0.0–1.0
  final Color bgColor;
  final Color fgColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;

    // Background arc (full circle)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi,
      false,
      Paint()
        ..color = bgColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );

    // Progress arc
    final clampedProgress = progress.clamp(0.0, 1.0);
    if (clampedProgress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * clampedProgress,
        false,
        Paint()
          ..color = fgColor
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(GoalProgressPainter old) =>
      old.progress != progress ||
      old.bgColor != bgColor ||
      old.fgColor != fgColor ||
      old.strokeWidth != strokeWidth;
}
