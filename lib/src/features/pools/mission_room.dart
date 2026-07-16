import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';

import '../../core/zend_state.dart';
import '../../data/local/pool_message_repository.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/pool_message_local.dart';
import '../../services/outbox_queue.dart';
import '../../services/pool_websocket_service.dart';
import '../../services/sse_service.dart';
import 'mission_room_message.dart';
import 'pool.dart';
import 'package:solar_icons/solar_icons.dart';

const _curatedEmojis = [
  '🔥', '💰', '🙏', '👑', '😭', '⚡',
  '🎯', '💸', '🎉', '👀', '✅', '🚀',
];

class MissionRoom extends StatefulWidget {
  const MissionRoom({super.key, required this.pool});
  final Pool pool;

  @override
  State<MissionRoom> createState() => _MissionRoomState();
}

class _MissionRoomState extends State<MissionRoom> {
  late Pool _pool;
  final List<PoolMessageLocal> _messages = [];
  bool _loading = true;

  // ── WebSocket + LocalDB ──────────────────────────────────────────────────────
  late PoolMessageRepository _repository;
  late PoolWebSocketService _wsService;
  late OutboxQueue _outboxQueue;
  StreamSubscription<WsServerFrame>? _wsSub;
  bool _hasConnectedOnce = false;
  bool _showReconnecting = false;

  // ── Infinite scroll ──────────────────────────────────────────────────────────
  bool _fullyLoaded = false;
  bool _loadingOlder = false;

  // ── Typing indicators ────────────────────────────────────────────────────────
  final Map<String, Timer> _typingTimers = {};
  final Set<String> _typingUsers = {};

  // ── Read receipts ─────────────────────────────────────────────────────────────
  /// Maps zendtag → last_read_message_id (server_id) for other pool members.
  final Map<String, String> _readReceipts = {};
  /// Maps zendtag → avatar_url for read receipt display.
  final Map<String, String?> _readerAvatars = {};
  String? _myLastReadMessageId;

  // ── Voice note recording ──────────────────────────────────────────────────────
  // Recording is stubbed — the `record` package is incompatible with the current
  // Android Gradle Plugin version. Re-enable when a compatible package ships.
  // Playback of received voice notes still works via just_audio.

  // ── Voice note playback ───────────────────────────────────────────────────────
  /// Currently playing message id → AudioPlayer instance.
  final Map<String, AudioPlayer> _players = {};

  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  bool _sending = false;
  bool _isRecording = false;
  // ignore: prefer_final_fields — will be mutable again when recording is re-enabled
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  StreamSubscription<SseEvent>? _sseSub;

  late final _LifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _pool = widget.pool;
    _lifecycleObserver = _LifecycleObserver(onResume: _onAppResume);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    if (!mounted) return;
    final model = ZendScope.of(context);

    // Set up local DB layer
    _repository = PoolMessageRepository(model.localDb);

    // Load from local DB immediately — no spinner if we have cached messages
    final cached = await _repository.getRecentMessages(_pool.id);
    if (!mounted) return;

    // Always clear loading immediately after the local DB read completes.
    // This means the UI shows either cached messages or an empty state right away,
    // never a spinner for 3 seconds while the WS handshake completes.
    setState(() {
      if (cached.isNotEmpty) {
        _messages.addAll(cached);
      }
      _loading = false;
    });

