import 'package:flutter/material.dart';
import '../../design/zend_tokens.dart';

/// Reusable streak indicator widget.
///
/// Compact variant (default): just the 🔥 emoji, used as an avatar badge.
/// Full variant: "🔥 8w streak" — used in thread headers and DM AppBar.
/// Profile variant: large number + "week streak" label.
class StreakIndicator extends StatelessWidget {
  const StreakIndicator({
    super.key,
    required this.streakWeeks,
    this.variant = StreakIndicatorVariant.compact,
  });

  final int streakWeeks;
  final StreakIndicatorVariant variant;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    if (streakWeeks < 2) return const SizedBox.shrink();

    return switch (variant) {
      StreakIndicatorVariant.compact => const Text('🔥', style: TextStyle(fontSize: 12)),
      StreakIndicatorVariant.full => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B00).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(ZendRadii.pill),
          ),
          child: Text(
            '🔥 ${streakWeeks}w streak',
            style: const TextStyle(
              fontFamily: 'DMMono',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFF6B00),
            ),
          ),
        ),
      StreakIndicatorVariant.profile => Column(
          children: [
            Text(
              '$streakWeeks',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 36,
                color: zt.textPrimary,
              ),
            ),
            Text(
              'week streak 🔥',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: zt.textSecondary,
              ),
            ),
          ],
        ),
    };
  }
}

enum StreakIndicatorVariant { compact, full, profile }
