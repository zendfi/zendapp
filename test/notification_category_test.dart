// Regression test for the client-side notification category mapping.
//
// This mapping MUST stay in exact sync with NotificationCategory::from_type()
// in src/push_notifications.rs (Rust) — both sides independently derive the
// same category from the same `type` string, and the client's derived
// Android channel_id must match what the server puts in the FCM payload
// (android.notification.channel_id), since Android routes a background/
// killed-app notification using whatever channel_id arrives with it. If the
// two map a `type` differently, background notifications and foreground/
// local notifications for the same event end up in different Android
// channels — silently splitting a user's per-channel mute setting.
import 'package:flutter_test/flutter_test.dart';

import 'package:zendapp/src/models/notification_category.dart';

void main() {
  group('NotificationCategoryKindX.fromType', () {
    test('chat category', () {
      expect(NotificationCategoryKindX.fromType('dm_message'), NotificationCategoryKind.chat);
      expect(NotificationCategoryKindX.fromType('pool_message'), NotificationCategoryKind.chat);
    });

    test('activity category', () {
      for (final t in [
        'activity_edge_reaction',
        'activity_edge_comment',
        'disclosure_digest',
        'activity_shared_by_mutual',
        'streak_milestone',
        'streak_break',
      ]) {
        expect(NotificationCategoryKindX.fromType(t), NotificationCategoryKind.activity,
            reason: 'type "$t" should map to activity');
      }
    });

    test('pools category', () {
      for (final t in [
        'pool_contribution',
        'pool_completed',
        'pool_expired',
        'pool_cancelled',
      ]) {
        expect(NotificationCategoryKindX.fromType(t), NotificationCategoryKind.pools,
            reason: 'type "$t" should map to pools');
      }
    });

    test('savings category', () {
      expect(NotificationCategoryKindX.fromType('goal_progress'), NotificationCategoryKind.savings);
    });

    test('unrecognized and money-related types fall back to transfers', () {
      for (final t in [
        'transfer_received',
        'transfer_confirmed',
        'drop_confirmed',
        'bank_send_confirmed',
        'payin_received',
        'deposit_received',
        'telegram_intent_claimed',
        'payment_request',
        'some_totally_unknown_future_type',
        '',
      ]) {
        expect(NotificationCategoryKindX.fromType(t), NotificationCategoryKind.transfers,
            reason: 'type "$t" should fail safe to transfers');
      }
    });
  });

  group('storage keys match the backend contract exactly', () {
    test('every category has the expected stable storage key', () {
      expect(NotificationCategoryKind.transfers.storageKey, 'transfers');
      expect(NotificationCategoryKind.chat.storageKey, 'chat');
      expect(NotificationCategoryKind.activity.storageKey, 'activity');
      expect(NotificationCategoryKind.pools.storageKey, 'pools');
      expect(NotificationCategoryKind.savings.storageKey, 'savings');
    });

    test('storage keys are all distinct', () {
      final keys = NotificationCategoryKind.values.map((c) => c.storageKey).toSet();
      expect(keys.length, NotificationCategoryKind.values.length);
    });
  });

  group('Android channel IDs', () {
    test('every category has a distinct, stable channel id', () {
      final ids = NotificationCategoryKind.values.map((c) => c.androidChannelId).toSet();
      expect(ids.length, NotificationCategoryKind.values.length,
          reason: 'two categories sharing a channel id would let muting one '
              'silently mute the other, which is exactly the bug this feature fixes');
      expect(NotificationCategoryKind.transfers.androidChannelId, 'zend_transfers',
          reason: 'must match the pre-existing channel id used before this '
              'feature existed, so already-created channels on real devices '
              'are reused rather than orphaned');
    });
  });
}
