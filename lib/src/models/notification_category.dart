/// Notification categories shared between the client and backend.
///
/// Every push notification `type` (see [NotificationDestination.fromData])
/// belongs to exactly one of these. Two things key off it:
///
/// 1. Which Android notification channel a local/foreground notification
///    uses — previously every notification hardcoded the same
///    "zend_transfers" channel regardless of whether it was a $500 incoming
///    transfer or a DM, so muting one at the OS level silently muted both.
/// 2. Whether the backend even sends the FCM push at all — see
///    `PATCH /api/zend/notifications/preferences` and
///    `NotificationCategory::storage_key()` on the Rust side
///    (`src/push_notifications.rs`). [storageKey] here MUST exactly match
///    the Rust enum's storage keys ('transfers' | 'chat' | 'activity' |
///    'pools' | 'savings') — they're compared as plain strings server-side.
enum NotificationCategoryKind { transfers, chat, activity, pools, savings }

extension NotificationCategoryKindX on NotificationCategoryKind {
  /// Stable string persisted both in SharedPreferences (client) and in
  /// `users.notification_muted_categories` (server). Never rename these
  /// without a migration on both sides — existing stored values would
  /// silently stop matching.
  String get storageKey => switch (this) {
        NotificationCategoryKind.transfers => 'transfers',
        NotificationCategoryKind.chat => 'chat',
        NotificationCategoryKind.activity => 'activity',
        NotificationCategoryKind.pools => 'pools',
        NotificationCategoryKind.savings => 'savings',
      };

  /// Android notification channel ID. Must match the channel_id the backend
  /// puts in the FCM payload's `android.notification.channel_id`
  /// (`NotificationCategory::android_channel_id()` in push_notifications.rs)
  /// — Android routes a background/killed-app notification using whatever
  /// channel_id arrives in the payload, so client and server must agree.
  String get androidChannelId => switch (this) {
        NotificationCategoryKind.transfers => 'zend_transfers',
        NotificationCategoryKind.chat => 'zend_chat',
        NotificationCategoryKind.activity => 'zend_activity',
        NotificationCategoryKind.pools => 'zend_pools',
        NotificationCategoryKind.savings => 'zend_savings',
      };

  String get androidChannelName => switch (this) {
        NotificationCategoryKind.transfers => 'Transfers',
        NotificationCategoryKind.chat => 'Messages',
        NotificationCategoryKind.activity => 'Activity',
        NotificationCategoryKind.pools => 'Pools',
        NotificationCategoryKind.savings => 'Savings',
      };

  String get androidChannelDescription => switch (this) {
        NotificationCategoryKind.transfers =>
          'Incoming and outgoing money: transfers, drops, deposits, bank sends',
        NotificationCategoryKind.chat => 'Direct messages and pool group chat',
        NotificationCategoryKind.activity =>
          'Reactions, comments, streaks and shared activity',
        NotificationCategoryKind.pools =>
          'Pool contributions and lifecycle updates',
        NotificationCategoryKind.savings => 'Savings goal progress',
      };

  /// Maps a push notification `type` field to its category. Mirrors
  /// `NotificationCategory::from_type()` in push_notifications.rs exactly —
  /// keep the two in sync. Falls back to [transfers] for unrecognized
  /// types, matching the backend's fail-safe default (money-related
  /// notifications must never be silently miscategorized as mutable).
  static NotificationCategoryKind fromType(String notifType) {
    switch (notifType) {
      case 'dm_message':
      case 'pool_message':
        return NotificationCategoryKind.chat;
      case 'activity_edge_reaction':
      case 'activity_edge_comment':
      case 'disclosure_digest':
      case 'activity_shared_by_mutual':
      case 'streak_milestone':
      case 'streak_break':
        return NotificationCategoryKind.activity;
      case 'pool_contribution':
      case 'pool_completed':
      case 'pool_expired':
      case 'pool_cancelled':
        return NotificationCategoryKind.pools;
      case 'goal_progress':
        return NotificationCategoryKind.savings;
      default:
        return NotificationCategoryKind.transfers;
    }
  }
}
