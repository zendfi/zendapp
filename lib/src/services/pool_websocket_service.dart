import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

enum WsConnectionState { disconnected, connecting, connected, reconnecting }

enum WsFrameType { ack, message, typing, readReceipt, reaction, reactionRemoved, error, unknown }

class WsServerFrame {
  final WsFrameType type;
  final Map<String, dynamic> data;

  const WsServerFrame({required this.type, required this.data});

  factory WsServerFrame.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? '';
    final type = switch (typeStr) {
      'ack' => WsFrameType.ack,
      'message' => WsFrameType.message,
      'typing' => WsFrameType.typing,
      'read_receipt' => WsFrameType.readReceipt,
      'reaction' => WsFrameType.reaction,
      'reaction_removed' => WsFrameType.reactionRemoved,
      'error' => WsFrameType.error,
      _ => WsFrameType.unknown,
    };
    return WsServerFrame(type: type, data: json);
  }
}

/// Manages the WebSocket connection lifecycle for a single pool room.
///
/// - Connects to `$baseWsUrl/api/zend/pools/$poolId/ws?token=<jwt>`
/// - Exposes a broadcast [frames] stream of parsed [WsServerFrame]s
/// - Implements exponential backoff reconnection (1s → 2s → 4s … capped at 30s)
/// - Stops reconnecting after [_maxConsecutiveFailures] consecutive failures
class PoolWebSocketService {
  final String poolId;
  final String baseWsUrl;

  /// Callback that returns the current JWT, or `null` if unauthenticated.
  final Future<String?> Function() getToken;

  /// Optional override for the WebSocket path.
  /// When set, overrides the default `/api/zend/pools/$poolId/ws`.
  final String? pathOverride;

  final ValueNotifier<WsConnectionState> connectionState =
      ValueNotifier(WsConnectionState.disconnected);

  final _streamController = StreamController<WsServerFrame>.broadcast();

  /// Broadcast stream of frames received from the server.
  Stream<WsServerFrame> get frames => _streamController.stream;

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _consecutiveFailures = 0;
  bool _disposed = false;

  /// The `server_id` of the last message frame received — used for sync after
  /// reconnect.
  String? lastKnownServerId;

  static const int _maxConsecutiveFailures = 5;

  PoolWebSocketService({
    required this.poolId,
    required this.baseWsUrl,
    required this.getToken,
    this.pathOverride,
  });

  int get consecutiveFailures => _consecutiveFailures;

  /// Opens the WebSocket connection. No-ops if already connected/connecting.
  Future<void> connect() async {
    if (_disposed) return;
    if (connectionState.value == WsConnectionState.connected ||
        connectionState.value == WsConnectionState.connecting) {
      return;
    }

    connectionState.value = _reconnectAttempts > 0
        ? WsConnectionState.reconnecting
        : WsConnectionState.connecting;

    final token = await getToken();
    if (token == null) {
      connectionState.value = WsConnectionState.disconnected;
      return;
    }

    try {
      final uri = Uri(
        scheme: baseWsUrl.startsWith('wss') ? 'wss' : 'ws',
        host: Uri.parse(baseWsUrl).host,
        port: Uri.parse(baseWsUrl).port,
        path: pathOverride ?? '/api/zend/pools/$poolId/ws',
        queryParameters: {'token': token},
      );
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      connectionState.value = WsConnectionState.connected;
      _reconnectAttempts = 0;
      _consecutiveFailures = 0;

      _channelSub = _channel!.stream.listen(
        (data) {
          if (data is String) {
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final frame = WsServerFrame.fromJson(json);
              if (frame.type == WsFrameType.message) {
                final sid = frame.data['server_id'] as String?;
                if (sid != null) lastKnownServerId = sid;
              }
              _streamController.add(frame);
            } catch (_) {
              // Malformed frame — silently discard.
            }
          }
        },
        onDone: () => _onDisconnected(),
        onError: (_) => _onDisconnected(),
        cancelOnError: true,
      );
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    if (_disposed) return;
    _channelSub?.cancel();
    _channelSub = null;
    _channel = null;
    _consecutiveFailures++;

    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      connectionState.value = WsConnectionState.disconnected;
      // Don't schedule another automatic retry — caller must invoke
      // resetAndReconnect() or connect() explicitly to try again.
      return;
    }

    connectionState.value = WsConnectionState.reconnecting;
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, capped at 30s.
    final delaySecs = (1 << _reconnectAttempts).clamp(1, 30);
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(seconds: delaySecs), connect);
  }

  /// Resets the failure counter and reconnects from scratch.
  /// Use this for explicit user-triggered retries or app-resume reconnects
  /// so the service doesn't permanently stop after [_maxConsecutiveFailures].
  Future<void> resetAndReconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _consecutiveFailures = 0;
    _reconnectAttempts = 0;
    await connect();
  }

  /// Closes the connection and cancels any pending reconnect timer.
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channelSub?.cancel();
    _channelSub = null;
    _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    connectionState.value = WsConnectionState.disconnected;
    _reconnectAttempts = 0;
    _consecutiveFailures = 0;
  }

  /// Permanently disposes this service. Do not call [connect] after this.
  void dispose() {
    _disposed = true;
    disconnect();
    _streamController.close();
    connectionState.dispose();
  }

  /// Sends a `send_message` frame to the server.
  void sendMessage(String clientId, String content) {
    _send(jsonEncode({
      'type': 'send_message',
      'client_id': clientId,
      'content': content,
    }));
  }

  /// Sends a `typing` frame to the server.
  void sendTyping(bool isTyping) {
    _send(jsonEncode({'type': 'typing', 'is_typing': isTyping}));
  }

  /// Sends a `read` frame to the server.
  /// [lastReadMessageId] is the server_id of the most recent visible message.
  void sendRead(String lastReadMessageId) {
    _send(jsonEncode({
      'type': 'read',
      'last_read_message_id': lastReadMessageId,
    }));
  }

  /// Sends an emoji reaction to a specific message.
  void sendReaction(String messageId, String emoji) {
    _send(jsonEncode({
      'type': 'reaction',
      'message_id': messageId,
      'emoji': emoji,
    }));
  }

  /// Removes an emoji reaction from a specific message.
  void sendReactionRemoved(String messageId, String emoji) {
    _send(jsonEncode({
      'type': 'reaction_removed',
      'message_id': messageId,
      'emoji': emoji,
    }));
  }

  void _send(String data) {
    if (connectionState.value == WsConnectionState.connected &&
        _channel != null) {
      _channel!.sink.add(data);
    }
  }
}
