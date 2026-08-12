import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dm_message.dart';
import '../models/dm_thread.dart';
import 'api_client.dart';

/// Sent/read timestamps for a single message — backs the message-info sheet.
class DmMessageInfo {
  const DmMessageInfo({required this.sentAt, this.readAt});
  final DateTime sentAt;
  /// Null if the counterparty hasn't read up to this message yet.
  final DateTime? readAt;
}

class DmMessagesResult {
  const DmMessagesResult({required this.messages, this.nextCursor, this.counterpartyLastReadMessageId});
  final List<DmMessage> messages;
  final String? nextCursor;
  /// The counterparty's current read cursor — the id of the last message
  /// they've read in this room. Used to hydrate "read" (double-tick) status
  /// on the current user's own sent messages when a thread is (re)opened,
  /// not just from live WS read_receipt frames.
  final String? counterpartyLastReadMessageId;
}

/// HTTP client for the DM REST endpoints.
/// WebSocket lifecycle is handled separately by [DmWebSocketService].
class DmService {
  DmService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// In-memory cache of the last loaded thread list — used by the notification
  /// navigator to look up counterparty info without an extra network call.
  List<DmThread> cachedThreads = [];

  /// Per-room message cache — seeded into the screen immediately on open
  /// so there's never a spinner for rooms the user has visited before.
  final Map<String, List<DmMessage>> _messageCache = {};

  /// Per-room "clear chat" boundary — the moment the user cleared history
  /// for that room. Persists for the lifetime of the DmService instance
  /// (i.e. the app session).
  ///
  /// This used to be a bare `Set<String> _clearedRooms` (a boolean "is this
  /// room cleared" flag) that blocked re-fetching from the server entirely
  /// until ANY new message arrived, at which point the flag was dropped via
  /// `unmarkCleared()` — and the very next full reload fetched the
  /// COMPLETE unfiltered server history, bringing back everything the user
  /// had just cleared. That's the exact bug this timestamp model fixes:
  /// instead of refusing to fetch, [DmThreadScreen] now always fetches
  /// normally and filters out any message at or before this boundary. A
  /// message arriving after the clear simply passes the filter — it no
  /// longer un-clears the *entire* room and floods old history back in.
  final Map<String, DateTime> _clearedBefore = {};

  /// Returns the clear-chat boundary for [roomId], or `null` if the room
  /// has never been cleared this session. Messages with `createdAt` at or
  /// before this timestamp should be hidden.
  DateTime? getClearedBefore(String roomId) => _clearedBefore[roomId];

