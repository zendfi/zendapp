import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';
import 'pool.dart';
import 'pool_list_drawer.dart';
import 'pool_progress_bar.dart';

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
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: zt.bgCard,
          borderRadius: BorderRadius.circular(ZendRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    pool.name,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary,
                    ),
                  ),
                ),
                if (pool.status != PoolStatus.active) ...[
                  const SizedBox(width: ZendSpacing.xs),
                  PoolStatusBadge(status: pool.status),
                ] else
                  _AvatarRow(participants: pool.participants),
              ],
            ),
            const SizedBox(height: ZendSpacing.xs),

            Text(
              pool.formattedGathered,
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 22,
                fontStyle: FontStyle.italic,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: ZendSpacing.xs),

            PoolProgressBar(progress: pool.progress),
            const SizedBox(height: ZendSpacing.xxs),

            Align(
              alignment: Alignment.centerRight,
              child: Text(
                pool.formattedTarget,
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 11,
                  color: zt.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.participants});

  final List<PoolParticipant> participants;

  static const double _size = 22;
  static const double _overlap = 6;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final visible = participants.take(3).toList();
    final overflow = participants.length - 3;

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
                backgroundColor: zt.accent,
                child: Text(
                  visible[i].avatarLabel,
                  style: TextStyle(
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
                backgroundColor: zt.bgSecondary,
                child: Text(
                  '+$overflow',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: zt.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
