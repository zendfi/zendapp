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
  Future<({String roomId, DmCounterparty counterparty})> getOrCreateRoom(
    String otherUserId,
  ) async {
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
    return DmMessagesResult(
      messages: messages,
      nextCursor: response.data['next_cursor'] as String?,
    );
  }

  /// Sends a text message via HTTP (WebSocket fallback path).
  Future<DmMessage> sendMessage(
    String roomId,
    String content,
    String clientId,
  ) async {
    final response = await _apiClient.dio.post(
      '/api/zend/dm/$roomId/messages',
      data: {'content': content, 'client_id': clientId},
    );
    // Server returns minimal data — we return our own optimistic message
    // since the local message is already in the UI.
    return DmMessage.fromJson({
      'id': response.data['id'] as String? ?? clientId,
      'room_id': roomId,
      'sender_user_id': '',
      'message_type': 'text',
      'content': content,
      'client_id': clientId,
      'created_at': response.data['created_at'] as String? ??
          DateTime.now().toIso8601String(),
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

  /// Step 1: gets blockhash + ATA addresses for client-side signing.
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
