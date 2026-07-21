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

  /// Sends a Vibe (sticker + micro-payment) in a DM room.
  /// Returns the resulting DM message.
  Future<DmMessage> sendVibe(
    String roomId, {
    required String stickerId,
    required double amountUsdc,
    required String clientId,
  }) async {
    final response = await _apiClient.sendVibe(
      roomId: roomId,
      stickerId: stickerId,
      amountUsdc: amountUsdc,
      clientId: clientId,
    );
    return DmMessage.fromJson({
      'id': response['id'] as String? ?? clientId,
      'room_id': roomId,
      'sender_user_id': '',
      'message_type': 'vibe',
      'sticker_id': stickerId,
      'amount_usdc': amountUsdc.toString(),
      'client_id': clientId,
      'created_at': response['created_at'] as String? ??
          DateTime.now().toIso8601String(),
    });
  }
}
