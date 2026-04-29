import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';
import 'pool.dart';
import 'pool_progress_bar.dart';

/// A card summarising a single [Pool] for use inside the Pool List Drawer.
///
/// Shows the pool name, participant avatars (max 3 with "+N" overflow),
/// gathered amount, a [PoolProgressBar], and the target amount.
class PoolInfoCard extends StatelessWidget {
  const PoolInfoCard({
    super.key,
    required this.pool,
    required this.onTap,
  });

  final Pool pool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ZendColors.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: name + avatars ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    pool.name,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ZendColors.textPrimary,
                    ),
                  ),
                ),
                _AvatarRow(participants: pool.participants),
              ],
            ),
            const SizedBox(height: ZendSpacing.xs),

            // ── Gathered amount ──
            Text(
              pool.formattedGathered,
              style: const TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 22,
                fontStyle: FontStyle.italic,
                color: ZendColors.textPrimary,
              ),
            ),
            const SizedBox(height: ZendSpacing.xs),

            // ── Progress bar ──
            PoolProgressBar(progress: pool.progress),
            const SizedBox(height: ZendSpacing.xxs),

            // ── Target label ──
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                pool.formattedTarget,
                style: const TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 11,
                  color: ZendColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays up to 3 overlapping circular avatars with a "+N" overflow badge.
class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.participants});

  final List<PoolParticipant> participants;

  static const double _size = 22;
  static const double _overlap = 6;

  @override
  Widget build(BuildContext context) {
    final visible = participants.take(3).toList();
    final overflow = participants.length - 3;

    // Total width: first avatar full + subsequent avatars offset.
    final count = visible.length + (overflow > 0 ? 1 : 0);
    final totalWidth =
        count == 0 ? 0.0 : _size + (_size - _overlap) * (count - 1);

    return SizedBox(
      width: totalWidth,
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * (_size - _overlap),
              child: CircleAvatar(
                radius: _size / 2,
                backgroundColor: ZendColors.accent,
                child: Text(
                  visible[i].avatarLabel,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: ZendColors.textOnDeep,
                  ),
                ),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * (_size - _overlap),
              child: CircleAvatar(
                radius: _size / 2,
                backgroundColor: ZendColors.bgDeep,
                child: Text(
                  '+$overflow',
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: ZendColors.textOnDeep,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
