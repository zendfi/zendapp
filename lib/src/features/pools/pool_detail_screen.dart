import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import 'contribute_sheet.dart';
import 'manage_sheet.dart';
import 'mission_room.dart';
import 'pool.dart';
import 'pool_progress_bar.dart';

class PoolDetailScreen extends StatefulWidget {
  const PoolDetailScreen({super.key, required this.pool});

  final Pool pool;

  @override
  State<PoolDetailScreen> createState() => _PoolDetailScreenState();
}

class _PoolDetailScreenState extends State<PoolDetailScreen> {
  late Pool _pool;

  @override
  void initState() {
    super.initState();
    _pool = widget.pool;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}';

  Color _statusColor(PoolStatus status) => switch (status) {
        PoolStatus.active => ZendColors.accentBright,
        PoolStatus.completed => ZendColors.accent,
        PoolStatus.expired => ZendColors.destructive,
        PoolStatus.cancelled => ZendColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final isCreator = model.currentUserId == _pool.creatorUserId;
    final isActive = _pool.status == PoolStatus.active;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: ZendColors.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pool name
                        Text(
                          _pool.name,
                          style: const TextStyle(
                            fontFamily: 'InstrumentSerif',
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: ZendColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: ZendSpacing.sm),

                        // Status badge
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(_pool.status)
                                  .withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(ZendRadii.pill),
                            ),
                            child: Text(
                              _pool.status.name,
                              style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _statusColor(_pool.status),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: ZendSpacing.md),

                        if (_pool.status == PoolStatus.completed)
                          _StatusBanner(
                            message: 'Goal reached! 🎉',
                            color: ZendColors.accent,
                          ),
                        if (_pool.status == PoolStatus.expired)
                          _StatusBanner(
                            message: 'Pool expired',
                            color: ZendColors.destructive,
                          ),
                        if (_pool.status == PoolStatus.cancelled)
                          _StatusBanner(
                            message: 'Pool cancelled',
                            color: ZendColors.textSecondary,
                          ),

                        Text(
                          '${_pool.formattedGathered} of ${_pool.formattedTarget}',
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 15,
                            color: ZendColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: ZendSpacing.xs),

                        PoolProgressBar(progress: _pool.progress),
                        const SizedBox(height: ZendSpacing.lg),

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
                        ..._pool.participants.map(_buildParticipantRow),
                        const SizedBox(height: ZendSpacing.lg),

                        _TimelineRow(
                          label: 'Created',
                          value: _formatDate(_pool.createdAt),
                        ),
                        const SizedBox(height: ZendSpacing.xs),
                        _TimelineRow(
                          label: 'Deadline',
                          value: _pool.deadline != null
                              ? _formatDate(_pool.deadline!)
                              : 'No deadline',
                        ),
                        const SizedBox(height: ZendSpacing.lg),
                      ],
                    ),
                  ),

                  Expanded(
                    child: MissionRoom(pool: _pool),
                  ),
                ],
              ),
            ),

            if (isActive)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    if (!isCreator) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => showContributeSheet(
                            context,
                            pool: _pool,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ZendColors.textPrimary,
                            side: const BorderSide(color: ZendColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(ZendRadii.lg),
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
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
                    ],
                    if (isCreator)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => showManageSheet(
                            context,
                            pool: _pool,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ZendColors.accent,
                            foregroundColor: ZendColors.textOnDeep,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(ZendRadii.lg),
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
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

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.color});
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: ZendSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: ZendSpacing.md, vertical: ZendSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ZendRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
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
