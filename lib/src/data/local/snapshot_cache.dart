import 'dart:convert';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'app_database.dart';

/// Persists "what the user saw last time" so launch can paint real content
/// instead of a loading skeleton.
///
/// ── Why this exists ────────────────────────────────────────────────────
/// Before this, nothing except pool chat rendered from disk. A cold launch
/// landed on Feed (the default tab) and showed a shimmer until the network
/// answered, and the balance — the number people open the app to look at —
/// came from the wire every single time. That makes the app feel slow even
/// when it is working perfectly, because the wait is unconditional.
///
/// ── Scoping and lifetime ───────────────────────────────────────────────
/// Every entry is keyed by user id as well as by [key]. A device signed into
/// a second account must never render the first account's balance or feed,
/// not even for a frame. [clearForUser] is called on sign-out.
///
/// ── Freshness ──────────────────────────────────────────────────────────
/// Reads are refused past [maxAge]. A cached balance is shown as if current,
/// so the honest bound on how wrong it can be matters more here than in a
/// typical cache: this is money. The live value replaces it as soon as
/// `fetchBalance()` returns, which is fired immediately on authentication —
/// the stale window is normally a few hundred milliseconds, and [maxAge]
/// exists for the offline case where it never closes.
class SnapshotCache {
  SnapshotCache(this._db);

  final AppDatabase _db;

  static const _table = 'ui_snapshots';

  /// Balance + spendable balance.
  static const keyBalance = 'balance';

  /// The first page of the Activity feed, stored as the same JSON the API
  /// returns so it round-trips through `ActivityEdge.fromJson` with no
  /// separate cache schema to drift out of sync.
  static const keyFeedPage1 = 'feed_page_1';

  /// Past this, a snapshot is treated as absent. Deliberately short for a
  /// financial figure — a day-old balance presented as current is worse than
  /// a skeleton.
  static const Duration maxAge = Duration(hours: 12);

  /// Never throws. A cache is an optimisation; a failure to read or write one
  /// must not be able to take a screen (or a transfer) down with it.
  Future<void> put(String userId, String key, Object payload) async {
    if (userId.isEmpty) return;
    try {
      final db = await _db.database;
      await db.insert(
        _table,
        {
          'user_id': userId,
          'key': key,
          'payload': jsonEncode(payload),
          'saved_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Best-effort.
    }
  }

  /// Returns the decoded payload, or null if absent, unreadable or older
  /// than [maxAge].
  Future<Object?> get(String userId, String key) async {
    if (userId.isEmpty) return null;
    try {
      final db = await _db.database;
      final rows = await db.query(
        _table,
        columns: ['payload', 'saved_at'],
        where: 'user_id = ? AND key = ?',
        whereArgs: [userId, key],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final savedAt = DateTime.tryParse(rows.first['saved_at'] as String? ?? '');
      if (savedAt == null || DateTime.now().toUtc().difference(savedAt) > maxAge) {
        return null;
      }
      return jsonDecode(rows.first['payload'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getMap(String userId, String key) async {
    final value = await get(userId, key);
    return value is Map<String, dynamic> ? value : null;
  }

  /// Drops every snapshot for one account. Called on sign-out so the next
  /// person to use the device can't see the previous one's figures.
  Future<void> clearForUser(String userId) async {
    if (userId.isEmpty) return;
    try {
      final db = await _db.database;
      await db.delete(_table, where: 'user_id = ?', whereArgs: [userId]);
    } catch (_) {
      // Best-effort.
    }
  }
}
