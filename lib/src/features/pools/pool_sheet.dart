import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../services/sse_service.dart';
import 'contribute_sheet.dart';
import 'manage_sheet.dart';
import 'pool.dart';
import 'pool_progress_bar.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// The Pool Sheet — ZEND BETA spec §34 (LOCKED wireframe): name,
/// gathered/target, progress bar, Contribute button, participant list.
/// Reached exclusively via the Pool icon in [PoolDetailScreen]'s chat
/// header (spec §33) — never a standalone navigation destination, per
/// spec §31 ("Pools don't need their own global navigation").
///
/// Handles both the with-target (spec §36) and without-target (spec §35)
/// cases, and the target-reached / pool-closed state (spec §38-39): the
/// financial lifecycle can end (no more Contribute) while the chat this
/// sheet sits on top of remains fully writable.
Future<void> showPoolSheet(
  BuildContext context, {
  required Pool pool,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PoolSheet(pool: pool),
  );
}

class PoolSheet extends StatefulWidget {
  const PoolSheet({super.key, required this.pool});

  final Pool pool;

  @override
  State<PoolSheet> createState() => _PoolSheetState();
}

class _PoolSheetState extends State<PoolSheet> {
  late Pool _pool;
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void initState() {
    super.initState();
    _pool = widget.pool;
    // ContributeSheet/ManageSheet don't mutate the pool they're given or
    // return an updated one — the actual source of truth for a gathered
    // amount or status change is the same SSE stream PoolDetailScreen
    // already listens to underneath this sheet. Subscribing independently
    // here (rather than threading a callback through the parent) keeps
    // this sheet correct regardless of which action sheet was opened, and
    // survives this sheet being reopened without the parent screen
    // needing to know about it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final model = ZendScope.of(context);
      _sseSub = model.sseService.events.listen(_onSseEvent);
    });
  }

  void _onSseEvent(SseEvent event) {
    if (!mounted) return;
    final data = event.data;
    final poolId = data['pool_id'] as String?;
    if (poolId != _pool.id) return;

    switch (event.type) {
      case SseEventType.poolContribution:
        final gatheredStr = data['gathered_amount_usdc'] as String?;
        if (gatheredStr != null) {
          final gathered = double.tryParse(gatheredStr);
          if (gathered != null) setState(() => _pool.gathered = gathered);
        }
      case SseEventType.poolStatusChanged:
        final newStatus = data['new_status'] as String?;
        if (newStatus != null) {
          const statusMap = {
            'active': PoolStatus.active,
            'completed': PoolStatus.completed,
            'expired': PoolStatus.expired,
            'cancelled': PoolStatus.cancelled,
          };
          final status = statusMap[newStatus];
          if (status != null) setState(() => _pool.status = status);
        }
      default:
        break;
    }
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  Future<void> _openContribute() async {
    await showContributeSheet(context, pool: _pool);
  }

  Future<void> _openManage() async {
    await showManageSheet(context, pool: _pool);
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final isCreator = model.currentUserId == _pool.creatorUserId;
    final isActive = _pool.status == PoolStatus.active;
    final hasTarget = _pool.targetAmount > 0;

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        decoration: BoxDecoration(
          color: zt.bgPrimary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary),
                    ),
                    const Spacer(),
                    // Admin entry point — spec §40: "The exact
                    // admin-management UI should remain intentionally
                    // small." A single icon, not a promoted button.
                    if (isCreator && isActive)
                      IconButton(
                        onPressed: _openManage,
                        icon: Icon(PhosphorIconsRegular.gearSix, color: zt.textSecondary, size: 20),
                        tooltip: 'Manage pool',
                      ),
                    if (_pool.shortCode != null)
                      IconButton(
                        onPressed: () => Share.share(
                          'Join my Zend pool: https://zdfi.me/pool/${_pool.shortCode}',
                          subject: _pool.name,
                        ),
                        icon: Icon(PhosphorIconsRegular.share, color: zt.textSecondary, size: 20),
                        tooltip: 'Share pool link',
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Text(
                          _pool.name,
                          style: TextStyle(fontFamily: 'Geist', fontSize: 22, fontWeight: FontWeight.w700, color: zt.textPrimary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ── Gathered / target — with or without a target (spec §35-36) ──
                      Center(
                        child: Column(
                          children: [
                            Text(
                              _pool.formattedGathered,
                              style: TextStyle(fontFamily: 'Geist', fontSize: 32, fontWeight: FontWeight.w700, color: zt.textPrimary),
                            ),
                            if (hasTarget) ...[
                              const SizedBox(height: 2),
                              Text(
                                'of ${_pool.formattedTarget}',
                                style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (hasTarget) ...[
                        const SizedBox(height: 16),
                        PoolProgressBar(progress: _pool.progress, style: PoolProgressBarStyle.line, height: 8),
                      ],
                      const SizedBox(height: 20),

                      // ── Status: target reached / closed (spec §38-39) ──
                      if (!isActive)
                        Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: zt.bgSecondary,
                            borderRadius: BorderRadius.circular(ZendRadii.lg),
                          ),
                          child: Text(
                            _pool.status == PoolStatus.completed
                                ? 'Target reached. Pool closed — no further contributions can be made. Chat remains open.'
                                : _pool.status == PoolStatus.cancelled
                                    ? 'Pool closed. No further contributions can be made. Chat remains open.'
                                    : 'Pool expired. No further contributions can be made. Chat remains open.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
                          ),
                        )
                      else
                        // Spec §40 doesn't exclude the creator from
                        // contributing — only Manage (the gear icon above)
                        // is creator-only. Contribute is the same button
                        // for every active participant.
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: PrimaryButton(label: 'Contribute', onPressed: _openContribute),
                        ),

                      // ── Open-contribution link (spec §6.3-6.4) ──
                      if (isActive && _pool.allowOpenContributions && _pool.shortCode != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: OutlineActionButton(
                            label: 'Share contribution link',
                            onPressed: () => Share.share(
                              'Contribute to "${_pool.name}": https://zdfi.me/pool/${_pool.shortCode}',
                              subject: _pool.name,
                            ),
                          ),
                        ),

                      Divider(color: zt.border, height: 1),
                      const SizedBox(height: 14),

                      // ── Participants ──
                      ..._pool.participants.map(_buildParticipantRow),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantRow(PoolParticipant p) {
    final zt = ZendTheme.of(context);
    final contribution = p.contribution == 0 ? '\$0.00' : '\$${p.contribution.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          ZendAvatar(radius: 16, photoUrl: p.avatarUrl, initials: p.avatarLabel),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.displayName, style: TextStyle(fontFamily: 'Geist', fontSize: 15, color: zt.textPrimary)),
                if (p.isExternal)
                  Text('external', style: TextStyle(fontFamily: 'Geist', fontSize: 11, color: zt.textSecondary)),
              ],
            ),
          ),
          Text(contribution, style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 13, color: zt.textPrimary)),
        ],
      ),
    );
  }
}
