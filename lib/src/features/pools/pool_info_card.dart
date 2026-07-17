import 'package:flutter/material.dart';

import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import 'pool.dart';
import 'pool_list_drawer.dart';
import 'pool_progress_bar.dart';

class PoolInfoCard extends StatelessWidget {
  const PoolInfoCard({
    super.key,
    required this.pool,
    required this.onTap,
    this.hasNewMessage = false,
  });

  final Pool pool;
  final VoidCallback onTap;
  /// When true, renders a small "new message" dot badge on the card.
  final bool hasNewMessage;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
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
          // New-message badge — top-right corner of the card
          if (hasNewMessage)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: ZendColors.destructive,
                  shape: BoxShape.circle,
                  border: Border.all(color: zt.bgPrimary, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.participants});

  final List<PoolParticipant> participants;

  // Slightly larger than before for visual prominence
  static const double _size = 26;
  static const double _overlap = 7;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final visible = participants.take(4).toList();
    final overflow = participants.length - 4;

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
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: zt.bgCard, width: 1.5),
                ),
                child: ZendAvatar(
                  radius: _size / 2,
                  photoUrl: visible[i].avatarUrl,
                  initials: visible[i].avatarLabel,
                ),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * (_size - _overlap),
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  color: zt.bgSecondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: zt.bgCard, width: 1.5),
                ),
                alignment: Alignment.center,
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
