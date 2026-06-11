import 'dart:async';
import 'dart:collection';
import '../data/local/pool_message_repository.dart';
import '../models/pool_message_local.dart';
import 'pool_websocket_service.dart';

class _PendingMessage {
  final String clientId;
  final String content;
  final DateTime createdAt;

  _PendingMessage({
    required this.clientId,
    required this.content,
    required this.createdAt,
  });
}

/// An ordered, in-memory queue of messages pending server acknowledgement.
///
/// - [enqueue] adds a message and triggers [drain] if connected.
/// - [drain] sends messages in FIFO order, waiting for an `ack` (or 15s
///   timeout) before advancing. On timeout the message is marked `failed`
///   and draining stops.
/// - [restoreFromDb] re-populates the queue from `LocalDB` rows with
///   `local_status = 'sending'` (called on app launch before connecting).
/// - The queue auto-drains whenever the WebSocket connection becomes
///   `connected`.
class OutboxQueue {
  final PoolWebSocketService wsService;
  final PoolMessageRepository repository;
  final String poolId;

  final Queue<_PendingMessage> _queue = Queue();
  bool _draining = false;
  bool _disposed = false;

  OutboxQueue({
    required this.wsService,
    required this.repository,
    required this.poolId,
  }) {
    wsService.connectionState.addListener(_onConnectionStateChanged);
  }

  void _onConnectionStateChanged() {
    if (wsService.connectionState.value == WsConnectionState.connected &&
        !_draining) {
      drain();
    }
  }

  bool get isEmpty => _queue.isEmpty;

  /// Adds a message to the queue and triggers [drain] if connected.
  void enqueue(String clientId, String content) {
    _queue.add(_PendingMessage(
      clientId: clientId,
      content: content,
      createdAt: DateTime.now(),
    ));
    if (wsService.connectionState.value == WsConnectionState.connected) {
      drain();
    }
  }

  /// Re-populates the queue from `LocalDB` rows with `local_status = 'sending'`.
  ///
  /// Call this on app launch before [connect] so that messages sent while
  /// offline are retried automatically.
  Future<void> restoreFromDb() async {
    final pending = await repository.getPendingMessages(poolId);
    for (final msg in pending) {
      if (msg.clientId != null) {
        _queue.add(_PendingMessage(
          clientId: msg.clientId!,
          content: msg.content ?? '',
          createdAt: msg.createdAt,
        ));
      }
    }
  }

  /// Drains the queue in FIFO order.
  ///
  /// For each message:
  /// 1. Sends it over WebSocket.
  /// 2. Waits up to 15 seconds for an `ack` frame matching the `client_id`.
  /// 3. On ack: marks `delivered` in LocalDB and advances.
  /// 4. On timeout: marks `failed` in LocalDB and continues to next message.
  Future<void> drain() async {
    if (_draining || _disposed) return;
    _draining = true;

    try {
      while (_queue.isNotEmpty && !_disposed) {
        if (wsService.connectionState.value != WsConnectionState.connected) {
          break;
        }

        final msg = _queue.first;

        // Subscribe to frames before sending to avoid a race condition.
        final completer = Completer<Map<String, dynamic>?>();
        StreamSubscription? sub;
        sub = wsService.frames.listen((frame) {
          if (frame.type == WsFrameType.ack) {
            final ackClientId = frame.data['client_id'] as String?;
            if (ackClientId == msg.clientId && !completer.isCompleted) {
              completer.complete(frame.data);
            }
          }
        });

        wsService.sendMessage(msg.clientId, msg.content);

        // Wait for ack or 15-second timeout.
        final result = await Future.any([
          completer.future,
          Future<Map<String, dynamic>?>.delayed(
            const Duration(seconds: 15),
            () => null,
          ),
        ]);

        await sub.cancel();

        if (result != null) {
          // Ack received — mark delivered and advance.
          final serverId = result['server_id'] as String?;
          final createdAtStr = result['created_at'] as String?;
          await repository.updateStatus(
            msg.clientId,
            LocalStatus.delivered,
            serverId: serverId,
            serverCreatedAt:
                createdAtStr != null ? DateTime.tryParse(createdAtStr) : null,
          );
          _queue.removeFirst();
        } else {
          // Timeout — mark failed and continue draining remaining messages.
          await repository.updateStatus(msg.clientId, LocalStatus.failed);
          _queue.removeFirst();
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Pauses draining (e.g., when the connection drops).
  void pause() {
    _draining = false;
  }

  /// Permanently disposes this queue.
  void dispose() {
    _disposed = true;
    wsService.connectionState.removeListener(_onConnectionStateChanged);
  }
}
