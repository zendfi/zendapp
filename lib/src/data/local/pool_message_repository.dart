import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../models/pool_message_local.dart';
import 'app_database.dart';

class PoolMessageRepository {
  final AppDatabase _db;

  PoolMessageRepository(this._db);

  Future<Database> get _database => _db.database;

  PoolMessageLocal _fromMap(Map<String, dynamic> map) {
    List<double>? waveform;
    if (map['waveform_data'] != null) {
      try {
        final list = jsonDecode(map['waveform_data'] as String) as List;
        waveform = list.map((e) => (e as num).toDouble()).toList();
      } catch (_) {}
    }
    return PoolMessageLocal(
      id: map['id'] as String,
      poolId: map['pool_id'] as String,
      clientId: map['client_id'] as String?,
      serverId: map['server_id'] as String?,
      senderUserId: map['sender_user_id'] as String?,
      senderZendtag: map['sender_zendtag'] as String?,
      senderAvatarUrl: map['sender_avatar_url'] as String?,
      messageType: map['message_type'] as String,
      content: map['content'] as String?,
      contributionId: map['contribution_id'] as String?,
      voiceNoteUrl: map['voice_note_url'] as String?,
      voiceNoteDurationSeconds: map['voice_note_duration_seconds'] as int?,
      waveformData: waveform,
      localStatus: _statusFromString(
        map['local_status'] as String? ?? 'delivered',
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  LocalStatus _statusFromString(String s) {
    switch (s) {
      case 'sending':
        return LocalStatus.sending;
      case 'failed':
        return LocalStatus.failed;
      default:
        return LocalStatus.delivered;
    }
  }

  String _statusToString(LocalStatus s) {
    switch (s) {
      case LocalStatus.sending:
        return 'sending';
      case LocalStatus.failed:
        return 'failed';
      case LocalStatus.delivered:
        return 'delivered';
    }
  }

  Map<String, dynamic> _toMap(PoolMessageLocal msg) {
    return {
      'id': msg.id,
      'pool_id': msg.poolId,
      'client_id': msg.clientId,
      'server_id': msg.serverId,
      'sender_user_id': msg.senderUserId,
      'sender_zendtag': msg.senderZendtag,
      'sender_avatar_url': msg.senderAvatarUrl,
      'message_type': msg.messageType,
      'content': msg.content,
      'contribution_id': msg.contributionId,
      'voice_note_url': msg.voiceNoteUrl,
      'voice_note_duration_seconds': msg.voiceNoteDurationSeconds,
      'waveform_data':
          msg.waveformData != null ? jsonEncode(msg.waveformData) : null,
      'local_status': _statusToString(msg.localStatus),
      'created_at': msg.createdAt.toIso8601String(),
    };
  }

  /// Returns the most recent [limit] messages for [poolId], ordered ASC.
  Future<List<PoolMessageLocal>> getRecentMessages(
    String poolId, {
    int limit = 50,
  }) async {
    final db = await _database;
    // Fetch DESC then reverse so the result is chronological (ASC).
    final rows = await db.query(
      'pool_messages',
      where: 'pool_id = ?',
      whereArgs: [poolId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.reversed.map(_fromMap).toList();
  }

  /// Returns up to [limit] messages older than [beforeCreatedAt], ordered ASC.
  Future<List<PoolMessageLocal>> getOlderMessages(
    String poolId,
    String beforeCreatedAt, {
    int limit = 50,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'pool_messages',
      where: 'pool_id = ? AND created_at < ?',
      whereArgs: [poolId, beforeCreatedAt],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_fromMap).toList();
  }

  /// Inserts or replaces a message row (conflict on primary key `id`).
  Future<void> upsertMessage(PoolMessageLocal msg) async {
    final db = await _database;
    await db.insert(
      'pool_messages',
      _toMap(msg),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Updates the delivery status of a message identified by [clientId].
  ///
  /// Enforces monotonic transitions: a `delivered` message is never
  /// downgraded to `sending` or `failed`.
  ///
  /// When [serverId] is provided the row is re-keyed: the old row is deleted
  /// and a new one is inserted with `server_id` as the primary key.
  Future<void> updateStatus(
    String clientId,
    LocalStatus status, {
    String? serverId,
    DateTime? serverCreatedAt,
  }) async {
    final db = await _database;

    final existing = await db.query(
      'pool_messages',
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (existing.isEmpty) return;

    final currentStatus = _statusFromString(
      existing.first['local_status'] as String? ?? 'delivered',
    );
    // Monotonic guard: delivered cannot regress.
    if (currentStatus == LocalStatus.delivered) return;

    if (serverId != null) {
      // Re-key the row so its primary key becomes the server-assigned ID.
      final oldRow = Map<String, dynamic>.from(existing.first);
      oldRow['id'] = serverId;
      oldRow['server_id'] = serverId;
      oldRow['local_status'] = _statusToString(status);
      if (serverCreatedAt != null) {
        oldRow['created_at'] = serverCreatedAt.toIso8601String();
      }
      await db.delete(
        'pool_messages',
        where: 'client_id = ?',
        whereArgs: [clientId],
      );
      await db.insert(
        'pool_messages',
        oldRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    await db.update(
      'pool_messages',
      {'local_status': _statusToString(status)},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Returns all messages for [poolId] that are still in `sending` state,
  /// ordered by `created_at` ASC (for outbox re-population on restart).
  Future<List<PoolMessageLocal>> getPendingMessages(String poolId) async {
    final db = await _database;
    final rows = await db.query(
      'pool_messages',
      where: 'pool_id = ? AND local_status = ?',
      whereArgs: [poolId, 'sending'],
      orderBy: 'created_at ASC',
    );
    return rows.map(_fromMap).toList();
  }

  /// Replaces all reaction rows for [messageId] with [reactions].
  Future<void> upsertReactions(
    String messageId,
    List<Map<String, dynamic>> reactions,
  ) async {
    final db = await _database;
    await db.delete(
      'pool_message_reactions',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    for (final r in reactions) {
      await db.insert(
        'pool_message_reactions',
        {
          'message_id': messageId,
          'emoji': r['emoji'] as String,
          'count': r['count'] as int,
          'reacted_by_me': (r['reacted_by_me'] as bool? ?? false) ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Returns the sync cursor for [poolId], or `null` if none exists.
  Future<Map<String, dynamic>?> getCursor(String poolId) async {
    final db = await _database;
    final rows = await db.query(
      'pool_sync_cursors',
      where: 'pool_id = ?',
      whereArgs: [poolId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Upserts the sync cursor for [poolId].
  Future<void> upsertCursor(
    String poolId, {
    String? oldestFetchedServerId,
  }) async {
    final db = await _database;
    await db.insert(
      'pool_sync_cursors',
      {
        'pool_id': poolId,
        'oldest_fetched_server_id': oldestFetchedServerId,
        'last_synced_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
