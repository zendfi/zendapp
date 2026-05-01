import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SSE event types matching the backend's SseEvent enum.
enum SseEventType {
  transferUpdate,
  transferFailed,
  balanceUpdate,
  heartbeat,
  refreshRequired,
  unknown,
}

/// A parsed SSE event from the backend.
class SseEvent {
  final SseEventType type;
  final Map<String, dynamic> data;

  const SseEvent({required this.type, required this.data});

  factory SseEvent.fromRaw(String eventType, String rawData) {
    final type = switch (eventType) {
      'transfer_update' => SseEventType.transferUpdate,
      'transfer_failed' => SseEventType.transferFailed,
      'balance_update' => SseEventType.balanceUpdate,
      'heartbeat' => SseEventType.heartbeat,
      'refresh_required' => SseEventType.refreshRequired,
      _ => SseEventType.unknown,
    };

    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(rawData) as Map<String, dynamic>;
    } catch (_) {
      // Heartbeat data is just a plain string — not JSON
    }

    return SseEvent(type: type, data: data);
  }
}

/// SSE client that connects to GET /api/zend/events and streams events.
///
/// Design decisions for scale and reliability:
/// - Uses Dio's streaming response (ResponseType.stream) — no extra package needed
/// - Automatic reconnection with exponential backoff (1s → 2s → 4s → max 30s)
/// - Stops reconnecting when the app is backgrounded (caller's responsibility)
/// - Exposes a `Stream[SseEvent]` that callers subscribe to
/// - Heartbeat events are filtered out before reaching callers
class SseService {
  final String _baseUrl;
  final FlutterSecureStorage _secureStorage;

  static const _tokenKey = 'zend_session_token';
  static const _maxReconnectDelay = Duration(seconds: 30);
  static const _initialReconnectDelay = Duration(seconds: 1);

  StreamController<SseEvent>? _controller;
  CancelToken? _cancelToken;
  bool _active = false;
  Duration _reconnectDelay = _initialReconnectDelay;
  Timer? _reconnectTimer;

  SseService({
    required String baseUrl,
    required FlutterSecureStorage secureStorage,
  })  : _baseUrl = baseUrl,
        _secureStorage = secureStorage;

  /// The stream of SSE events. Subscribe to this to receive real-time updates.
  /// Heartbeat events are filtered out.
  Stream<SseEvent> get events {
    _controller ??= StreamController<SseEvent>.broadcast();
    return _controller!.stream.where(
      (e) => e.type != SseEventType.heartbeat,
    );
  }

  /// Start the SSE connection. Call this when the user is authenticated
  /// and the app is in the foreground.
  void start() {
    if (_active) return;
    _active = true;
    _reconnectDelay = _initialReconnectDelay;
    _connect();
  }

  /// Stop the SSE connection. Call this on logout or when the app backgrounds.
  void stop() {
    _active = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cancelToken?.cancel('SSE stopped');
    _cancelToken = null;
  }

  /// Dispose the service entirely (call on app shutdown).
  void dispose() {
    stop();
    _controller?.close();
    _controller = null;
  }

  Future<void> _connect() async {
    if (!_active) return;

    final token = await _secureStorage.read(key: _tokenKey);
    if (token == null || token.isEmpty) {
      // Not authenticated — don't connect
      _active = false;
      return;
    }

    _cancelToken = CancelToken();

    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
      responseType: ResponseType.stream,
      // No timeout — SSE is a long-lived connection
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: null,
    ));

    try {
      final response = await dio.get<ResponseBody>(
        '/api/zend/events',
        cancelToken: _cancelToken,
      );

      final stream = response.data!.stream;

      // SSE line buffer — events can span multiple lines
      final buffer = StringBuffer();
      String currentEventType = 'message';

      await for (final chunk in stream) {
        if (!_active) break;

        final text = utf8.decode(chunk);
        buffer.write(text);

        // Process complete lines
        final content = buffer.toString();
        final lines = content.split('\n');

        // Keep the last incomplete line in the buffer
        buffer.clear();
        if (!content.endsWith('\n')) {
          buffer.write(lines.last);
        }

        final completeLines = content.endsWith('\n') ? lines : lines.sublist(0, lines.length - 1);

        for (final line in completeLines) {
          if (line.startsWith('event:')) {
            currentEventType = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            final data = line.substring(5).trim();
            final event = SseEvent.fromRaw(currentEventType, data);
            _controller?.add(event);
            currentEventType = 'message'; // Reset for next event
          } else if (line.isEmpty) {
            // Empty line = end of event block, reset
            currentEventType = 'message';
          }
          // Ignore 'id:' and 'retry:' lines for now
        }
      }

      // Stream ended cleanly — reconnect
      _scheduleReconnect();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // Intentional cancellation — don't reconnect
        return;
      }

      if (e.response?.statusCode == 401) {
        // Session expired — stop SSE, let the auth interceptor handle it
        _active = false;
        return;
      }

      _scheduleReconnect();
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_active) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (_active) {
        _connect();
      }
    });

    // Exponential backoff: 1s → 2s → 4s → 8s → 16s → 30s (max)
    _reconnectDelay = Duration(
      seconds: (_reconnectDelay.inSeconds * 2).clamp(
        _initialReconnectDelay.inSeconds,
        _maxReconnectDelay.inSeconds,
      ),
    );
  }
}