    if (cached.isNotEmpty) {
      _jumpToBottom();
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendReadReceipt());
    }

    // Set up WebSocket service
    const storage = FlutterSecureStorage();
    final apiBaseUrl = model.walletService.apiClient.baseUrl;
    final wsBaseUrl = apiBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    _wsService = PoolWebSocketService(
      poolId: _pool.id,
      baseWsUrl: wsBaseUrl,
      getToken: () => storage.read(key: 'zend_session_token'),
    );

    // Set up outbox queue
    _outboxQueue = OutboxQueue(
      wsService: _wsService,
      repository: _repository,
      poolId: _pool.id,
    );

    // Restore any pending messages from DB into the outbox
    await _outboxQueue.restoreFromDb();

    // Listen to WS frames
    _wsSub = _wsService.frames.listen(_onWsFrame);

    // Listen to connection state for reconnecting banner
    _wsService.connectionState.addListener(_onConnectionStateChanged);

    // Connect (background — UI is already showing, no more blocking awaits)
    unawaited(_wsService.connect());

    // Subscribe to SSE for non-message events
    _subscribeSse();

    // Add scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
  }

  void _onConnectionStateChanged() {
    if (!mounted) return;
    final state = _wsService.connectionState.value;
    final shouldShow = _hasConnectedOnce &&
        (state == WsConnectionState.reconnecting ||
            state == WsConnectionState.disconnected);
    if (shouldShow != _showReconnecting) {
      setState(() => _showReconnecting = shouldShow);
    }
    if (state == WsConnectionState.connected) {
      _hasConnectedOnce = true;
      if (_showReconnecting) setState(() => _showReconnecting = false);
      // Always sync missed messages on every successful connection —
      // both first connect (cache may be stale/empty) and reconnects.
      // The afterId cursor makes this cheap when nothing was missed.
      unawaited(_onWsReconnected());
    }
  }

  Future<void> _onWsReconnected() async {
    // Find the last server-acknowledged message ID to use as a cursor.
    // If we have no messages at all (e.g. first open after a push notification),
    // afterId stays null — the API will return the most recent messages.
    String? lastServerId;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].serverId != null) {
        lastServerId = _messages[i].serverId;
        break;
      }
    }

    // Retry up to 3 times with a short delay on transient failures.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final model = ZendScope.of(context);
        final missed = await model.walletService.apiClient.listMessages(
          poolId: _pool.id,
          afterId: lastServerId,   // null → fetches latest batch
          limit: 100,
        );
        if (!mounted) return;
        for (final msg in missed) {
          final local = PoolMessageLocal.fromPoolMessage(msg);
          await _repository.upsertMessage(local);
          _upsertMessageLocal(local);
        }
        if (missed.isNotEmpty && mounted) {
          setState(() {});
          _jumpToBottom();
          _sendReadReceipt();
        }
        return; // success — done
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: (attempt + 1) * 2));
          if (!mounted) return;
        }
        // Final attempt failed — messages will be fetched on next reconnect
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _sseSub?.cancel();
    _wsSub?.cancel();
    _wsService.connectionState.removeListener(_onConnectionStateChanged);
    _wsService.dispose();
    _outboxQueue.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.dispose();
    _recordingTimer?.cancel();
    for (final p in _players.values) { p.dispose(); }
    for (final t in _typingTimers.values) { t.cancel(); }
    super.dispose();
  }

  /// Called when the app returns to the foreground.
  void _onAppResume() {
    if (!mounted) return;
    // Always reset and reconnect on foreground — this handles both the normal
    // "briefly backgrounded" case and the case where reconnection has given up
    // after 5 consecutive failures (resetAndReconnect clears the counter).
    unawaited(_wsService.resetAndReconnect());
  }

  // ── WebSocket frame handling ─────────────────────────────────────────────────

  void _onWsFrame(WsServerFrame frame) {
    if (!mounted) return;
    switch (frame.type) {
      case WsFrameType.message:
        final msg = PoolMessageLocal.fromWsFrame(frame.data);
        _repository.upsertMessage(msg);
        setState(() => _upsertMessageLocal(msg));
        _jumpToBottom();
        _sendReadReceipt();

      case WsFrameType.ack:
        final clientId = frame.data['client_id'] as String?;
        final serverId = frame.data['server_id'] as String?;
        final createdAtStr = frame.data['created_at'] as String?;
        if (clientId != null) {
          _repository.updateStatus(
            clientId,
            LocalStatus.delivered,
            serverId: serverId,
            serverCreatedAt: createdAtStr != null ? DateTime.tryParse(createdAtStr) : null,
          );
          setState(() {
            final idx = _messages.indexWhere((m) => m.clientId == clientId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(
                localStatus: LocalStatus.delivered,
                serverId: serverId,
                createdAt: createdAtStr != null ? DateTime.tryParse(createdAtStr) : null,
              );
            }
          });
        }

      case WsFrameType.typing:
        final senderTag = frame.data['sender_zendtag'] as String?;
        final isTyping = frame.data['is_typing'] as bool? ?? false;
        if (senderTag == null) break;
        if (isTyping) {
          _typingTimers[senderTag]?.cancel();
          _typingTimers[senderTag] = Timer(const Duration(seconds: 5), () {
            if (mounted) setState(() { _typingUsers.remove(senderTag); _typingTimers.remove(senderTag); });
          });
          setState(() => _typingUsers.add(senderTag));
        } else {
          _typingTimers[senderTag]?.cancel();
          _typingTimers.remove(senderTag);
          setState(() => _typingUsers.remove(senderTag));
        }

      case WsFrameType.error:
        final code = frame.data['code'] as String?;
        if (code == 'POOL_NOT_ACTIVE') {
          setState(() => _pool.status = PoolStatus.cancelled);
        }

      case WsFrameType.readReceipt:
        final readerTag = frame.data['reader_zendtag'] as String?;
        final lastReadId = frame.data['last_read_message_id'] as String?;
        final readerUserId = frame.data['reader_user_id'] as String?;
        if (readerTag != null && lastReadId != null) {
          // Look up avatar from pool participants.
          String? avatarUrl;
          if (readerUserId != null) {
            try {
              final participant = _pool.participants.firstWhere(
                (p) => p.userId == readerUserId,
              );
              avatarUrl = participant.avatarUrl;
            } catch (_) {
              // Participant not found — avatar stays null, initials will show.
            }
          }
          setState(() {
            _readReceipts[readerTag] = lastReadId;
            _readerAvatars[readerTag] = avatarUrl;
          });
        }

      case WsFrameType.reaction:
        final messageId = frame.data['message_id'] as String?;
        final emoji = frame.data['emoji'] as String?;
        final reactorZendtag = frame.data['reactor_zendtag'] as String?;
        if (messageId != null && emoji != null) {
          _updateReaction(messageId, emoji, reactorZendtag, increment: true);
        }

      case WsFrameType.reactionRemoved:
        final messageId = frame.data['message_id'] as String?;
        final emoji = frame.data['emoji'] as String?;
        final reactorZendtag = frame.data['reactor_zendtag'] as String?;
        if (messageId != null && emoji != null) {
          _updateReaction(messageId, emoji, reactorZendtag, increment: false);
        }

      default:
        break;
    }
  }

  // ── Local message management ─────────────────────────────────────────────────

  void _upsertMessageLocal(PoolMessageLocal msg) {
    final idx = _messages.indexWhere((m) => m.id == msg.id || (m.serverId != null && m.serverId == msg.serverId));
    if (idx >= 0) {
      _messages[idx] = msg;
    } else {
      _messages.add(msg);
    }
  }

  /// Sends a `read` frame for the last delivered message in the list.
  /// Only fires if the room is visible and the last message has a server ID.
  void _sendReadReceipt() {
    if (!mounted) return;
    // Find the last message with a server ID (delivered from server).
    for (var i = _messages.length - 1; i >= 0; i--) {
      final sid = _messages[i].serverId;
      if (sid != null && sid != _myLastReadMessageId) {
        _myLastReadMessageId = sid;
        _wsService.sendRead(sid);
        break;
      }
    }
  }

  /// Returns a map of {zendtag → avatarUrl} for readers who have read up to or past [messageServerId].
  Map<String, String?> _readersOf(String? messageServerId) {
    if (messageServerId == null || _readReceipts.isEmpty) return const {};
    final serverIdToIndex = <String, int>{};
    for (var i = 0; i < _messages.length; i++) {
      final sid = _messages[i].serverId;
      if (sid != null) serverIdToIndex[sid] = i;
    }
    final msgIndex = serverIdToIndex[messageServerId];
    if (msgIndex == null) return const {};

    return {
      for (final e in _readReceipts.entries)
        if ((serverIdToIndex[e.value] ?? -1) >= msgIndex)
          e.key: _readerAvatars[e.key],
    };
  }

  // ── Infinite scroll ──────────────────────────────────────────────────────────

  void _onScroll() {
    if (_loadingOlder || _fullyLoaded) return;
    if (_scrollController.hasClients && _scrollController.position.pixels <= 200) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || _fullyLoaded || _messages.isEmpty) return;
    // Capture context-dependent values before any await.
    final model = ZendScope.of(context);
    final poolId = _pool.id;
    setState(() => _loadingOlder = true);
    try {
      final oldest = _messages.first;
      final oldestCreatedAt = oldest.createdAt.toIso8601String();

      // Check local cache first
      final localOlder = await _repository.getOlderMessages(poolId, oldestCreatedAt);
      if (localOlder.isNotEmpty) {
        setState(() {
          _messages.insertAll(0, localOlder);
          _loadingOlder = false;
        });
        return;
      }

      // Fetch from server
      final oldestServerId = oldest.serverId;
      if (oldestServerId == null) {
        setState(() { _loadingOlder = false; _fullyLoaded = true; });
        return;
      }

      final fetched = await model.walletService.apiClient.listMessages(
        poolId: poolId,
        beforeId: oldestServerId,
        limit: 50,
      );
      if (!mounted) return;

      final localFetched = fetched.map(PoolMessageLocal.fromPoolMessage).toList();
      for (final msg in localFetched) {
        await _repository.upsertMessage(msg);
      }
      if (localFetched.isNotEmpty) {
        await _repository.upsertCursor(poolId, oldestFetchedServerId: localFetched.first.serverId);
      }

      setState(() {
        _messages.insertAll(0, localFetched);
        _loadingOlder = false;
        if (localFetched.length < 50) _fullyLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  // ── Data loading (legacy fallback) ───────────────────────────────────────────
  // Initial load is handled by _init() via local DB. This method is intentionally
  // empty — kept so _onAppResume can call it without a null check.
  // ignore: unused_element
  Future<void> _loadMessages() async {}

  // ── SSE ─────────────────────────────────────────────────────────────────────

  void _subscribeSse() {
    final model = ZendScope.of(context);
    _sseSub = model.sseService.events.listen(_onSseEvent);
  }

  void _onSseEvent(SseEvent event) {
    if (!mounted) return;

    final data = event.data;
    final poolId = data['pool_id'] as String?;
    if (poolId != _pool.id) return;

    switch (event.type) {
      // poolMessage is now handled via WebSocket — skip here

      case SseEventType.poolContribution:
        final gatheredStr = data['gathered_amount_usdc'] as String?;
        if (gatheredStr != null) {
          final gathered = double.tryParse(gatheredStr);
          if (gathered != null) setState(() => _pool.gathered = gathered);
        }

      // Reactions are now handled via WebSocket — skip SSE reaction events.

      case SseEventType.poolStatusChanged:
        final newStatus = data['new_status'] as String?;
        if (newStatus != null) {
          final statusMap = {
            'active': PoolStatus.active,
            'completed': PoolStatus.completed,
            'expired': PoolStatus.expired,
            'cancelled': PoolStatus.cancelled,
          };
          final status = statusMap[newStatus];
          if (status != null) setState(() => _pool.status = status);
        }

      default:
        break;
    }
  }

  void _updateReaction(
    String messageId,
    String emoji,
    String? reactorZendtag, {
    required bool increment,
  }) {
    final model = ZendScope.of(context);
    final isMe = reactorZendtag == model.currentZendtag;

    setState(() {
      final idx = _messages.indexWhere((m) => m.id == messageId || m.serverId == messageId);
      if (idx < 0) return;

      final msg = _messages[idx];
      final reactions = List<PoolReactionCount>.from(msg.reactions);
      final rIdx = reactions.indexWhere((r) => r.emoji == emoji);

      if (increment) {
        if (rIdx >= 0) {
          reactions[rIdx] = PoolReactionCount(
            emoji: emoji,
            count: reactions[rIdx].count + 1,
            reactedByMe: reactions[rIdx].reactedByMe || isMe,
          );
        } else {
          reactions.add(PoolReactionCount(emoji: emoji, count: 1, reactedByMe: isMe));
        }
      } else {
        if (rIdx >= 0) {
          final newCount = reactions[rIdx].count - 1;
          if (newCount <= 0) {
            reactions.removeAt(rIdx);
          } else {
            reactions[rIdx] = PoolReactionCount(
              emoji: emoji,
              count: newCount,
              reactedByMe: isMe ? false : reactions[rIdx].reactedByMe,
            );
          }
        }
      }

      _messages[idx] = msg.withReactions(reactions);

      // Persist updated reactions to local DB so they survive room reopen.
      final updatedMsg = _messages[idx];
      final dbMessageId = updatedMsg.serverId ?? updatedMsg.id;
      _repository.upsertReactions(
        dbMessageId,
        updatedMsg.reactions.map((r) => {
          'emoji': r.emoji,
          'count': r.count,
          'reacted_by_me': r.reactedByMe,
        }).toList(),
      );
    });
  }

  // ── Sending ─────────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final content = _textController.text.trim();
    if (content.isEmpty || content.length > 280) return;

    _textController.clear();

    final model = ZendScope.of(context);
    final clientId = const Uuid().v4();
    final now = DateTime.now();

    final optimistic = PoolMessageLocal(
      id: clientId,
      poolId: _pool.id,
      clientId: clientId,
      senderZendtag: model.currentZendtag,
      senderUserId: model.currentUserId,
      senderAvatarUrl: model.currentAvatarUrl,
      messageType: 'text',
      content: content,
      localStatus: LocalStatus.sending,
      createdAt: now,
    );

    // Write to local DB and show immediately
    await _repository.upsertMessage(optimistic);
    setState(() {
      _messages.add(optimistic);
      _sending = true;
    });
    _jumpToBottom();

    // Enqueue for WebSocket delivery
    _outboxQueue.enqueue(clientId, content);
    setState(() => _sending = false);
  }

  // ── Reactions ────────────────────────────────────────────────────────────────

  void _showReactionPicker(PoolMessageLocal message) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _EmojiPickerSheet(
        onEmojiTap: (emoji) {
          Navigator.of(context).pop();
          _toggleReaction(message, emoji);
        },
      ),
    );
  }

  Future<void> _toggleReaction(PoolMessageLocal message, String emoji) async {
    final model = ZendScope.of(context);
    final existing = message.reactions.firstWhere(
      (r) => r.emoji == emoji,
      orElse: () => const PoolReactionCount(emoji: '', count: 0, reactedByMe: false),
    );

    _updateReaction(message.id, emoji, model.currentZendtag,
        increment: !existing.reactedByMe);

    final messageId = message.serverId ?? message.id;
    try {
      if (existing.reactedByMe) {
        await model.walletService.apiClient.removeReaction(
          poolId: _pool.id, messageId: messageId, emoji: emoji);
      } else {
        await model.walletService.apiClient.addReaction(
          poolId: _pool.id, messageId: messageId, emoji: emoji);
      }
    } catch (_) {
      if (mounted) {
        _updateReaction(message.id, emoji, model.currentZendtag,
            increment: existing.reactedByMe);
      }
    }
  }

  // ── Recording ────────────────────────────────────────────────────────────────

  // ── Recording (stub — re-enable when AGP 8 compatible recorder ships) ─────────

  Future<void> _startRecording() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice notes coming soon 🎙️'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (mounted) setState(() => _isRecording = false);
  }

  // ── Voice note playback ───────────────────────────────────────────────────────

  Future<void> _togglePlayback(PoolMessageLocal message) async {
    final msgId = message.id;
    final url = message.voiceNoteUrl;
    if (url == null) return;

    // Stop any other playing message.
    for (final entry in _players.entries) {
      if (entry.key != msgId) {
        await entry.value.stop();
      }
    }

    if (_players.containsKey(msgId)) {
      final player = _players[msgId]!;
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
      return;
    }

    // New player for this message.
    final player = AudioPlayer();
    _players[msgId] = player;

    // Rebuild when playback state changes.
    player.playerStateStream.listen((_) { if (mounted) setState(() {}); });
    player.positionStream.listen((_) { if (mounted) setState(() {}); });

    player.playbackEventStream.listen(
      (_) {},
      onError: (error, stackTrace) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not play voice note')),
          );
        }
      },
    );

    try {
      await player.setUrl(url);
      await player.play();
      setState(() {});
    } catch (_) {
      _players.remove(msgId);
      player.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play voice note')),
        );
      }
    }
  }

  AudioPlayer? _playerFor(String messageId) => _players[messageId];

  // ── Scroll ───────────────────────────────────────────────────────────────────

  /// Jump instantly — no animation. Feels native, avoids jank.
  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  bool get _isActive => _pool.status == PoolStatus.active;

  // ── Build ────────────────────────────────────────────────────────────────────

  /// Builds the flat list of messages into a display list that includes
  /// date separator items and carries grouping metadata.
  List<_ListItem> _buildDisplayList() {
    final items = <_ListItem>[];
    DateTime? lastDate;
    String? lastSenderId;
    DateTime? lastMessageTime;

    for (var i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      final msgDate = DateTime(
          msg.createdAt.year, msg.createdAt.month, msg.createdAt.day);

      // Date separator
      if (lastDate == null || msgDate != lastDate) {
        items.add(_DateSeparatorItem(date: msgDate));
        lastDate = msgDate;
        lastSenderId = null; // reset grouping across date boundaries
        lastMessageTime = null;
      }

      // Grouping: same sender within 2 minutes = continuation
      final isContinuation = lastSenderId != null &&
          lastSenderId == msg.senderUserId &&
          lastMessageTime != null &&
          msg.createdAt.difference(lastMessageTime).inMinutes < 2 &&
          msg.messageTypeEnum == PoolMessageType.text;

      items.add(_MessageItem(message: msg, isContinuation: isContinuation));
      lastSenderId = msg.senderUserId;
      lastMessageTime = msg.createdAt;
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final currentUserId = model.currentUserId;

    return Column(
      children: [
        // ── Reconnecting banner ──
        if (_showReconnecting)
          Builder(builder: (context) {
            final zt = ZendTheme.of(context);
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: ZendSpacing.lg, vertical: ZendSpacing.xs),
              color: zt.bgSecondary,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ZendLoader(size: 12, strokeWidth: 1.5, color: zt.textSecondary),
                  const SizedBox(width: 8),
                  Text('Reconnecting...', style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: zt.textSecondary)),
                ],
              ),
            );
          }),

        // ── Could not connect banner ──
        if (!_showReconnecting && _wsService.consecutiveFailures >= 5)
          Builder(builder: (context) {
            final zt = ZendTheme.of(context);
            return GestureDetector(
              onTap: () => _wsService.resetAndReconnect(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: ZendSpacing.lg, vertical: ZendSpacing.xs),
                color: ZendColors.destructive.withValues(alpha: 0.1),
                child: Text(
                  'Could not connect. Tap to retry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: zt.textPrimary),
                ),
              ),
            );
          }),

        // ── Closed-pool archive banner ──
        if (!_isActive)
          Builder(builder: (context) {
            final zt = ZendTheme.of(context);
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: ZendSpacing.lg, vertical: ZendSpacing.xs),
              color: zt.bgSecondary,
              child: Text(
                'This pool has closed — messages are read-only',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: zt.textSecondary),
              ),
            );
          }),

        // ── Message list ──
        Expanded(
          child: _loading
              ? Center(
                  child: ZendLoader(color: ZendTheme.of(context).accentBright),
                )
              : _messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet. Say something! 👋',
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: ZendTheme.of(context).textSecondary),
                      ),
                    )
                  : Stack(
                      children: [
                        Builder(builder: (context) {
                          final displayList = _buildDisplayList();
                          return ListView.builder(
                            controller: _scrollController,
                            cacheExtent: 500,
                            padding: const EdgeInsets.symmetric(
                                horizontal: ZendSpacing.lg,
                                vertical: ZendSpacing.xs),
                            itemCount: displayList.length + (_loadingOlder ? 1 : 0),
                            itemBuilder: (_, i) {
                              // Loading older indicator at top
                              if (_loadingOlder && i == 0) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: ZendLoader(
                                      size: 20,
                                      strokeWidth: 2,
                                      color: ZendTheme.of(context).accentBright,
                                    ),
                                  ),
                                );
                              }
                              final listIdx = _loadingOlder ? i - 1 : i;
                              final item = displayList[listIdx];
                              if (item is _DateSeparatorItem) {
                                return _DateSeparator(date: item.date);
                              }
                              final msgItem = item as _MessageItem;
                              final msg = msgItem.message;
                              return RepaintBoundary(
                                child: MissionRoomMessage(
                                  key: ValueKey(msg.id),
                                  message: msg,
                                  currentUserId: currentUserId,
                                  isContinuation: msgItem.isContinuation,
                                  onLongPress: () => _showReactionPicker(msg),
                                  onReactionTap: (emoji) => _toggleReaction(msg, emoji),
                                  // Only show read receipt avatars on my own messages.
                                  readers: msg.senderUserId == currentUserId
                                      ? _readersOf(msg.serverId)
                                      : const {},
                                  player: _playerFor(msg.id),
                                  onPlayTap: msg.messageTypeEnum == PoolMessageType.voiceNote
                                      ? () => _togglePlayback(msg)
                                      : null,
                                  onRetry: msg.localStatus == LocalStatus.failed
                                      ? () {
                                          if (msg.clientId != null && msg.content != null) {
                                            _repository.updateStatus(msg.clientId!, LocalStatus.sending);
                                            setState(() {
                                              final idx = _messages.indexWhere((m) => m.id == msg.id);
                                              if (idx >= 0) _messages[idx] = msg.copyWith(localStatus: LocalStatus.sending);
                                            });
                                            _outboxQueue.enqueue(msg.clientId!, msg.content!);
                                          } else if (msg.messageTypeEnum == PoolMessageType.voiceNote &&
                                              msg.clientId != null) {
                                            _repository.updateStatus(msg.clientId!, LocalStatus.failed);
                                          }
                                        }
                                      : null,
                                ),
                              );
                            },
                          );
                        }),

                        // ── Scroll-to-bottom button ──
                        _ScrollToBottomButton(
                          scrollController: _scrollController,
                        ),
                      ],
                    ),
        ),

        // ── Typing indicator ──
        if (_typingUsers.isNotEmpty)
          _TypingIndicator(typingUsers: _typingUsers.toList()),

        // ── Input bar ──
        if (_isActive)
          _InputBar(
            controller: _textController,
            sending: _sending,
            isRecording: _isRecording,
            recordingSeconds: _recordingSeconds,
            onSend: _sendMessage,
            onMicStart: _startRecording,
            onMicStop: _stopRecording,
            onTyping: (isTyping) => _wsService.sendTyping(isTyping),
          ),
      ],
    );
  }
}