  /// Loads persisted clear-chat boundaries from SharedPreferences.
  /// Call once after DmService creation (e.g. in app startup / post-auth).
  Future<void> loadClearedBoundaries() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('dm_cleared_'));
    for (final key in keys) {
      final roomId = key.replaceFirst('dm_cleared_', '');
      final isoString = prefs.getString(key);
      if (isoString != null) {
        final dt = DateTime.tryParse(isoString);
        if (dt != null) _clearedBefore[roomId] = dt;
      }
    }
  }

  /// Per-room draft text — preserved across navigating away from and back
  /// to a thread (e.g. backing out to answer a call, or to check another
  /// chat) within the same app session. Previously the composer's
  /// TextEditingController was scoped to DmThreadScreen's own State and
  /// disposed with it, silently discarding whatever the user had typed
  /// but not sent the moment the screen was popped.
  final Map<String, String> _drafts = {};

  /// Returns the saved draft text for a room, or an empty string if none.
  String getDraft(String roomId) => _drafts[roomId] ?? '';

  /// Saves draft text for a room. An empty [text] clears the draft.
  void setDraft(String roomId, String text) {
    if (text.isEmpty) {
      _drafts.remove(roomId);
    } else {
      _drafts[roomId] = text;
    }
  }

  /// Live presence cache keyed by user_id.
  /// Updated by DmThreadScreen when WS presence frames arrive.
  /// Used by DmListScreen to show online dots without needing an open WS.
  final Map<String, bool> presenceCache = {};

  /// Returns cached messages for a room, or empty list if not yet loaded.
  List<DmMessage> getCachedMessages(String roomId) =>
      List.unmodifiable(_messageCache[roomId] ?? const []);

  /// Updates the message cache for a room.
  void _updateMessageCache(String roomId, List<DmMessage> messages) {
    _messageCache[roomId] = List.of(messages);
  }

  /// Clears the cache (e.g. on sign-out).
  void clearCaches() {
    cachedThreads = [];
    _messageCache.clear();
    _clearedBefore.clear();
    _drafts.clear();
    _clearPersistedBoundaries();
  }

  /// Removes all persisted clear-chat boundaries from SharedPreferences.
  Future<void> _clearPersistedBoundaries() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('dm_cleared_')).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Clears the cached messages for a single room and records the current
  /// moment as that room's clear-chat boundary — every future fetch filters
  /// out anything at or before it (see [_clearedBefore]'s doc comment).
  void clearRoomCache(String roomId) {
    _messageCache.remove(roomId);
    _clearedBefore[roomId] = DateTime.now();
    _persistClearedBoundary(roomId, _clearedBefore[roomId]!);
  }

  /// Persists a single room's clear-chat boundary to SharedPreferences.
  Future<void> _persistClearedBoundary(String roomId, DateTime boundary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dm_cleared_$roomId', boundary.toIso8601String());
  }

  /// Lists all DM threads for the current user, sorted by recency.
  Future<List<DmThread>> listThreads() async {
    final response = await _apiClient.dio.get('/api/zend/dm');
    final threads = (response.data['threads'] as List<dynamic>? ?? []);
    final result = threads
        .cast<Map<String, dynamic>>()
        .map(DmThread.fromJson)
        .toList();
    cachedThreads = result;
    return result;
  }

  /// Gets or creates a DM room with the given user and returns the canonical
  /// room_id from the server. This is the single source of truth — never
  /// compute room_id client-side.
  ///
  /// Fast path: if the thread is already in [cachedThreads] we return
  /// immediately without a network round-trip. The server stays the source of
  /// truth — the cache is only used to avoid the API call when we already have
  /// the room_id (e.g. navigating from the Activity page to a person you've
  /// already chatted with).
  Future<({String roomId, DmCounterparty counterparty})> getOrCreateRoom(
    String otherUserId,
  ) async {
    // ── Cache-first lookup ────────────────────────────────────────────────
    final cached = cachedThreads
        .where((t) => t.counterparty.userId == otherUserId)
        .firstOrNull;
    if (cached != null) {
      return (roomId: cached.roomId, counterparty: cached.counterparty);
    }

    // ── Network fallback ──────────────────────────────────────────────────
    final response = await _apiClient.dio.get(
      '/api/zend/dm/with/$otherUserId',
    );
    final roomId = response.data['room_id'] as String;
    final cp = DmCounterparty.fromJson(
      response.data['counterparty'] as Map<String, dynamic>,
    );
    return (roomId: roomId, counterparty: cp);
  }

  /// Fetches paginated message history for a room.
  Future<DmMessagesResult> getMessages(
    String roomId, {
    String? cursor,
    int limit = 50,
  }) async {
    final response = await _apiClient.dio.get(
      '/api/zend/dm/$roomId/messages',
      queryParameters: {
        if (cursor != null) 'cursor': cursor, // ignore: use_null_aware_elements
        'limit': limit,
      },
    );
    final rawMessages = (response.data['messages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(DmMessage.fromJson)
        .toList();
    // Apply this room's own clear-chat boundary BEFORE caching or returning.
    // Previously this filtering only happened in DmThreadScreen at display
    // time, while this method cached the server's raw, unfiltered response
    // via _updateMessageCache — so a room cleared mid-session, then fetched
    // again for any reason (a new message arriving, pagination, reconnect
    // resync), would re-cache the pre-clear history too. The next time that
    // room was opened, getCachedMessages() would seed the screen with that
    // raw cache (which the screen's initState never re-filters — it trusts
    // the cache), briefly showing cleared messages until _loadMessages()'s
    // own fetch resolved and clobbered the list. Filtering here means the
    // cache itself can never contain anything at or before the clear
    // boundary, closing that race at the source.
    final clearedBefore = _clearedBefore[roomId];
    final messages = clearedBefore == null
        ? rawMessages
        : rawMessages.where((m) => m.createdAt.isAfter(clearedBefore)).toList();
    // Populate cache for first page (no cursor = fresh load)
    if (cursor == null) {
      _updateMessageCache(roomId, messages);
    }
    return DmMessagesResult(
      messages: messages,
      nextCursor: response.data['next_cursor'] as String?,
      counterpartyLastReadMessageId: response.data['counterparty_last_read_message_id'] as String?,
    );
  }

  /// Sends a text message via HTTP (WebSocket fallback path).
  /// [replyToContent] and [replyToSenderZendtag] are optional reply metadata
  /// stored in the message's JSON metadata so they survive server round-trips.
  /// [forwarded] marks this as a forwarded message — the server stores a
  /// `forwarded: true` flag in metadata so the bubble can render a
  /// "Forwarded" label.
  Future<DmMessage> sendMessage(
    String roomId,
    String content,
    String clientId, {
    String? replyToContent,
    String? replyToSenderZendtag,
    String? replyToMessageId,
    bool forwarded = false,
  }) async {
    final data = <String, dynamic>{
      'content': content,
      'client_id': clientId,
      if (forwarded) 'forwarded': true,
    };
    if (replyToContent != null || replyToSenderZendtag != null || replyToMessageId != null) {
      data['metadata'] = {
        'reply_to_content': replyToContent,
        'reply_to_sender_zendtag': replyToSenderZendtag,
        'reply_to_message_id': replyToMessageId,
      };
    }
    final response = await _apiClient.dio.post(
      '/api/zend/dm/$roomId/messages',
      data: data,
    );
    return DmMessage.fromJson({
      'id': response.data['id'] as String? ?? clientId,
      'room_id': roomId,
      'sender_user_id': '',
      'message_type': 'text',
      'content': content,
      'client_id': clientId,
      'created_at': response.data['created_at'] as String? ??
          DateTime.now().toIso8601String(),
      'reply_to_content': replyToContent,
      'reply_to_sender_zendtag': replyToSenderZendtag,
      'reply_to_message_id': replyToMessageId,
      'metadata': {if (forwarded) 'forwarded': true},
    });
  }

  /// Soft-deletes a message the current user sent. Throws on failure (e.g.
  /// not the sender, already deleted, network error) — caller should catch
  /// this and revert any optimistic UI removal rather than assuming success.
  Future<void> deleteMessage(String roomId, String messageId) async {
    await _apiClient.dio.delete('/api/zend/dm/$roomId/messages/$messageId');
  }

  /// Fetches sent/read timestamps for a single message — backs the
  /// message-info sheet (mirrors WhatsApp's "Message info" screen).
  Future<DmMessageInfo> getMessageInfo(String roomId, String messageId) async {
    final response = await _apiClient.dio.get(
      '/api/zend/dm/$roomId/messages/$messageId/info',
    );
    return DmMessageInfo(
      sentAt: DateTime.tryParse(response.data['sent_at'] as String? ?? '') ?? DateTime.now(),
      readAt: response.data['read_at'] != null
          ? DateTime.tryParse(response.data['read_at'] as String)
          : null,
    );
  }

  /// Marks all messages in the room as read.
  Future<void> markRead(String roomId, String lastMessageId) async {
    try {
      await _apiClient.dio.post(
        '/api/zend/dm/$roomId/read',
        data: {'last_message_id': lastMessageId},
      );
    } on DioException catch (_) {
      // Non-fatal — unread count will sync on next thread list fetch.
    }
  }

  /// Sends a reaction on a DM message via HTTP (so the server can fan-out
  /// notifications to the other party). The WS path already handles live
  /// delivery to connected clients; this call ensures the reaction is
  /// persisted and the counterparty gets notified even if they're offline.
  Future<void> sendMessageReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) async {
    try {
      await _apiClient.dio.post(
        '/api/zend/dm/$roomId/messages/$messageId/react',
        data: {'emoji': emoji},
      );
    } on DioException catch (_) {
      // Non-fatal — the optimistic UI update already happened.
    }
  }

  /// Removes a reaction from a DM message.
  Future<void> removeMessageReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) async {
    try {
      await _apiClient.dio.delete(
        '/api/zend/dm/$roomId/messages/$messageId/react',
        data: {'emoji': emoji},
      );
    } on DioException catch (_) {
      // Non-fatal — the optimistic UI update already happened.
    }
  }

  /// Sends a payment request message into a DM room.
  /// The request renders as a tappable bubble; the recipient taps it to pay.
  Future<DmMessage> sendPaymentRequest(
    String roomId, {
    required double amountUsdc,
    required String requesterZendtag,
    String? note,
    required String clientId,
  }) async {
    final response = await _apiClient.dio.post(
      '/api/zend/dm/$roomId/messages',
      data: {
        'message_type': 'payment_request',
        'metadata': {
          'amount_usdc': amountUsdc.toStringAsFixed(6),
          'requester_zendtag': requesterZendtag,
          if (note != null && note.isNotEmpty) 'note': note,
          'status': 'pending',
        },
        'client_id': clientId,
      },
    );
    return DmMessage(
      id: response.data['id'] as String? ?? clientId,
      roomId: roomId,
      senderUserId: '',
      type: DmMessageType.paymentRequest,
      paymentRequestData: DmPaymentRequestData(
        amountUsdc: amountUsdc.toStringAsFixed(6),
        requesterZendtag: requesterZendtag,
        note: note,
        status: 'pending',
      ),
      clientId: clientId,
      createdAt: DateTime.tryParse(response.data['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// Updates the current user's presence visibility preference.
  /// 'everyone' | 'contacts' | 'nobody'
  Future<void> updatePresencePrivacy(String visibility) async {
    await _apiClient.dio.patch(
      '/api/zend/presence/privacy',
      data: {'visibility': visibility},
    );
  }
  Future<Map<String, dynamic>> prepareVibe(
    String roomId, {
    required String stickerId,
    required double amountUsdc,
  }) =>
      _apiClient.prepareVibe(
        roomId: roomId,
        stickerId: stickerId,
        amountUsdc: amountUsdc,
      );

  /// Step 2: submits the client-signed transaction to complete the Vibe.
  Future<Map<String, dynamic>> submitVibe(
    String roomId, {
    required String stickerId,
    required double amountUsdc,
    required String partiallySignedTx,
    required String clientId,
  }) =>
      _apiClient.submitVibe(
        roomId: roomId,
        stickerId: stickerId,
        amountUsdc: amountUsdc,
        partiallySignedTx: partiallySignedTx,
        clientId: clientId,
      );
}
