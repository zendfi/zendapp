import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';
import '../../models/dm_thread.dart';
import '../../navigation/zend_routes.dart';
import '../../services/dm_websocket_service.dart';
import '../profile/user_profile_screen.dart';
import '../vibes/vibe_picker_sheet.dart';
import 'dm_message_bubble.dart';
import 'dm_input_bar.dart';
import 'package:solar_icons/solar_icons.dart';

class DmThreadScreen extends StatefulWidget {
  const DmThreadScreen({
    super.key,
    required this.roomId,
    required this.counterparty,
  });

  final String roomId;
  final DmCounterparty counterparty;

  @override
  State<DmThreadScreen> createState() => _DmThreadScreenState();
}

class _DmThreadScreenState extends State<DmThreadScreen>
    with WidgetsBindingObserver {
  late final DmWebSocketService _ws;
  StreamSubscription? _wsSub;

  final _messages = <DmMessage>[];
  bool _loading = true;
  bool _theyAreTyping = false;
  Timer? _typingClearTimer;
  String? _nextCursor;
  bool _loadingMore = false;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWs();
    _loadMessages();
    _scrollController.addListener(_onScroll);
  }

  void _initWs() {
    final model = ZendScope.of(context);
    _ws = DmWebSocketService(
      roomId: widget.roomId,
      baseWsUrl: model.walletService.apiClient.baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://'),
      getToken: () => model.walletService.apiClient.getToken(),
    );
    _ws.connect();

    _wsSub = _ws.frames.listen((frame) {
      if (!mounted) return;
      switch (frame.type) {
        case WsFrameType.message:
          final msg = DmMessage.fromJson(frame.data);
          setState(() {
            // Remove any optimistic version of this message
            _messages.removeWhere((m) =>
                m.clientId != null && m.clientId == msg.clientId);
            _messages.insert(0, msg);
          });
          if (msg.senderUserId != model.currentUserId) {
            _ws.sendRead(msg.id);
          }
        case WsFrameType.typing:
          final isTyping = frame.data['is_typing'] as bool? ?? false;
          final senderId = frame.data['sender_user_id'] as String?;
          if (senderId != model.currentUserId) {
            setState(() => _theyAreTyping = isTyping);
            if (isTyping) {
              _typingClearTimer?.cancel();
              _typingClearTimer =
                  Timer(const Duration(seconds: 4), () {
                if (mounted) setState(() => _theyAreTyping = false);
              });
            }
          }
        case WsFrameType.ack:
          final clientId = frame.data['client_id'] as String?;
          if (clientId != null) {
            setState(() {
              final idx =
                  _messages.indexWhere((m) => m.clientId == clientId);
              if (idx != -1) {
                _messages[idx].localStatus = DmLocalStatus.delivered;
              }
            });
          }
        default:
          break;
      }
    });
  }

  Future<void> _loadMessages({bool more = false}) async {
    if (more && (_loadingMore || _nextCursor == null)) return;
    if (!more) setState(() => _loading = _messages.isEmpty);
    if (more) setState(() => _loadingMore = true);

    try {
      final model = ZendScope.of(context);
      final result = await model.dmService.getMessages(
        widget.roomId,
        cursor: more ? _nextCursor : null,
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          _messages.addAll(result.messages);
        } else {
          _messages
            ..clear()
            ..addAll(result.messages);
        }
        _nextCursor = result.nextCursor;
        _loading = false;
        _loadingMore = false;
      });
      // Mark as read
      if (_messages.isNotEmpty) {
        model.dmService.markRead(widget.roomId, _messages.first.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onScroll() {
    // Load more when near the bottom (reversed list, bottom = old messages)
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 200) {
      _loadMessages(more: true);
    }
  }

  void _onSend(String text) {
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final model = ZendScope.of(context);
    final clientId = DateTime.now().millisecondsSinceEpoch.toString();

    final optimistic = DmMessage.optimistic(
      roomId: widget.roomId,
      senderUserId: model.currentUserId ?? '',
      senderZendtag: model.currentZendtag ?? '',
      senderAvatarUrl: model.currentAvatarUrl,
      content: text,
      clientId: clientId,
    );

    setState(() => _messages.insert(0, optimistic));

    // Try WebSocket first
    _ws.sendMessage(clientId, text);

    // HTTP fallback after 2s if WS not confirmed
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      final idx =
          _messages.indexWhere((m) => m.clientId == clientId);
      if (idx != -1 &&
          _messages[idx].localStatus == DmLocalStatus.sending) {
        model.dmService.sendMessage(widget.roomId, text, clientId).then((_) {
          if (mounted) {
            setState(() {
              final i = _messages.indexWhere((m) => m.clientId == clientId);
              if (i != -1) {
                _messages[i].localStatus = DmLocalStatus.delivered;
              }
            });
          }
        }).catchError((_) {
          if (mounted) {
            setState(() {
              final i = _messages.indexWhere((m) => m.clientId == clientId);
              if (i != -1) {
                _messages[i].localStatus = DmLocalStatus.failed;
              }
            });
          }
        });
      }
    });
  }

  void _onRetry(String clientId) {
    final idx = _messages.indexWhere((m) => m.clientId == clientId);
    if (idx == -1) return;
    final msg = _messages[idx];
    if (msg.content == null) return;
    setState(() => _messages[idx].localStatus = DmLocalStatus.sending);
    _ws.sendMessage(clientId, msg.content!);
  }

  Future<void> _onSendVibe(VibeSendResult vibe) async {
    final model = ZendScope.of(context);
    final clientId =
        'vibe_${DateTime.now().millisecondsSinceEpoch}';

    // Optimistic bubble
    final optimistic = DmMessage(
      id: clientId,
      roomId: widget.roomId,
      senderUserId: model.currentUserId ?? '',
      senderZendtag: model.currentZendtag,
      senderAvatarUrl: model.currentAvatarUrl,
      type: DmMessageType.vibe,
      vibeData: DmVibeData(
        stickerId: vibe.stickerId,
        stickerSlug: vibe.stickerEmoji,
        stickerName: vibe.stickerLabel,
        amountUsdc: vibe.amountUsdc.toString(),
        transferId: '',
      ),
      clientId: clientId,
      createdAt: DateTime.now(),
      localStatus: DmLocalStatus.sending,
    );
    setState(() => _messages.insert(0, optimistic));

    try {
      await model.dmService.sendVibe(
        widget.roomId,
        stickerId: vibe.stickerId,
        amountUsdc: vibe.amountUsdc,
        clientId: clientId,
      );
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.clientId == clientId);
          if (i != -1) _messages[i].localStatus = DmLocalStatus.delivered;
        });
        // Refresh balance since funds moved
        model.fetchBalance();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.clientId == clientId);
          if (i != -1) _messages[i].localStatus = DmLocalStatus.failed;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ws.resetAndReconnect();
      _loadMessages();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    _ws.dispose();
    _scrollController.dispose();
    _typingClearTimer?.cancel();
    super.dispose();
  }

  bool _isContinuation(int index) {
    if (index >= _messages.length - 1) return false;
    final current = _messages[index];
    final next = _messages[index + 1]; // older message (list is reversed)
    if (current.senderUserId != next.senderUserId) return false;
    return current.createdAt.difference(next.createdAt).inSeconds.abs() < 60;
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final cp = widget.counterparty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── AppBar ────────────────────────────────────────────────────
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(SolarIconsBold.altArrowLeft,
                        color: zt.textPrimary),
                  ),
                  GestureDetector(
                    onTap: () => pushZendSlide(
                      context,
                      UserProfileScreen(zendtag: cp.zendtag),
                    ),
                    child: ZendAvatar(
                      radius: 18,
                      photoUrl: cp.avatarUrl,
                      initials: cp.initialLetter,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => pushZendSlide(
                        context,
                        UserProfileScreen(zendtag: cp.zendtag),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            cp.displayName.trim().isEmpty
                                ? '@${cp.zendtag}'
                                : cp.displayName,
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: zt.textPrimary,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '@${cp.zendtag}',
                                style: TextStyle(
                                  fontFamily: 'DMMono',
                                  fontSize: 11,
                                  color: zt.textSecondary,
                                ),
                              ),
                              Builder(builder: (ctx) {
                                final streak = model.activeStreaks[cp.userId];
                                if (streak == null || !streak.isActive) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    '🔥 ${streak.streakWeeks}w',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: zt.border),

            // ── Messages ──────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: ZendLoader(size: 24))
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: _messages.length +
                          (_theyAreTyping ? 1 : 0) +
                          (_loadingMore ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        // Load more spinner at bottom of reversed list
                        if (_loadingMore &&
                            i == _messages.length + (_theyAreTyping ? 1 : 0)) {
                          return const Padding(
                            padding: EdgeInsets.all(8),
                            child: Center(child: ZendLoader(size: 18)),
                          );
                        }
                        // Typing indicator at top of reversed list (index 0)
                        if (_theyAreTyping && i == 0) {
                          return _TypingIndicator(
                              avatarUrl: cp.avatarUrl,
                              initial: cp.initialLetter);
                        }
                        final msgIdx = _theyAreTyping ? i - 1 : i;
                        final msg = _messages[msgIdx];
                        return DmMessageBubble(
                          message: msg,
                          isMe: msg.senderUserId ==
                              model.currentUserId,
                          isContinuation: _isContinuation(msgIdx),
                          onRetry: msg.localStatus == DmLocalStatus.failed
                              ? () => _onRetry(msg.clientId ?? '')
                              : null,
                        );
                      },
                    ),
            ),

            // ── Input ─────────────────────────────────────────────────────
            DmInputBar(
              onSend: _onSend,
              onTyping: (v) => _ws.sendTyping(v),
              roomId: widget.roomId,
              onSendVibe: _onSendVibe,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.avatarUrl, required this.initial});
  final String? avatarUrl;
  final String initial;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          ZendAvatar(
              radius: 14,
              photoUrl: widget.avatarUrl,
              initials: widget.initial),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final offset = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
                    final scale = 0.6 + 0.4 * (offset < 0.5 ? offset * 2 : (1 - offset) * 2);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 7, height: 7,
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
          ),
        ],
      ),
    );
  }
}
