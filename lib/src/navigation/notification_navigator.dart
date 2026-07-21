import 'dart:async';

import 'package:flutter/material.dart';

import '../core/zend_state.dart';
import '../features/activity/activity_comment_sheet.dart';
import '../features/activity/public_feed_screen.dart';
import '../features/dm/dm_thread_screen.dart';
import '../features/pools/pool_detail_screen.dart';
import '../features/pools/mission_room_sheet.dart';
import '../features/savings/savings_screen.dart';
import '../models/activity_edge.dart';
import '../models/dm_thread.dart';
import '../models/notification_destination.dart';
import 'zend_routes.dart';
import 'zend_shell_controller.dart';

extension _NullableFirst<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) { if (test(e)) return e; }
    return null;
  }
}

/// Routes a [NotificationDestination] to the correct screen.
///
/// All navigation is performed via [BuildContext] from the root navigator,
/// so this works from app.dart's `_navigatorKey` — outside any specific
/// widget subtree. Callers must ensure the user is authenticated and unlocked
/// before calling.
class NotificationNavigator {
  static Future<void> dispatch(
    BuildContext context,
    NotificationDestination dest,
    ZendAppModel model,
  ) async {
    switch (dest) {
      // ── Activity: show the threaded feed, optionally open a specific edge ──
      case NotifActivityFeed(:final focusSenderZendtag, :final focusTransferId):
        ZendShellController.instance?.switchToTab(2);
        if (focusTransferId == null && focusSenderZendtag == null) return;
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (!context.mounted) return;
        final edge = model.threadedActivityEdges.firstWhereOrNull((e) {
          if (focusTransferId != null) return e.edgeId == focusTransferId;
          return e.senderZendtag == focusSenderZendtag ||
              e.recipientZendtag == focusSenderZendtag;
        });
        if (edge != null && context.mounted) {
          _openCommentSheet(context, edge, model);
        }

      // ── Activity: open a specific edge's comment sheet ──────────────────────
      case NotifActivityEdge(:final edgeId):
        ZendShellController.instance?.switchToTab(2);
        // Trigger a fetch so the edge is available if it's not yet loaded.
        unawaited(model.fetchThreadedActivity());
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!context.mounted) return;
        final edge = model.threadedActivityEdges.firstWhereOrNull(
          (e) => e.edgeId == edgeId,
        );
        if (edge != null && context.mounted) {
          _openCommentSheet(context, edge, model);
        }

      // ── Public feed ──────────────────────────────────────────────────────────
      case NotifPublicFeed():
        ZendShellController.instance?.switchToTab(2);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!context.mounted) return;
        pushZendSlide(context, const PublicFeedScreen(), rootNavigator: true);

      // ── Pool detail ──────────────────────────────────────────────────────────
      case NotifPoolDetail(:final poolId):
        final pool = model.pools.firstWhereOrNull((p) => p.id == poolId);
        if (pool == null) {
          unawaited(model.fetchPools());
          ZendShellController.instance?.switchToTab(0);
          return;
        }
        if (!context.mounted) return;
        pushZendSlide(context, PoolDetailScreen(pool: pool), rootNavigator: true);

      // ── Pool chat: open pool detail then immediately open mission room ────────
      case NotifPoolChat(:final poolId):
        final pool = model.pools.firstWhereOrNull((p) => p.id == poolId);
        if (pool == null) {
          unawaited(model.fetchPools());
          ZendShellController.instance?.switchToTab(0);
          return;
        }
        if (!context.mounted) return;
        pushZendSlide(context, PoolDetailScreen(pool: pool), rootNavigator: true);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!context.mounted) return;
        showMissionRoomSheet(context, pool: pool);

      // ── Home / Money tab ─────────────────────────────────────────────────────
      case NotifHomeFeed():
        ZendShellController.instance?.switchToTab(0);

      // ── Savings ──────────────────────────────────────────────────────────────
      case NotifSavings():
        ZendShellController.instance?.switchToTab(0);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!context.mounted) return;
        pushZendSlide(context, const SavingsScreen(), rootNavigator: true);

      // ── DM thread ────────────────────────────────────────────────────────────
      case NotifDmThread(:final roomId):
        ZendShellController.instance?.switchToTab(3);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!context.mounted) return;
        // Try to find the counterparty from the loaded thread list
        final thread = model.dmService.cachedThreads
            .firstWhere((t) => t.roomId == roomId, orElse: () =>
                DmThread(
                  roomId: roomId,
                  counterparty: const DmCounterparty(
                    userId: '', zendtag: '', displayName: 'Message'),
                  unreadCount: 0,
                  lastMessageAt: DateTime.now(),
                ));
        if (!context.mounted) return;
        pushZendSlide(
          context,
          DmThreadScreen(roomId: roomId, counterparty: thread.counterparty),
          rootNavigator: true,
        );
    }
  }

  static void _openCommentSheet(
    BuildContext context,
    ActivityEdge edge,
    ZendAppModel model,
  ) {
    final isOutgoing = edge.isOutgoing;
    final verb = 'paid'; // neutral fallback — full feedVerbFor is in activity_grouping
    final counterpartyLabel = isOutgoing
        ? (edge.recipientZendtag != null ? '@${edge.recipientZendtag}' : 'someone')
        : (edge.senderZendtag != null ? '@${edge.senderZendtag}' : 'someone');
    final headline = edge.direction == 'external'
        ? '${edge.senderZendtag != null ? '@${edge.senderZendtag}' : 'Someone'} $verb '
            '${edge.recipientZendtag != null ? '@${edge.recipientZendtag}' : 'someone'}'
        : isOutgoing
            ? 'You $verb $counterpartyLabel'
            : '$counterpartyLabel $verb you';

    showActivityCommentSheet(
      context,
      edge: edge,
      headline: headline,
      avatarUrl: isOutgoing ? model.currentAvatarUrl : edge.senderAvatarUrl,
      avatarInitial: isOutgoing
          ? (model.currentZendtag?.isNotEmpty == true
              ? model.currentZendtag![0].toUpperCase()
              : 'Y')
          : (edge.senderZendtag?.isNotEmpty == true
              ? edge.senderZendtag![0].toUpperCase()
              : '?'),
      onViewReceipt: () => Navigator.of(context).pop(),
    );
  }
}