// ── Display list items ────────────────────────────────────────────────────────

sealed class _ListItem {}

class _DateSeparatorItem extends _ListItem {
  _DateSeparatorItem({required this.date});
  final DateTime date;
}

class _MessageItem extends _ListItem {
  _MessageItem({required this.message, required this.isContinuation});
  final PoolMessageLocal message;
  final bool isContinuation;
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.typingUsers});
  final List<String> typingUsers;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _label {
    final users = widget.typingUsers;
    if (users.length == 1) return '@${users[0]} is typing...';
    if (users.length == 2) return '@${users[0]} and @${users[1]} are typing...';
    return 'Several people are typing...';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZendSpacing.lg, 4, ZendSpacing.lg, 0),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final delay = i / 3;
                  final value = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
                  final opacity = value < 0.5 ? value * 2 : (1 - value) * 2;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Opacity(
                      opacity: opacity.clamp(0.3, 1.0),
                      child: Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          color: zt.textSecondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: zt.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});
  final DateTime date;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (date == today) return 'Today';
    if (date == yesterday) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: zt.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _label(),
              style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary, letterSpacing: 0.4),
            ),
          ),
          Expanded(child: Divider(color: zt.border)),
        ],
      ),
    );
  }
}

// ── Scroll-to-bottom button ──────────────────────────────────────────────────

