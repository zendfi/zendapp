import 'package:flutter/foundation.dart';

import 'pool_websocket_service.dart';

export 'pool_websocket_service.dart'
    show WsConnectionState, WsFrameType, WsServerFrame;

/// DM WebSocket service — thin wrapper around [PoolWebSocketService] that
/// connects to the DM room WebSocket endpoint instead of a pool room.
///
/// All frame handling (send_message, typing, read receipts) is identical to
/// pool rooms — the only difference is the connection URL.
class DmWebSocketService {
  DmWebSocketService({
    required String roomId,
    required String baseWsUrl,
    required Future<String?> Function() getToken,
  }) : _ws = PoolWebSocketService(
          poolId: roomId,
          baseWsUrl: baseWsUrl,
          getToken: getToken,
          pathOverride: '/api/zend/dm/$roomId/ws',
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

  void sendTyping(bool isTyping) => _ws.sendTyping(isTyping);

  void sendRead(String lastReadMessageId) => _ws.sendRead(lastReadMessageId);

  void sendReaction(String messageId, String emoji) =>
      _ws.sendReaction(messageId, emoji);

  void sendReactionRemoved(String messageId, String emoji) =>
      _ws.sendReactionRemoved(messageId, emoji);
}
