import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';
import 'pool.dart';
import 'pool_progress_bar.dart';

/// Full-screen detail view for a single [Pool].
///
/// Shows the pool name, status badge, gathered/target amounts, progress bar,
/// participant list with contributions, and timeline information.
class PoolDetailScreen extends StatelessWidget {
  const PoolDetailScreen({super.key, required this.pool});

  final Pool pool;

  // ── Helpers ──────────────────────────────────────────────────────────────

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime date) {
    return '${_months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Color _statusColor() {
    switch (pool.status) {
      case PoolStatus.active:
        return ZendColors.accentBright;
      case PoolStatus.completed:
        return ZendColors.accent;
      case PoolStatus.expired:
        return ZendColors.destructive;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: ZendColors.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // ── Pool name ──
                  Text(
                    pool.name,
                    style: const TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: ZendColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: ZendSpacing.sm),

                  // ── Status badge ──
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor().withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                      child: Text(
                        pool.status.name,
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _statusColor(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: ZendSpacing.lg),

                  // ── Gathered / Target ──
                  Text(
                    '${pool.formattedGathered} of ${pool.formattedTarget}',
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      color: ZendColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: ZendSpacing.xs),

                  // ── Progress bar ──
                  PoolProgressBar(progress: pool.progress),
                  const SizedBox(height: ZendSpacing.xl),

                  // ── Participants section ──
                  const Text(
                    'PARTICIPANTS',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: ZendColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: ZendSpacing.sm),

                  ...pool.participants.map(_buildParticipantRow),

                  const SizedBox(height: ZendSpacing.xl),

                  // ── Timeline section ──
                  _TimelineRow(
                    label: 'Created',
                    value: _formatDate(pool.createdAt),
                  ),
                  const SizedBox(height: ZendSpacing.xs),
                  _TimelineRow(
                    label: 'Deadline',
                    value: pool.deadline != null
                        ? _formatDate(pool.deadline!)
                        : 'No deadline',
                  ),
                  const SizedBox(height: ZendSpacing.xxl),
                ],
              ),
            ),

            // ── Bottom action buttons (fixed, no icons) ──
            if (pool.status == PoolStatus.active)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Contribute feature coming soon')),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ZendColors.textPrimary,
                          side: const BorderSide(color: ZendColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(ZendRadii.lg),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Contribute',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: ZendSpacing.md),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Manage pool feature coming soon')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZendColors.accent,
                          foregroundColor: ZendColors.textOnDeep,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(ZendRadii.lg),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Manage',
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

  Widget _buildParticipantRow(PoolParticipant p) {
    final contribution = p.contribution == 0
        ? '\$0.00'
        : '\$${p.contribution.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: ZendSpacing.sm),
      child: Row(
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: ZendColors.bgSecondary,
            child: Text(
              p.avatarLabel,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: ZendColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: ZendSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.displayName,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    color: ZendColors.textPrimary,
                  ),
                ),
                if (p.isExternal)
                  const Text(
                    'external',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 11,
                      color: ZendColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            contribution,
            style: const TextStyle(
              fontFamily: 'DMMono',
              fontSize: 13,
              color: ZendColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 13,
            color: ZendColors.textSecondary,
          ),
        ),
        const SizedBox(width: ZendSpacing.xs),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 13,
            color: ZendColors.textPrimary,
          ),
        ),
      ],
    );
  }
}


