import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../services/sse_service.dart';
import 'mission_room.dart';
import 'pool.dart';
import 'pool_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// A Pool's primary surface — ZEND BETA spec §31-34: "A Pool begins as a
/// Group Chat with a shared wallet attached... the Chat is primary. The
/// Pool financial state is accessed through the Chat header."
///
/// This screen IS the group chat ([MissionRoom]) — not a financial
/// dashboard with a "Message" button bolted on. The header Pool icon
/// (spec §33: "Header Pool icon opens the Pool sheet") is the only route
/// into gathered/target amounts, Contribute, and participant contributions
/// — all of that now lives in [showPoolSheet], reached from here.
class PoolDetailScreen extends StatefulWidget {
  const PoolDetailScreen({super.key, required this.pool});

  final Pool pool;

  @override
  State<PoolDetailScreen> createState() => _PoolDetailScreenState();
}

class _PoolDetailScreenState extends State<PoolDetailScreen> {
  late Pool _pool;
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void initState() {
    super.initState();
    _pool = widget.pool;
    // Live-update pool status/gathered amount while this screen is open —
    // the header badge and the Pool sheet (when opened) both need to
    // reflect a contribution or status change that lands mid-session.
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

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header: ← Pool name  ◉ (spec §33 wireframe) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      _pool.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w700, color: zt.textPrimary),
                    ),
                  ),
                  IconButton(
                    onPressed: () => showPoolSheet(context, pool: _pool),
                    icon: Icon(PhosphorIconsRegular.usersThree, color: zt.textSecondary, size: 22),
                    tooltip: 'Pool details',
                  ),
                ],
              ),
            ),
            Divider(color: zt.border, height: 1),
            Expanded(child: MissionRoom(pool: _pool)),
          ],
        ),
      ),
    );
  }
}