/// Self-contained scroll-to-bottom button that attaches its own listener
/// to the scroll controller. This avoids the AnimatedBuilder-on-unattached-
/// controller issue that caused a transparent overlay on first open.
class _ScrollToBottomButton extends StatefulWidget {
  const _ScrollToBottomButton({required this.scrollController});
  final ScrollController scrollController;

  @override
  State<_ScrollToBottomButton> createState() => _ScrollToBottomButtonState();
}

class _ScrollToBottomButtonState extends State<_ScrollToBottomButton> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final pos = widget.scrollController.position;
    final shouldShow = pos.maxScrollExtent > 0 &&
        pos.maxScrollExtent - pos.pixels > 120;
    if (shouldShow != _show) {
      setState(() => _show = shouldShow);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Positioned(
      right: 12,
      bottom: 8,
      child: GestureDetector(
        onTap: () {
          if (!widget.scrollController.hasClients) return;
          widget.scrollController.animateTo(
            widget.scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: ZendTheme.of(context).accent,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: const Icon(SolarIconsBold.altArrowDown, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.isRecording,
    required this.recordingSeconds,
    required this.onSend,
    required this.onMicStart,
    required this.onMicStop,
    required this.onTyping,
  });

  final TextEditingController controller;
  final bool sending;
  final bool isRecording;
  final int recordingSeconds;
  final VoidCallback onSend;
  final Future<void> Function() onMicStart;
  final Future<void> Function() onMicStop;
  final void Function(bool) onTyping;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  int _charCount = 0;
  bool _isTyping = false;
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _typingDebounce?.cancel();
    if (_isTyping) widget.onTyping(false);
    super.dispose();
  }

  void _onTextChanged() {
    final len = widget.controller.text.length;
    if (len != _charCount) setState(() => _charCount = len);

    if (len == 0) {
      _typingDebounce?.cancel();
      if (_isTyping) {
        _isTyping = false;
        widget.onTyping(false);
      }
      return;
    }

    if (!_isTyping) {
      _isTyping = true;
      widget.onTyping(true);
    }

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 3), () {
      if (_isTyping) {
        _isTyping = false;
        widget.onTyping(false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = 280 - _charCount;
    final overLimit = remaining < 0;
    // Keyboard inset — pushes the bar above the keyboard, WhatsApp-style
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(ZendSpacing.md, ZendSpacing.xs, ZendSpacing.md, ZendSpacing.sm),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: ZendTheme.of(context).border)),
        ),
        child: widget.isRecording
            ? Row(
                children: [
                  const Icon(SolarIconsBold.recordCircle, color: ZendColors.destructive, size: 14),
                  const SizedBox(width: ZendSpacing.xs),
                  Text(
                    'Recording ${widget.recordingSeconds}s / 30s',
                    style: TextStyle(fontFamily: 'DMMono', fontSize: 13, color: ZendTheme.of(context).textPrimary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => unawaited(widget.onMicStop()),
                    child: const Text('Stop', style: TextStyle(fontFamily: 'DMSans', fontWeight: FontWeight.w600, color: ZendColors.destructive)),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      maxLines: 4,
                      minLines: 1,
                      maxLength: 280,
                      textInputAction: TextInputAction.newline,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) {
                        if (!isFocused || !overLimit) return null;
                        return Text('$remaining', style: const TextStyle(fontFamily: 'DMMono', fontSize: 11, color: ZendColors.destructive));
                      },
                      decoration: InputDecoration(
                        hintText: 'Message the group...',
                        hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: ZendTheme.of(context).textSecondary),
                        filled: true,
                        fillColor: ZendTheme.of(context).bgSecondary,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZendRadii.pill), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: ZendSpacing.xs),
                  GestureDetector(
                    onLongPressStart: (_) => unawaited(widget.onMicStart()),
                    onLongPressEnd: (_) => unawaited(widget.onMicStop()),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: ZendTheme.of(context).bgSecondary, shape: BoxShape.circle),
                      child: Icon(SolarIconsBold.microphone, size: 20, color: ZendTheme.of(context).textSecondary),
                    ),
                  ),
                  const SizedBox(width: ZendSpacing.xs),
                  GestureDetector(
                    onTap: overLimit || widget.sending || _charCount == 0 ? null : widget.onSend,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: overLimit || _charCount == 0 ? ZendTheme.of(context).bgSecondary : ZendTheme.of(context).accent,
                        shape: BoxShape.circle,
                      ),
                      child: widget.sending
                          ? Padding(padding: const EdgeInsets.all(10), child: ZendLoader(size: 20, strokeWidth: 2, color: Colors.white))
                          : Icon(SolarIconsBold.sendSquare, size: 18, color: overLimit || _charCount == 0 ? ZendTheme.of(context).textSecondary : Colors.white),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Emoji picker ──────────────────────────────────────────────────────────────

class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet({required this.onEmojiTap});
  final ValueChanged<String> onEmojiTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(0, 14, 0, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(ZendRadii.pill)),
          ),
          const SizedBox(height: ZendSpacing.md),
          for (var row = 0; row < 2; row++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: List.generate(6, (col) {
                  final emoji = _curatedEmojis[row * 6 + col];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onEmojiTap(emoji),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: zt.bgSecondary, borderRadius: BorderRadius.circular(ZendRadii.md)),
                          child: Text(emoji, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (row == 0) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

// ── Lifecycle observer ────────────────────────────────────────────────────────

/// Lightweight [WidgetsBindingObserver] that fires [onResume] when the app
/// returns to the foreground. Used by [MissionRoom] to reload messages after
/// the app was backgrounded (SSE is paused while backgrounded, so messages
/// sent by others during that window would otherwise be missed).
class _LifecycleObserver extends WidgetsBindingObserver {
  _LifecycleObserver({required this.onResume});

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }

  // Two observers are equal if they have the same onResume callback reference,
  // which allows removeObserver to find and remove the correct instance.
  //
  // NOTE: This override is kept for reference only. The stored _lifecycleObserver
  // field is used for removal, so identity comparison works correctly.
  @override
  bool operator ==(Object other) =>
      other is _LifecycleObserver && other.onResume == onResume;

  @override
  int get hashCode => onResume.hashCode;
}
