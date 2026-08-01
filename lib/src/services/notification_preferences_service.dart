import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_category.dart';
import 'api_client.dart';

/// Single source of truth for which notification categories the user has
/// muted, backed by SharedPreferences locally and synced to the backend.
///
/// Before this existed, each of the three "mute notifications" toggles
/// (DM list, threaded activity, legacy activity list) read/wrote its own
/// isolated SharedPreferences key and only ever affected the in-app banner —
/// the backend had no idea a category was muted and kept sending the FCM
/// push regardless. This service is the one place that:
///   1. Persists the muted set locally (so the toggle's UI state survives
///      app restarts without a network round trip).
///   2. Pushes the full set to `PATCH /api/zend/notifications/preferences`
///      so the backend actually stops sending pushes for muted categories
///      (see `send_push_notification`'s `is_category_muted` check in
///      src/push_notifications.rs).
///
/// Read is synchronous-after-[load] via [isMuted]; callers should call
/// [load] once (e.g. in initState) before relying on [isMuted]/[mutedSet].
class NotificationPreferencesService {
  NotificationPreferencesService({required ApiClient apiClient})
      : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const _prefsKey = 'notification_muted_categories';

  Set<NotificationCategoryKind> _muted = {};
  bool _loaded = false;

  /// Loads the persisted muted set from SharedPreferences. Safe to call
  /// multiple times — subsequent calls are a no-op once loaded, so several
  /// screens can each call this in their own initState without redundant
  /// disk reads racing each other.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey) ?? const [];
    _muted = stored
        .map(_categoryFromStorageKey)
        .whereType<NotificationCategoryKind>()
        .toSet();
    _loaded = true;
  }

  bool isMuted(NotificationCategoryKind category) => _muted.contains(category);

  /// Sets [category]'s muted state, persists it locally, and syncs the full
  /// set to the backend. Returns after the local write completes — the
  /// backend sync is fire-and-forget (a transient network failure here
  /// should not block the UI toggle or silently revert it; the backend
  /// fails open on read errors too, see `is_category_muted`).
  Future<void> setMuted(NotificationCategoryKind category, bool muted) async {
    if (muted) {
      _muted.add(category);
    } else {
      _muted.remove(category);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      _muted.map((c) => c.storageKey).toList(),
    );

    try {
      await _apiClient.updateNotificationPreferences(
        _muted.map((c) => c.storageKey).toList(),
      );
    } catch (_) {
      // Non-fatal — the local toggle already reflects the user's choice;
      // the in-app banner (the client-side suppression) still respects it
      // regardless of whether the backend sync succeeded. Next successful
      // toggle (of any category) will resend the full current set anyway.
    }
  }

  static NotificationCategoryKind? _categoryFromStorageKey(String key) {
    for (final c in NotificationCategoryKind.values) {
      if (c.storageKey == key) return c;
    }
    return null;
  }
}
