/// Typed tap-destination parsed from an FCM push notification's `data` payload.
///
/// Each variant carries exactly the IDs and metadata needed to navigate to
/// the right screen — no raw JSON after this point. The service layer
/// (`PushNotificationService._parseDestination`) builds these; `app.dart`'s
/// `_dispatchNotificationDestination` consumes them.
sealed class NotificationDestination {
  const NotificationDestination();

  /// Parse a raw FCM `data` map into a typed destination, or return null if
  /// the notification type is unknown or lacks required fields.
  factory NotificationDestination.fromData(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    switch (type) {
      // ── Financial ──────────────────────────────────────────────────────────
      case 'transfer_received':
      case 'drop_confirmed':
        final senderTag = data['sender_zendtag'] as String? ??
            data['counterparty_zendtag'] as String?;
        final transferId = data['transfer_id'] as String?;
        return NotifActivityFeed(
          focusSenderZendtag: senderTag,
          focusTransferId: transferId,
        );

      case 'transfer_confirmed':
        final recipientTag = data['recipient_zendtag'] as String?;
        final transferId = data['transfer_id'] as String?;
        return NotifActivityFeed(
          focusSenderZendtag: recipientTag,
          focusTransferId: transferId,
        );

      case 'bank_send_confirmed':
        // No deep-link target — just show the activity feed
        return const NotifActivityFeed();

      case 'payin_received':
      case 'deposit_received':
        // Money arrived from external source — show wallet balance
        return const NotifHomeFeed();

      case 'telegram_intent_claimed':
        return const NotifActivityFeed();

      // ── Social (activity edges) ────────────────────────────────────────────
      case 'activity_edge_reaction':
      case 'activity_edge_comment':
        final edgeKind = data['edge_kind'] as String?;
        final edgeId = data['edge_id'] as String?;
        if (edgeKind != null && edgeId != null) {
          return NotifActivityEdge(edgeKind: edgeKind, edgeId: edgeId);
        }
        return const NotifActivityFeed();

      case 'disclosure_digest':
        // Activities were shared — show the public feed
        return const NotifPublicFeed();

      case 'activity_shared_by_mutual':
        // A mutual shared an activity — show the public feed
        return const NotifPublicFeed();

      // ── Direct messages ────────────────────────────────────────────────────
      case 'dm_message':
        final roomId = data['room_id'] as String?;
        if (roomId != null) {
          return NotifDmThread(roomId: roomId);
        }
        return const NotifHomeFeed();

      // ── Streaks ────────────────────────────────────────────────────────────
      case 'streak_milestone':
      case 'streak_break':
        return const NotifActivityFeed();

      // ── Pools ──────────────────────────────────────────────────────────────
      case 'pool_message':
        final poolId = data['pool_id'] as String?;
        if (poolId != null) {
          return NotifPoolChat(poolId: poolId);
        }
        return const NotifActivityFeed();

      case 'pool_contribution':
      case 'pool_completed':
      case 'pool_expired':
      case 'pool_cancelled':
        final poolId = data['pool_id'] as String?;
        if (poolId != null) {
          return NotifPoolDetail(poolId: poolId);
        }
        return const NotifActivityFeed();

      // ── Savings ────────────────────────────────────────────────────────────
      case 'goal_progress':
        return const NotifSavings();

      default:
        return const NotifHomeFeed();
    }
  }
}

// ── Concrete destination types ────────────────────────────────────────────────

/// Navigate to the Activity tab (threaded feed). Optionally focus on a
/// specific sender's thread or a specific transfer, when the data is
/// available in the in-memory edge list.
final class NotifActivityFeed extends NotificationDestination {
  const NotifActivityFeed({this.focusSenderZendtag, this.focusTransferId});
  final String? focusSenderZendtag;
  final String? focusTransferId;
}

/// Navigate to the Activity tab and open the comment sheet for a specific
/// edge (identified by edgeKind + edgeId). Falls back to the Activity tab
/// if the edge is not found in the loaded list.
final class NotifActivityEdge extends NotificationDestination {
  const NotifActivityEdge({required this.edgeKind, required this.edgeId});
  final String edgeKind;
  final String edgeId;
}

/// Navigate to the Public Feed screen.
final class NotifPublicFeed extends NotificationDestination {
  const NotifPublicFeed();
}

/// Navigate to the Pool Detail screen for [poolId].
final class NotifPoolDetail extends NotificationDestination {
  const NotifPoolDetail({required this.poolId});
  final String poolId;
}

/// Navigate to the Pool Detail screen and then open the Mission Room sheet.
final class NotifPoolChat extends NotificationDestination {
  const NotifPoolChat({required this.poolId});
  final String poolId;
}

/// Navigate to the Home / Money tab.
final class NotifHomeFeed extends NotificationDestination {
  const NotifHomeFeed();
}

/// Navigate to the Savings screen.
final class NotifSavings extends NotificationDestination {
  const NotifSavings();
}

/// Navigate to a specific DM thread.
final class NotifDmThread extends NotificationDestination {
  const NotifDmThread({required this.roomId});
  final String roomId;
}
