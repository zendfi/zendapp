import 'package:dio/dio.dart';

import '../models/dm_message.dart';
import '../models/dm_thread.dart';
import 'api_client.dart';

class DmMessagesResult {
  const DmMessagesResult({required this.messages, this.nextCursor});
  final List<DmMessage> messages;
  final String? nextCursor;
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

  /// Rooms the user has explicitly cleared — messages won't be reloaded
  /// from the server until the user navigates away and back (or restarts).
  /// Persists for the lifetime of the DmService instance (i.e. the app session).
  final Set<String> _clearedRooms = {};

  /// Live presence cache keyed by user_id.
  /// Updated by DmThreadScreen when WS presence frames arrive.
  /// Used by DmListScreen to show online dots without needing an open WS.
  final Map<String, bool> presenceCache = {};

  /// Returns true if the user has cleared this room in the current session.
  bool isRoomCleared(String roomId) => _clearedRooms.contains(roomId);

  /// Returns cached messages for a room, or empty list if not yet loaded.
  List<DmMessage> getCachedMessages(String roomId) =>
      List.unmodifiable(_messageCache[roomId] ?? const []);

  /// Updates the message cache for a room.
  void _updateMessageCache(String roomId, List<DmMessage> messages) {
    _messageCache[roomId] = List.of(messages);
    // Note: do NOT unmark cleared rooms here. Clearing is only undone when
    // the counterparty sends a new message (handled in DmThreadScreen._initWs).
  }

  /// Clears the cache (e.g. on sign-out).
  void clearCaches() {
    cachedThreads = [];
    _messageCache.clear();
    _clearedRooms.clear();
  }

  /// Clears the cached messages for a single room and marks it as user-cleared
  /// so the screen doesn't refetch from the server on reopen.
  void clearRoomCache(String roomId) {
    _messageCache.remove(roomId);
    _clearedRooms.add(roomId);
  }

  /// Unclears a room — called when new incoming messages arrive so the room
  /// becomes active again after a clear.
  void unmarkCleared(String roomId) {
    _clearedRooms.remove(roomId);
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
    final messages = (response.data['messages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(DmMessage.fromJson)
        .toList();
    // Populate cache for first page (no cursor = fresh load)
    if (cursor == null) {
      _updateMessageCache(roomId, messages);
    }
    return DmMessagesResult(
      messages: messages,
      nextCursor: response.data['next_cursor'] as String?,
    );
  }

  /// Sends a text message via HTTP (WebSocket fallback path).
  /// [replyToContent] and [replyToSenderZendtag] are optional reply metadata
  /// stored in the message's JSON metadata so they survive server round-trips.
  Future<DmMessage> sendMessage(
    String roomId,
    String content,
    String clientId, {
    String? replyToContent,
    String? replyToSenderZendtag,
    String? replyToMessageId,
  }) async {
    final data = <String, dynamic>{
      'content': content,
      'client_id': clientId,
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
    });
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
