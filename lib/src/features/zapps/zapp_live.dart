import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/api_client.dart';

/// Live rooms for a ZApp (AppKit `zend.live`). The Zend app holds the
/// connection, so the user's sign-in never reaches the page; messages and
/// presence are pushed to the page through the bridge.
class ZAppLiveRooms {
  ZAppLiveRooms({required this.api, required this.push});

  final ApiClient api;

  /// Sends an event to the page: `{zend:1, event:'live', interactionId, ...}`.
  final void Function(Map<String, dynamic> event) push;

  final Map<String, _Room> _rooms = {};

  /// At most this many rooms per open app, so a page can't open hundreds.
  static const maxRooms = 4;

  Future<void> join(String interactionId) async {
    if (_rooms.containsKey(interactionId)) return;
    if (_rooms.length >= maxRooms) {
      throw StateError('LIVE_TOO_MANY_ROOMS');
    }
    final room = _Room(interactionId, this);
    _rooms[interactionId] = room;
    await room.connect();
  }

  void send(String interactionId, Object? data) {
    final room = _rooms[interactionId];
    if (room == null) throw StateError('LIVE_NOT_JOINED');
    room.send(data);
  }

  void leave(String interactionId) => _rooms.remove(interactionId)?.close();

  void dispose() {
    for (final r in _rooms.values) {
      r.close();
    }
    _rooms.clear();
  }

  Future<String?> _ticket() async {
    try {
      final r = await api.dio.post('/api/zend/dm/ws-ticket');
      return r.data['ticket'] as String?;
    } catch (_) {
      return null;
    }
  }
}

class _Room {
  _Room(this.interactionId, this.owner);
  final String interactionId;
  final ZAppLiveRooms owner;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;
  int _attempts = 0;

  void _emit(String type, [Map<String, dynamic> extra = const {}]) =>
      owner.push({
        'zend': 1,
        'event': 'live',
        'type': type,
        'interactionId': interactionId,
        ...extra,
      });

  Future<void> connect() async {
    final ticket = await owner._ticket();
    if (ticket == null) throw StateError('LIVE_UNAVAILABLE');
    final base = Uri.parse(owner.api.baseUrl);
    final uri = Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/api/zend/v2/apps/live/$interactionId/ws',
      queryParameters: {'ticket': ticket},
    );
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;
    _attempts = 0;
    _emit('status', {'status': 'connected'});
    _sub = channel.stream.listen(
      (raw) {
        if (raw is! String) return;
        final Map<String, dynamic> f;
        try {
          f = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        switch (f['type']) {
          case 'live_message':
            _emit('message', {
              'from': f['from'],
              'data': f['data'],
              'at': f['at'],
            });
          case 'live_presence':
            _emit('presence', {
              'members': [
                for (final m in (f['members'] as List? ?? const []))
                  {
                    'appUserId': (m as Map)['app_user_id'],
                    'name': m['name'],
                    'username': m['username'],
                    'avatar': m['avatar'],
                  },
              ],
            });
          case 'live_closed':
            _closed = true;
            _emit('closed', {'reason': f['reason']});
            owner._rooms.remove(interactionId);
          case 'error':
            _emit('error', {'code': f['code'], 'message': f['message']});
        }
      },
      onDone: _onDropped,
      onError: (_) => _onDropped(),
      cancelOnError: true,
    );
  }

  void _onDropped() {
    _sub?.cancel();
    _channel = null;
    if (_closed) return;
    _emit('status', {'status': 'reconnecting'});
    if (_attempts >= 5) {
      _emit('status', {'status': 'disconnected'});
      owner._rooms.remove(interactionId);
      return;
    }
    final wait = Duration(seconds: 1 << _attempts);
    _attempts++;
    Future<void>.delayed(wait, () async {
      if (_closed) return;
      try {
        await connect();
      } catch (_) {
        _onDropped();
      }
    });
  }

  void send(Object? data) {
    final c = _channel;
    if (c == null) throw StateError('LIVE_NOT_CONNECTED');
    c.sink.add(jsonEncode({'type': 'send', 'data': data}));
  }

  void close() {
    _closed = true;
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
