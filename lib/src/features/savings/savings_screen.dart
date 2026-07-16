import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/savings_models.dart';
import 'savings_deposit_sheet.dart';
import 'savings_withdraw_sheet.dart';
import 'package:solar_icons/solar_icons.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  SavingsMetrics? _metrics;
  SavingsPosition? _position;
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
      final service = ZendScope.of(context).savingsService;
      final results = await Future.wait([
        service.getSavingsMetrics(),
        service.getSavingsPosition(),
      ]);
      if (!mounted) return;
      setState(() {
        _metrics = results[0] as SavingsMetrics;
        _position = results[1] as SavingsPosition;
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

  Future<void> _openDepositSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SavingsDepositSheet(),
    );
    if (mounted) unawaited(_loadData());
  }

  Future<void> _openWithdrawSheet() async {
    final position = _position;
    if (position == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SavingsWithdrawSheet(position: position),
    );
    if (mounted) unawaited(_loadData());
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
              child: IconButton(
                icon: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            // ── Body ─────────────────────────────────────────────────────
            Expanded(
              child: _buildBody(zt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ZendTheme zt) {
    if (_loading) return _LoadingState(zt: zt);
    if (_error != null) return _ErrorState(zt: zt, onRetry: _loadData);

    final metrics = _metrics!;
    final position = _position!;

    if (!position.hasPosition) {
      return _ZeroState(
        zt: zt,
        metrics: metrics,
        onSave: _openDepositSheet,
      );
    }

    return _ActiveState(
      zt: zt,
      metrics: metrics,
      position: position,
      onAddMoney: _openDepositSheet,
      onCashOut: _openWithdrawSheet,
    );
  }
}

// ── Loading state ─────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.zt});
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: ZendLoader(color: ZendColors.accentBright),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.zt, required this.onRetry});
  final ZendTheme zt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              SolarIconsBold.infoCircle,
              size: 48,
              color: zt.textSecondary,
            ),
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
              'We couldn\'t load your savings. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: ZendSpacing.xl),
            SizedBox(
              width: 160,
              child: PrimaryButton(label: 'Try again', onPressed: onRetry),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Zero state ────────────────────────────────────────────────────────────────

class _ZeroState extends StatelessWidget {
  const _ZeroState({
    required this.zt,
    required this.metrics,
    required this.onSave,
  });
  final ZendTheme zt;
  final SavingsMetrics metrics;
  final VoidCallback onSave;

  String get _apyDisplay {
    final pct = metrics.apy;
    if (pct == pct.truncateToDouble()) {
      return '${pct.toStringAsFixed(0)}%';
    }
    return '${pct.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: ZendSpacing.xl),

          // ── Large APY display ──────────────────────────────────────────
          Text(
            '$_apyDisplay a year',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 56,
              height: 1.04,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.md),

          // ── Subtitle ──────────────────────────────────────────────────
          Text(
            'Your money works while you sleep',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xs),

          // ── Description ───────────────────────────────────────────────
          Text(
            'Earn on your balance with no lock-up. Withdraw anytime.',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              height: 1.45,
              color: zt.textSecondary,
            ),
          ),

          const Spacer(),

          // ── CTA button ────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Save money',
              onPressed: onSave,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Active state ──────────────────────────────────────────────────────────────

class _ActiveState extends StatelessWidget {
  const _ActiveState({
    required this.zt,
    required this.metrics,
    required this.position,
    required this.onAddMoney,
    required this.onCashOut,
  });
  final ZendTheme zt;
  final SavingsMetrics metrics;
  final SavingsPosition position;
  final VoidCallback onAddMoney;
  final VoidCallback onCashOut;

  String get _apyDisplay {
    final pct = metrics.apy;
    if (pct == pct.truncateToDouble()) {
      return '${pct.toStringAsFixed(0)}% a year';
    }
    return '${pct.toStringAsFixed(1)}% a year';
  }

  String _formatUsd(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        const SizedBox(height: ZendSpacing.md),

        // ── APY chip ──────────────────────────────────────────────────
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: ZendColors.accentBright.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(ZendRadii.pill),
            ),
            child: Text(
              _apyDisplay,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ZendColors.accentBright,
              ),
            ),
          ),
        ),
        const SizedBox(height: ZendSpacing.xl),

        // ── "Your savings" label ──────────────────────────────────────
        Text(
          'Your savings',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: zt.textSecondary,
          ),
        ),
        const SizedBox(height: ZendSpacing.xxs),

        // ── Current value (large) ─────────────────────────────────────
        Text(
          _formatUsd(position.currentValueUsd),
          style: TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 56,
            height: 1.04,
            fontWeight: FontWeight.w700,
            color: zt.textPrimary,
          ),
        ),
        const SizedBox(height: ZendSpacing.xl),

        // ── Stat cards row ────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _StatCard(
                zt: zt,
                label: 'Saved',
                value: _formatUsd(position.principalUsd),
              ),
            ),
            const SizedBox(width: ZendSpacing.sm),
            Expanded(
              child: _StatCard(
                zt: zt,
                label: 'Earned',
                value: _formatUsd(position.netYieldUsd),
                valueColor: ZendColors.accentBright,
              ),
            ),
          ],
        ),
        const SizedBox(height: ZendSpacing.xxl),

        // ── Action buttons ────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(
            label: 'Add money',
            onPressed: onAddMoney,
          ),
        ),
        const SizedBox(height: ZendSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onCashOut,
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
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.zt,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final ZendTheme zt;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZendSpacing.md),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: zt.textSecondary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xxs),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'DMMono',
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: valueColor ?? zt.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
