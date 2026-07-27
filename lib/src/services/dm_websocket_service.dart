import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'pool_websocket_service.dart';

export 'pool_websocket_service.dart'
    show WsConnectionState, WsFrameType, WsServerFrame;

/// DM WebSocket service — thin wrapper around [PoolWebSocketService] that
/// connects to the DM room WebSocket endpoint.
///
/// Uses the WS ticket endpoint (`POST /api/zend/dm/ws-ticket`) to obtain a
/// short-lived single-use ticket so the JWT is never exposed in the URL.
class DmWebSocketService {
  DmWebSocketService({
    required String roomId,
    required String baseWsUrl,
    required Future<String?> Function() getToken,
    required ApiClient apiClient,
  }) : _ws = PoolWebSocketService(
          poolId: roomId,
          baseWsUrl: baseWsUrl,
          getToken: getToken,
          pathOverride: '/api/zend/dm/$roomId/ws',
          getTicket: () async {
            try {
              final response = await apiClient.dio.post('/api/zend/dm/ws-ticket');
              return response.data['ticket'] as String?;
            } catch (_) {
              // Ticket fetch failed — PoolWebSocketService falls back to ?token=
              return null;
            }
          },
        );

  final PoolWebSocketService _ws;

  /// Broadcast stream of frames received from the server.
  Stream<WsServerFrame> get frames => _ws.frames;

  /// Connection state notifier.
  ValueNotifier<WsConnectionState> get connectionState => _ws.connectionState;

  /// The server_id of the last message frame received.
  String? get lastKnownServerId => _ws.lastKnownServerId;

  Future<void> connect() => _ws.connect();
  void disconnect() => _ws.disconnect();
  Future<void> resetAndReconnect() => _ws.resetAndReconnect();
  void dispose() => _ws.dispose();

  void sendMessage(String clientId, String content) =>
      _ws.sendMessage(clientId, content);

  void sendMessageWithReply(
    String clientId,
    String content, {
    String? replyToMessageId,
    String? replyToContent,
    String? replyToSenderZendtag,
  }) =>
      _ws.sendMessageWithReply(
        clientId,
        content,
        replyToMessageId: replyToMessageId,
        replyToContent: replyToContent,
        replyToSenderZendtag: replyToSenderZendtag,
      );

  void sendTyping(bool isTyping) => _ws.sendTyping(isTyping);

  void sendRead(String lastReadMessageId) => _ws.sendRead(lastReadMessageId);

  void sendReaction(String messageId, String emoji) =>
      _ws.sendReaction(messageId, emoji);

  void sendReactionRemoved(String messageId, String emoji) =>
      _ws.sendReactionRemoved(messageId, emoji);

  void sendRecordingAudio(bool isRecording) =>
      _ws.sendRecordingAudio(isRecording);
}
