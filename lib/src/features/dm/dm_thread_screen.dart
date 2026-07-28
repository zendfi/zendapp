import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';
import '../../models/dm_thread.dart';
import '../../navigation/zend_routes.dart';
import '../../services/dm_websocket_service.dart';
import '../../services/wallet_session_cache.dart';
import '../../models/qr_payment_intent.dart';
import '../profile/user_profile_screen.dart';
import '../send/qr_payment_sheet.dart';
import '../vibes/vibe_picker_sheet.dart';
import '../vibes/vibe_pin_prompt.dart';
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
  bool _theyAreRecording = false;  // "recording audio..." indicator
  // Counterparty presence
  bool? _counterpartyOnline;        // null = unknown, true = online, false = offline
  DateTime? _counterpartyLastSeen;  // null = hidden by privacy setting
  // E2EE
  String? _counterpartyPubkey;      // counterparty's Ed25519 pubkey (base58)
  bool get _e2eeReady => _counterpartyPubkey != null;
  Timer? _typingClearTimer;
  Timer? _recordingClearTimer;
  String? _nextCursor;
  bool _loadingMore = false;
  bool _showScrollToBottom = false;
  bool _showTimestamps = false;      // revealed by left-edge swipe
  DmMessage? _replyingTo;           // the message being replied to

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Seed with cached messages immediately — no spinner for known rooms
    final model = ZendScope.of(context);
    final cached = model.dmService.getCachedMessages(widget.roomId);
    if (cached.isNotEmpty) {
      _messages.addAll(cached);
      _loading = false;
    }
    _initWs();
    _loadMessages();
    _scrollController.addListener(_onScroll);
    _fetchCounterpartyPubkey();
  }

  Future<void> _fetchCounterpartyPubkey() async {
    final model = ZendScope.of(context);

    // Publish our key before checking the other user. The former ordering only
    // registered a key after a counterparty already had one, so two newly
    // upgraded users could never bootstrap E2EE.
    final walletAddress = await model.walletService.getWalletAddress();
    if (walletAddress != null) {
      await model.e2eeService.registerPubkey(walletAddress);
    }

    final pubkey = await model.e2eeService.fetchCounterpartyPubkey(
      widget.counterparty.userId,
    );
    if (!mounted || pubkey == null) return;
    setState(() => _counterpartyPubkey = pubkey);
    // _loadMessages() may have already finished (or the room may have been
    // seeded from cache in initState) before the counterparty key arrived —
    // in that case any e2ee: messages were left as raw ciphertext because
    // _e2eeReady was false at load time. Decrypt the currently-held list now
    // that the key is available so we never display ciphertext to the user.
    await _decryptMessages(_messages);
    if (mounted) setState(() {});
  }

  void _initWs() {
    final model = ZendScope.of(context);
    _ws = DmWebSocketService(
      roomId: widget.roomId,
      baseWsUrl: model.walletService.apiClient.baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://'),
      getToken: () => model.walletService.apiClient.getToken(),
      apiClient: model.walletService.apiClient,
    );
    _ws.connect();

    _wsSub = _ws.frames.listen((frame) {
      if (!mounted) return;
      switch (frame.type) {
        case WsFrameType.message:
          final msg = DmMessage.fromJson(frame.data);
          // Unmark the room as cleared when new messages arrive from the other party,
          // so reopening the chat will show history again.
          if (model.dmService.isRoomCleared(widget.roomId) &&
              msg.senderUserId != model.currentUserId) {
            model.dmService.unmarkCleared(widget.roomId);
          }
          // Decrypt E2EE content inline before displaying
          if (msg.content != null && msg.content!.startsWith('e2ee:')) {
            _decryptIfNeeded(msg.content).then((plain) {
              if (!mounted) return;
              msg.content = plain ?? msg.content;
              msg.isEncrypted = true;
              setState(() {
                _messages.removeWhere((m) =>
                    m.clientId != null && m.clientId == msg.clientId);
                _messages.insert(0, msg);
              });
            });
          } else {
            setState(() {
              // Remove any optimistic version of this message
              _messages.removeWhere((m) =>
                  m.clientId != null && m.clientId == msg.clientId);
              _messages.insert(0, msg);
            });
          }
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
        case WsFrameType.reaction:
          final messageId = frame.data['message_id'] as String?;
          final emoji = frame.data['emoji'] as String?;
          final reactorUserId = frame.data['reactor_user_id'] as String?;
          if (messageId != null && emoji != null) {
            setState(() {
              final idx = _messages.indexWhere((m) => m.id == messageId);
              if (idx != -1) {
                final isMe = reactorUserId == model.currentUserId;
                final existing = _messages[idx].reactions.indexWhere((r) => r.emoji == emoji);
                final updated = List<DmReaction>.from(_messages[idx].reactions);
                if (existing != -1) {
                  // Only increment if the reactor is not the current user
                  // (current user already applied it optimistically)
                  if (!isMe) {
                    updated[existing] = updated[existing].copyWith(
                      count: updated[existing].count + 1,
                    );
                  }
                } else {
                  updated.add(DmReaction(emoji: emoji, count: 1, reactedByMe: isMe));
                }
                _messages[idx].reactions = updated;
              }
            });
          }
        case WsFrameType.reactionRemoved:
          final messageId = frame.data['message_id'] as String?;
          final emoji = frame.data['emoji'] as String?;
          final reactorUserId = frame.data['reactor_user_id'] as String?;
          if (messageId != null && emoji != null) {
            setState(() {
              final idx = _messages.indexWhere((m) => m.id == messageId);
              if (idx != -1) {
                final isMe = reactorUserId == model.currentUserId;
                final updated = _messages[idx].reactions
                    .map((r) {
                      if (r.emoji != emoji) return r;
                      // Don't double-remove for current user (already applied optimistically)
                      if (isMe) return null;
                      if (r.count <= 1) return null;
                      return r.copyWith(count: r.count - 1);
                    })
                    .whereType<DmReaction>()
                    .toList();
                _messages[idx].reactions = updated;
              }
            });
          }
        default:
          // Handle presence + recording frames
          if (frame.type == WsFrameType.presenceUpdate) {
            final userId = frame.data['user_id'] as String?;
            if (userId != null && userId != model.currentUserId) {
              final online = frame.data['is_online'] as bool? ?? false;
              // Update service-level presence cache so the DM list can show dots
              model.dmService.presenceCache[userId] = online;
              setState(() {
                _counterpartyOnline = online;
                final lastSeenStr = frame.data['last_seen_at'] as String?;
                if (lastSeenStr != null && lastSeenStr != 'hidden' && lastSeenStr != 'never') {
                  _counterpartyLastSeen = DateTime.tryParse(lastSeenStr)?.toLocal();
                } else {
                  _counterpartyLastSeen = null;
                }
              });
            }
          } else if (frame.type == WsFrameType.recordingAudio) {
            final senderId = frame.data['sender_user_id'] as String?;
            final isRecording = frame.data['is_recording'] as bool? ?? false;
            if (senderId != null && senderId != model.currentUserId) {
              setState(() => _theyAreRecording = isRecording);
              if (isRecording) {
                _recordingClearTimer?.cancel();
                _recordingClearTimer = Timer(const Duration(seconds: 30), () {
                  if (mounted) setState(() => _theyAreRecording = false);
                });
              } else {
                _recordingClearTimer?.cancel();
              }
            }
          }
          break;
      }
    });
  }

  Future<void> _loadMessages({bool more = false}) async {
    // If the user cleared this room, don't reload from server — show empty.
    // New incoming WS messages will populate it naturally and unmark the clear.
    final model = ZendScope.of(context);
    if (!more && model.dmService.isRoomCleared(widget.roomId)) {
      // Make sure we're not stuck in loading state
      if (_loading) setState(() => _loading = false);
      return;
    }
    if (more && (_loadingMore || _nextCursor == null)) return;
    // Only show the full-screen spinner if we have nothing to display yet
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
          // Merge: keep any optimistic messages (local-only) and replace the rest
          final localOnly = _messages.where((m) => m.id.startsWith('local-')).toList();
          _messages
            ..clear()
            ..addAll(result.messages)
            ..insertAll(0, localOnly);
        }
        _nextCursor = result.nextCursor;
        _loading = false;
        _loadingMore = false;
      });
      // Decrypt E2EE messages after loading
      if (_e2eeReady) {
        await _decryptMessages(_messages);
        if (mounted) setState(() {});
      }
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
    // Show scroll-to-bottom button when scrolled up more than 200px
    final shouldShow = _scrollController.position.pixels > 200;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  void _onSend(String text) {
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final model = ZendScope.of(context);
    final clientId = const Uuid().v4();

    // Sending a new message means the user is actively chatting again —
    // unmark the room as cleared so history reloads on the next open.
    if (model.dmService.isRoomCleared(widget.roomId)) {
      model.dmService.unmarkCleared(widget.roomId);
    }

    final optimistic = DmMessage.optimistic(
      roomId: widget.roomId,
      senderUserId: model.currentUserId ?? '',
      senderZendtag: model.currentZendtag ?? '',
      senderAvatarUrl: model.currentAvatarUrl,
      content: text,
      clientId: clientId,
    );

    setState(() => _messages.insert(0, optimistic));

    // Encrypt if E2EE is active, then send
    _encryptForSend(text).then((wireContent) {
      // Try WebSocket first
      _ws.sendMessage(clientId, wireContent);

      // HTTP fallback after 1.5s if WS ack not received — covers dropped frames
      // or a WS that went silent without closing cleanly.
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        final idx =
            _messages.indexWhere((m) => m.clientId == clientId);
        if (idx != -1 &&
            _messages[idx].localStatus == DmLocalStatus.sending) {
          model.dmService.sendMessage(widget.roomId, wireContent, clientId).then((_) {
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
    });
  }

  /// Sends a reply message — carries structured quote context so the bubble
  /// renders a proper in-bubble quote block instead of a text prefix.
  ///
  /// Reply messages always go via HTTP (not WS) so the reply metadata
  /// (replyToContent / replyToSenderZendtag) is persisted on the server.
  /// The WS-only path only supports plain content — metadata would be lost.
  /// The SSE fan-out and WS broadcast still happen server-side, so the
  /// counterparty sees the message in real time.
  void _onSendWithReply(String text, DmMessage quotedMsg) {
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final model = ZendScope.of(context);
    final clientId = const Uuid().v4();
    if (model.dmService.isRoomCleared(widget.roomId)) {
      model.dmService.unmarkCleared(widget.roomId);
    }

    // Build the quoted preview — use the actual message ID for reliable lookup
    final quoteContent = switch (quotedMsg.type) {
      DmMessageType.payment        => '💸 Payment',
      DmMessageType.vibe           => '✨ Vibe',
      DmMessageType.paymentRequest => '↙ Payment request',
      // Use displayContent, not content — if the quoted message hasn't
      // finished decrypting yet, content still holds the raw `e2ee:` blob
      // and we must never let that leak into the reply-quote metadata.
      _                            => quotedMsg.displayContent ?? '',
    };
    // Use the real server ID, not a local-* id (optimistic messages don't have a stable ID yet)
    final replyToId = quotedMsg.id.startsWith('local-') ? null : quotedMsg.id;

    final optimistic = DmMessage(
      id: 'local-$clientId',
      roomId: widget.roomId,
      senderUserId: model.currentUserId ?? '',
      senderZendtag: model.currentZendtag,
      senderAvatarUrl: model.currentAvatarUrl,
      type: DmMessageType.text,
      content: text,
      clientId: clientId,
      createdAt: DateTime.now(),
      localStatus: DmLocalStatus.sending,
      replyToContent: quoteContent,
      replyToSenderZendtag: quotedMsg.senderZendtag,
      replyToMessageId: replyToId,
    );

    setState(() => _messages.insert(0, optimistic));

    _encryptForSend(text).then((wireContent) {
      // Send over WS with full reply context — backend now persists metadata
      _ws.sendMessageWithReply(
        clientId,
        wireContent,
        replyToMessageId: replyToId,
        replyToContent: quoteContent,
        replyToSenderZendtag: quotedMsg.senderZendtag,
      );

      // HTTP fallback after 1.5s (also carries reply metadata via DmService)
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        final idx = _messages.indexWhere((m) => m.clientId == clientId);
        if (idx != -1 && _messages[idx].localStatus == DmLocalStatus.sending) {
          model.dmService.sendMessage(
            widget.roomId, wireContent, clientId,
            replyToContent: quoteContent,
            replyToSenderZendtag: quotedMsg.senderZendtag,
            replyToMessageId: replyToId,
          ).then((_) {
            if (mounted) {
              setState(() {
                final i = _messages.indexWhere((m) => m.clientId == clientId);
                if (i != -1) _messages[i].localStatus = DmLocalStatus.delivered;
              });
            }
          }).catchError((_) {
            if (mounted) {
              setState(() {
                final i = _messages.indexWhere((m) => m.clientId == clientId);
                if (i != -1) _messages[i].localStatus = DmLocalStatus.failed;
              });
            }
          });
        }
      });
    });
  }

  Widget _buildPresenceSubtitle(ZendTheme zt, DmCounterparty cp) {
    // Priority: recording > typing > online/last seen > zendtag
    if (_theyAreRecording) {
      return _PresenceLabel(
        text: 'recording audio…',
        color: zt.accent,
        dot: true,
      );
    }
    if (_theyAreTyping) {
      return _PresenceLabel(
        text: 'typing…',
        color: zt.accent,
        dot: true,
      );
    }
    if (_counterpartyOnline == true) {
      return _PresenceLabel(
        text: 'online',
        color: ZendColors.positive,
        dot: true,
      );
    }
    if (_counterpartyOnline == false && _counterpartyLastSeen != null) {
      return _PresenceLabel(
        text: 'last seen ${_formatLastSeen(_counterpartyLastSeen!)}',
        color: zt.textSecondary,
        dot: false,
      );
    }
    // Fallback: show zendtag + streak
    return Builder(builder: (ctx) {
      final model = ZendScope.of(ctx);
      final streak = model.activeStreaks[cp.userId];
      return Row(
        children: [
          Text('@${cp.zendtag}',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary)),
          if (streak != null && streak.isActive)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('🔥 ${streak.streakWeeks}w', style: const TextStyle(fontSize: 11)),
            ),
        ],
      );
    });
  }

  // ── E2EE helpers ────────────────────────────────────────────────────────────

  /// Encrypts [plaintext] for sending. Returns the `e2ee:…` wire string,
  /// or the original plaintext if E2EE is not ready (counterparty has no pubkey).
  Future<String> _encryptForSend(String plaintext) async {
    if (!_e2eeReady) return plaintext;
    final model = ZendScope.of(context);
    final cached = WalletSessionCache.instance.keypair;
    if (cached == null) return plaintext;
    // Extract 32-byte seed from cached keypair bytes
    final seed = cached.length >= 32 ? cached.sublist(0, 32) : cached;
    final encrypted = await model.e2eeService.encrypt(
      plaintext: plaintext,
      mySeed32: seed,
      counterpartyPubkeyB58: _counterpartyPubkey!,
      roomId: widget.roomId,
    );
    return encrypted ?? plaintext;
  }

  /// Decrypts [content] if it starts with `e2ee:`. Returns the plaintext,
  /// or null if decryption fails. Returns the original string if not encrypted.
  Future<String?> _decryptIfNeeded(String? content) async {
    if (content == null) return null;
    if (!content.startsWith('e2ee:')) return content;
    // Need seed — try session cache first, then fall back to null
    final cached = WalletSessionCache.instance.keypair;
    if (cached == null) return '🔒 (unlock to decrypt)';
    final seed = cached.length >= 32 ? cached.sublist(0, 32) : cached;
    final model = ZendScope.of(context);
    // For decryption we need the other party's pubkey — could be sender or recipient
    final pubkey = _counterpartyPubkey;
    if (pubkey == null) return '🔒 (key unavailable)';
    final decrypted = await model.e2eeService.decrypt(
      wireContent: content,
      mySeed32: seed,
      counterpartyPubkeyB58: pubkey,
      roomId: widget.roomId,
    );
    return decrypted ?? '🔒 (decryption failed)';
  }

  /// Applies E2EE decryption in-place on a loaded message list.
  Future<void> _decryptMessages(List<DmMessage> messages) async {
    for (final msg in messages) {
      if (msg.content != null && msg.content!.startsWith('e2ee:')) {
        final decrypted = await _decryptIfNeeded(msg.content);
        msg.content = decrypted ?? msg.content;
        msg.isEncrypted = true;
      }
    }
  }

  // ── Reply scroll-to-original ─────────────────────────────────────────────────
  //
  // When the user taps a quote block inside a bubble, scroll to the original
  // message. We match by content + sender because we don't store the original
  // message ID in the metadata yet. If the message is off-screen we scroll to
  // it and flash the bubble to confirm.

  // Keys for each message row — used by _scrollToReplyOrigin to find and
  // flash-highlight the original message without estimating pixel offsets.
  final _msgItemKeys = <String, GlobalKey>{};
  String? _flashingMsgId;

  void _scrollToReplyOrigin(DmMessage replyMsg) {
    final replyContent = replyMsg.replyToContent;
    final replySender = replyMsg.replyToSenderZendtag;
    final replyMsgId = replyMsg.replyToMessageId;

    int idx = -1;

    // Prefer ID-based lookup (exact, works for all message types including
    // payment/vibe which have null content)
    if (replyMsgId != null) {
      idx = _messages.indexWhere((m) => m.id == replyMsgId);
    }

    // Fallback: content+sender match for messages sent before ID tracking
    if (idx == -1 && replyContent != null) {
      idx = _messages.indexWhere((m) =>
          m.content == replyContent &&
          (replySender == null || m.senderZendtag == replySender));
    }

    if (idx == -1) return;

    final targetId = _messages[idx].id;
    final key = _msgItemKeys[targetId];
    if (key?.currentContext == null) return;

    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: 0.3,
    ).then((_) {
      if (mounted) {
        setState(() => _flashingMsgId = targetId);
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) setState(() => _flashingMsgId = null);
        });
      }
    });
  }

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}';
  }

  Widget _buildScrollToBottomButton(ZendTheme zt) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      bottom: _showScrollToBottom ? 8 : -48,
      right: 12,
      child: AnimatedOpacity(
        opacity: _showScrollToBottom ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 180),
        child: GestureDetector(
          onTap: () => _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              shape: BoxShape.circle,
              border: Border.all(color: zt.border),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Icon(SolarIconsBold.altArrowDown, size: 18, color: zt.textSecondary),
          ),
        ),
      ),
    );
  }

  void _showMessageReactions(BuildContext ctx, DmMessage msg, Offset globalPos) {
    const emojis = ['🔥', '❤️', '😂', '👏', '🙏', '😭', '💸', '✅', '👑', '🚀', '💯', '👀'];
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    // Position the tray just above or below the tap point
    final trayHeight = 56.0;
    final trayWidth = screenWidth - 32;
    double top = globalPos.dy - trayHeight - 12;
    if (top < 80) top = globalPos.dy + 20; // flip below if near top
    top = top.clamp(80.0, screenHeight - trayHeight - 80);

    // Find the message index so we can update its reactions in place
    final msgIdx = _messages.indexWhere((m) => m.id == msg.id);

    entry = OverlayEntry(builder: (overlayCtx) => Stack(children: [
      Positioned.fill(child: GestureDetector(
        onTap: () => entry.remove(),
        behavior: HitTestBehavior.opaque,
        child: const ColoredBox(color: Color(0x22000000)),
      )),
      Positioned(
        top: top,
        left: 16,
        width: trayWidth,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: zt.bgElevated,
              borderRadius: BorderRadius.circular(ZendRadii.pill),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: emojis.take(8).map((e) {
                // Check if the current user already reacted with this emoji
                final alreadyReacted = msgIdx != -1
                    ? _messages[msgIdx].reactions.any((r) => r.emoji == e && r.reactedByMe)
                    : false;

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    entry.remove();

                    if (msgIdx == -1) return;
                    final targetMsg = _messages[msgIdx];

                    if (alreadyReacted) {
                      // Toggle off — remove the reaction optimistically
                      setState(() {
                        final updatedReactions = targetMsg.reactions
                            .map((r) {
                              if (r.emoji != e) return r;
                              if (r.count <= 1) return null; // remove entirely
                              return r.copyWith(count: r.count - 1, reactedByMe: false);
                            })
                            .whereType<DmReaction>()
                            .toList();
                        _messages[msgIdx].reactions = updatedReactions;
                      });
                      unawaited(model.dmService.removeMessageReaction(
                        widget.roomId,
                        messageId: targetMsg.id,
                        emoji: e,
                      ));
                    } else {
                      // Add the reaction optimistically
                      setState(() {
                        final existing = targetMsg.reactions.indexWhere((r) => r.emoji == e);
                        final updated = List<DmReaction>.from(targetMsg.reactions);
                        if (existing != -1) {
                          updated[existing] = updated[existing].copyWith(
                            count: updated[existing].count + 1,
                            reactedByMe: true,
                          );
                        } else {
                          updated.add(DmReaction(emoji: e, count: 1, reactedByMe: true));
                        }
                        _messages[msgIdx].reactions = updated;
                      });
                      // The persisted endpoint broadcasts to the other
                      // connected participant; this client already updated
                      // its own reaction optimistically.
                      unawaited(model.dmService.sendMessageReaction(
                        widget.roomId,
                        messageId: targetMsg.id,
                        emoji: e,
                      ));
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                    decoration: alreadyReacted
                        ? BoxDecoration(
                            color: zt.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(ZendRadii.pill),
                          )
                        : null,
                    child: Text(
                      e,
                      style: TextStyle(
                        fontSize: alreadyReacted ? 24 : 26,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    ]));
    overlay.insert(entry);

    // Also handle incoming reaction frames from the WS while the tray is open
    // (these arrive in _wsSub listener in _initWs)
  }

  void _onToggleReaction(DmMessage msg, String emoji) {
    final msgIdx = _messages.indexWhere((m) => m.id == msg.id);
    if (msgIdx == -1) return;
    final model = ZendScope.of(context);
    final targetMsg = _messages[msgIdx];
    final alreadyReacted = targetMsg.reactions.any((r) => r.emoji == emoji && r.reactedByMe);

    HapticFeedback.selectionClick();
    if (alreadyReacted) {
      setState(() {
        final updated = targetMsg.reactions
            .map((r) {
              if (r.emoji != emoji) return r;
              if (r.count <= 1) return null;
              return r.copyWith(count: r.count - 1, reactedByMe: false);
            })
            .whereType<DmReaction>()
            .toList();
        _messages[msgIdx].reactions = updated;
      });
      unawaited(model.dmService.removeMessageReaction(widget.roomId, messageId: targetMsg.id, emoji: emoji));
    } else {
      setState(() {
        final existing = targetMsg.reactions.indexWhere((r) => r.emoji == emoji);
        final updated = List<DmReaction>.from(targetMsg.reactions);
        if (existing != -1) {
          updated[existing] = updated[existing].copyWith(count: updated[existing].count + 1, reactedByMe: true);
        } else {
          updated.add(DmReaction(emoji: emoji, count: 1, reactedByMe: true));
        }
        _messages[msgIdx].reactions = updated;
      });
      unawaited(model.dmService.sendMessageReaction(widget.roomId, messageId: targetMsg.id, emoji: emoji));
    }
  }

  void _onRetry(String clientId) {
    final idx = _messages.indexWhere((m) => m.clientId == clientId);
    if (idx == -1) return;
    final msg = _messages[idx];
    if (msg.content == null) return;
    setState(() => _messages[idx].localStatus = DmLocalStatus.sending);
    _ws.sendMessage(clientId, msg.content!);
  }

  void _onRequestPayment() {
    _showRequestAmountSheet();
  }

  void _showRequestAmountSheet() {
    final zt = ZendTheme.of(context);
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? errorMsg;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.92),
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 14),
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(ZendRadii.pill)))),
                const SizedBox(height: 16),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      ZendAvatar(radius: 18, photoUrl: widget.counterparty.avatarUrl, initials: widget.counterparty.initialLetter),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Request from', style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary)),
                          Text('@${widget.counterparty.zendtag}', style: TextStyle(fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700, color: zt.textPrimary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Amount display — large like QR sheet
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () {},
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('\$', style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 32, color: zt.textSecondary, fontStyle: FontStyle.italic)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: TextField(
                                controller: amountCtrl,
                                autofocus: true,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 48, fontStyle: FontStyle.italic, color: zt.textPrimary, height: 1),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  hintStyle: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 48, fontStyle: FontStyle.italic, color: zt.textSecondary.withValues(alpha: 0.4)),
                                  border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (_) => setModalState(() => errorMsg = null),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (errorMsg != null)
                        Text(errorMsg!, style: const TextStyle(fontFamily: 'DMSans', fontSize: 12, color: ZendColors.destructive)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Note field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: noteCtrl,
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Add a note…',
                      hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary.withValues(alpha: 0.5)),
                      filled: true, fillColor: zt.bgPrimary,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZendRadii.lg), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                // Confirm button — always visible above the keyboard.
                // When the keyboard is up, we push the button up by the
                // keyboard height (bottomInset). When it's down, we use
                // the device's bottom safe-area inset + a comfortable 20px
                // margin so the button never sits flush with the home bar.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    bottomInset > 0
                        ? bottomInset + 8
                        : MediaQuery.of(ctx).viewPadding.bottom + 20,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final parsed = double.tryParse(amountCtrl.text.trim());
                        if (parsed == null || parsed < 0.01) {
                          setModalState(() => errorMsg = 'Enter a valid amount');
                          return;
                        }
                        Navigator.pop(ctx);
                        _sendPaymentRequest(parsed, noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.lg)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Send request', style: TextStyle(fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    ).then((_) {
      amountCtrl.dispose();
      noteCtrl.dispose();
    });
  }

  void _sendPaymentRequest(double amount, String? note) {
    final model = ZendScope.of(context);
    final clientId = const Uuid().v4();
    final myZendtag = model.currentZendtag ?? '';
    if (model.dmService.isRoomCleared(widget.roomId)) {
      model.dmService.unmarkCleared(widget.roomId);
    }

    // Optimistic message
    final optimistic = DmMessage(
      id: 'local-$clientId',
      roomId: widget.roomId,
      senderUserId: model.currentUserId ?? '',
      senderZendtag: myZendtag,
      type: DmMessageType.paymentRequest,
      paymentRequestData: DmPaymentRequestData(
        amountUsdc: amount.toStringAsFixed(6),
        requesterZendtag: myZendtag,
        note: note,
        status: 'pending',
      ),
      clientId: clientId,
      createdAt: DateTime.now(),
      localStatus: DmLocalStatus.sending,
    );
    setState(() => _messages.insert(0, optimistic));
    HapticFeedback.lightImpact();

    // Send to server
    model.dmService.sendPaymentRequest(
      widget.roomId,
      amountUsdc: amount,
      requesterZendtag: myZendtag,
      note: note,
      clientId: clientId,
    ).then((_) {
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.clientId == clientId);
          if (i != -1) _messages[i].localStatus = DmLocalStatus.delivered;
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.clientId == clientId);
          if (i != -1) _messages[i].localStatus = DmLocalStatus.failed;
        });
      }
    });
  }

  void _onPayRequest(DmPaymentRequestData rd) {
    // Recipient taps Pay → open QR payment sheet pre-filled with amount
    final amount = double.tryParse(rd.amountUsdc) ?? 0.0;
    showQrPaymentSheet(
      context,
      intent: QrPaymentIntent(
        zendtag: rd.requesterZendtag,
        amountUsdc: amount,
      ),
    );
  }

  void _onPayRecipient() {
    // Pay this counterparty directly
    showQrPaymentSheet(
      context,
      intent: QrPaymentIntent(zendtag: widget.counterparty.zendtag),
    );
  }

  PopupMenuItem<_ChatMenuAction> _popupItem(
    BuildContext ctx,
    ZendTheme zt,
    _ChatMenuAction action,
    IconData icon,
    String label, {
    bool disabled = false,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? ZendColors.destructive : zt.textPrimary;
    return PopupMenuItem<_ChatMenuAction>(
      value: action,
      enabled: !disabled,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, ZendTheme zt, DmCounterparty cp, _ChatMenuAction action) {
    switch (action) {
      case _ChatMenuAction.viewContact:
        pushZendSlide(context, UserProfileScreen(zendtag: cp.zendtag));
      case _ChatMenuAction.searchInChat:
        break; // coming soon
      case _ChatMenuAction.disappearing:
        break; // coming soon
      case _ChatMenuAction.clearChat:
        setState(() => _messages.clear());
        ZendScope.of(context).dmService.clearRoomCache(widget.roomId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Chat cleared', style: TextStyle(fontFamily: 'DMSans')), backgroundColor: zt.bgSecondary),
        );
      case _ChatMenuAction.block:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Block feature coming soon', style: TextStyle(fontFamily: 'DMSans')), backgroundColor: zt.bgSecondary),
        );
    }
  }

  Future<void> _onSendVibe(VibeSendResult vibe) async {
    final model = ZendScope.of(context);
    final clientId = const Uuid().v4();

    // 1. Show the optimistic sticker immediately — amount hidden, feels like
    //    sending a sticker. The DmLocalStatus.sending state is invisible to
    //    the user (no spinner shown on vibes — it just pops in).
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
    HapticFeedback.mediumImpact();

    // 2. Everything below happens silently in the background.
    //    The sticker is already visible — the user has moved on.
    try {
      // Step A: prepare — get blockhash + ATAs
      final prepareData = await model.dmService.prepareVibe(
        widget.roomId,
        stickerId: vibe.stickerId,
        amountUsdc: vibe.amountUsdc,
      );

      // Step B: sign the USDC transfer transaction locally
      final blockhash = prepareData['blockhash'] as String;
      final recipientAddress = prepareData['recipient_wallet_address'] as String;
      final feePayerAddress = prepareData['fee_payer'] as String;
      final senderAta = prepareData['sender_ata'] as String?;
      final recipientAta = prepareData['recipient_ata'] as String?;

      final String signedTx;

      // Resolve a signing credential — uses the session cache when policy
      // allows it, otherwise prompts for PIN (never silently fails just
      // because the cache is empty; see zendapp-hardening Req 1.2).
      if (!mounted) return;
      final keypair = await resolveVibeSigningKeypair(context, vibe.amountUsdc);
      if (keypair == null) {
        // User cancelled the PIN prompt — treat as a failed send.
        throw Exception('Vibe cancelled');
      }
      signedTx = await model.walletService.buildAndSignTransactionFromCache(
        keypairBytes: keypair,
        amountUsdc: vibe.amountUsdc,
        recipientAddress: recipientAddress,
        blockhash: blockhash,
        feePayerAddress: feePayerAddress,
        senderAtaOverride: senderAta,
        recipientAtaOverride: recipientAta,
      );
      for (var i = 0; i < keypair.length; i++) { keypair[i] = 0; }

      // Step C: submit the signed transaction
      await model.dmService.submitVibe(
        widget.roomId,
        stickerId: vibe.stickerId,
        amountUsdc: vibe.amountUsdc,
        partiallySignedTx: signedTx,
        clientId: clientId,
      );

      // Silent success — upgrade optimistic bubble to delivered
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.clientId == clientId);
          if (i != -1) _messages[i].localStatus = DmLocalStatus.delivered;
        });
        // Record spend locally + schedule balance refresh after chain confirmation
        unawaited(model.recordVibeSpend(vibe.amountUsdc));
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) model.fetchBalance();
        });
      }
    } catch (_) {
      // Silently mark as failed — a small retry indicator appears on the bubble.
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
    _recordingClearTimer?.cancel();
    super.dispose();
  }

  bool _isContinuation(int index) {
    if (index >= _messages.length - 1) return false;
    final current = _messages[index];
    final next = _messages[index + 1]; // older message (list is reversed)
    if (current.senderUserId != next.senderUserId) return false;
    return current.createdAt.difference(next.createdAt).inMinutes.abs() < 5;
  }

  /// Whether the message at [index] is the FIRST (topmost) in its sender run.
  /// In the reversed list, the message before (index - 1) is newer.
  bool _isFirstInGroup(int index) {
    if (index == 0) return true; // newest message = always starts a group visually
    final current = _messages[index];
    final newer = _messages[index - 1];
    if (current.senderUserId != newer.senderUserId) return true;
    return current.createdAt.difference(newer.createdAt).inMinutes.abs() >= 5;
  }

  /// Whether the message at [index] is the LAST (bottommost) in its sender run.
  /// The last bubble gets the tail and (for received) shows the avatar.
  bool _isLastInGroup(int index) {
    if (index >= _messages.length - 1) return true;
    final current = _messages[index];
    final older = _messages[index + 1];
    if (current.senderUserId != older.senderUserId) return true;
    return current.createdAt.difference(older.createdAt).inMinutes.abs() >= 5;
  }

  // ── Display list (message items + date separators) ────────────────────────
  //
  // Mirrors the mission room pattern: iterate oldest→newest, insert a date
  // separator whenever the day changes, label with that day. The resulting
  // list is reversed so the newest item is at index 0, matching the reversed
  // ListView — exactly the same order as _messages but with separator items
  // interspersed.

  List<_DmDisplayItem> _buildDisplayList() {
    if (_messages.isEmpty) return const [];

    // _messages is newest-first. Iterate oldest-first to build chronologically.
    final chronological = _messages.reversed.toList();
    final items = <_DmDisplayItem>[];
    DateTime? lastDay;

    for (final msg in chronological) {
      final day = DateTime(msg.createdAt.year, msg.createdAt.month, msg.createdAt.day);
      if (lastDay == null || day != lastDay) {
        items.add(_DmSeparatorItem(date: day));
        lastDay = day;
      }
      items.add(_DmMessageItem(message: msg));
    }

    // Reverse so newest is at index 0 — matches the reversed ListView
    return items.reversed.toList();
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
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary, size: 26),
                  ),
                  GestureDetector(
                    onTap: () => pushZendSlide(context, UserProfileScreen(zendtag: cp.zendtag)),
                    child: ZendAvatar(
                      radius: 20,
                      photoUrl: cp.avatarUrl,
                      initials: cp.initialLetter,
                      isOnline: _counterpartyOnline,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => pushZendSlide(context, UserProfileScreen(zendtag: cp.zendtag)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  cp.displayName.trim().isEmpty ? '@${cp.zendtag}' : cp.displayName,
                                  style: TextStyle(fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700, color: zt.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_e2eeReady) ...[
                                const SizedBox(width: 5),
                                Icon(SolarIconsBold.lockPassword, size: 13, color: ZendColors.positive),
                              ],
                            ],
                          ),
                          // ── Presence / status row ─────────────────────
                          _buildPresenceSubtitle(zt, cp),
                        ],
                      ),
                    ),
                  ),
                  // ── Overflow menu ─────────────────────────────────────
                  PopupMenuButton<_ChatMenuAction>(
                    icon: Icon(SolarIconsBold.menuDots, color: zt.textSecondary, size: 24),
                    color: zt.bgSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.xl)),
                    elevation: 1,
                    shadowColor: Colors.black.withValues(alpha: 0.08),
                    popUpAnimationStyle: AnimationStyle.noAnimation,
                    onSelected: (action) => _handleMenuAction(context, zt, cp, action),
                    itemBuilder: (ctx) => [
                      _popupItem(ctx, zt, _ChatMenuAction.viewContact, SolarIconsBold.user, 'View contact'),
                      _popupItem(ctx, zt, _ChatMenuAction.searchInChat, SolarIconsBold.magnifier, 'Search in chat', disabled: true),
                      _popupItem(ctx, zt, _ChatMenuAction.disappearing, SolarIconsBold.clockCircle, 'Disappearing messages', disabled: true),
                      _popupItem(ctx, zt, _ChatMenuAction.clearChat, SolarIconsBold.trashBinMinimalistic, 'Clear chat'),
                      const PopupMenuDivider(),
                      _popupItem(ctx, zt, _ChatMenuAction.block, SolarIconsBold.userBlock, 'Block @${cp.zendtag}', isDestructive: true),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: zt.border),

            // ── Messages + scroll-to-bottom ───────────────────────────────
            Expanded(
              child: GestureDetector(
                // Swipe left from right edge → reveal timestamps (iMessage style)
                onHorizontalDragUpdate: (details) {
                  if (details.delta.dx < -3) {
                    if (!_showTimestamps) setState(() => _showTimestamps = true);
                  }
                },
                onHorizontalDragEnd: (_) {
                  if (_showTimestamps) setState(() => _showTimestamps = false);
                },
                onHorizontalDragCancel: () {
                  if (_showTimestamps) setState(() => _showTimestamps = false);
                },
                child: Stack(
                children: [
                  _loading
                      ? const DmThreadSkeleton()
                      : Builder(builder: (ctx) {
                          final displayList = _buildDisplayList();
                          final typingOffset = _theyAreTyping ? 1 : 0;
                          final moreOffset  = _loadingMore ? 1 : 0;
                          final totalCount  = displayList.length + typingOffset + moreOffset;

                          return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          itemCount: totalCount,
                          itemBuilder: (ctx, i) {
                            // "Load more" spinner at the very end (oldest)
                            if (_loadingMore && i == displayList.length + typingOffset) {
                              return const Padding(
                                padding: EdgeInsets.all(8),
                                child: Center(child: ZendLoader(size: 18)),
                              );
                            }
                            // Typing indicator at the very start (newest)
                            if (_theyAreTyping && i == 0) {
                              return _TypingIndicator(avatarUrl: cp.avatarUrl, initial: cp.initialLetter);
                            }
                            final listIdx = i - typingOffset;
                            final item = displayList[listIdx];

                            // Date separator
                            if (item is _DmSeparatorItem) {
                              return _DateSeparator(date: item.date);
                            }

                            final msgItem = item as _DmMessageItem;
                            final msg = msgItem.message;

                            // Stable per-message key for scroll-to-reply
                            final itemKey = _msgItemKeys.putIfAbsent(
                              msg.id,
                              () => GlobalKey(),
                            );

                            // Map back to _messages index for grouping helpers
                            final msgIdx = _messages.indexWhere((m) => m.id == msg.id || (m.clientId != null && m.clientId == msg.clientId));

                            final isMe = msg.senderUserId == model.currentUserId;
                            final isCont = msgIdx >= 0 ? _isContinuation(msgIdx) : false;
                            final isFirst = msgIdx >= 0 ? _isFirstInGroup(msgIdx) : true;
                            final isLast  = msgIdx >= 0 ? _isLastInGroup(msgIdx) : true;
                            final isGroupEnd = !isMe && isFirst;
                            final isFlashing = _flashingMsgId == msg.id;

                            Widget bubbleRow = Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Avatar slot — only shown on group-end for incoming.
                                // Fixed 26×26 so the circle never stretches to an oval.
                                if (!isMe) SizedBox(
                                  width: 32,
                                  height: 26,
                                  child: isGroupEnd
                                      ? Align(
                                          alignment: Alignment.bottomCenter,
                                          child: ZendAvatar(radius: 13, photoUrl: cp.avatarUrl, initials: cp.initialLetter),
                                        )
                                      : null,
                                ),
                                Expanded(
                                  child: DmMessageBubble(
                                    message: msg,
                                    isMe: isMe,
                                    isContinuation: isCont,
                                    isFirst: isFirst,
                                    isLast: isLast,
                                    showTimestamp: _showTimestamps,
                                    onReply: (m) => setState(() => _replyingTo = m),
                                    onReplyTap: (m) => _scrollToReplyOrigin(m),
                                    onRetry: msg.localStatus == DmLocalStatus.failed
                                        ? () => _onRetry(msg.clientId ?? '')
                                        : null,
                                    onPayRequest: _onPayRequest,
                                    onLongPress: _showMessageReactions,
                                    onReactionTap: _onToggleReaction,
                                  ),
                                ),
                              ],
                            );

                            // Flash highlight — AnimatedContainer tint that
                            // fades in and out when tapping a reply to jump
                            // back to the original message.
                            return _FlashHighlight(
                              key: itemKey,
                              isFlashing: isFlashing,
                              child: bubbleRow,
                            );
                          },
                        );
                        }),
                  // ── Scroll-to-bottom button ─────────────────────────────
                  _buildScrollToBottomButton(zt),
                ],
              ),  // close Stack
              ),  // close GestureDetector child
            ),  // close Expanded

            // Reply strip - shown when user swipes right on a message
            if (_replyingTo != null)
              _ReplyStrip(
                message: _replyingTo!,
                currentUserId: model.currentUserId ?? '',
                onCancel: () => setState(() => _replyingTo = null),
              ),

            // ── Input ─────────────────────────────────────────────────────
            DmInputBar(
              onSend: (text) {
                if (_replyingTo != null) {
                  final quoted = _replyingTo!;
                  setState(() => _replyingTo = null);
                  // Send with structured reply context — not a text prefix.
                  // The optimistic message carries replyToContent/replyToSenderZendtag
                  // so the bubble renders a proper quote block immediately.
                  _onSendWithReply(text, quoted);
                } else {
                  _onSend(text);
                }
              },
              onTyping: (v) => _ws.sendTyping(v),
              roomId: widget.roomId,
              onSendVibe: _onSendVibe,
              onRequestPayment: _onRequestPayment,
              onPayRecipient: _onPayRecipient,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Presence label ────────────────────────────────────────────────────────────

class _PresenceLabel extends StatelessWidget {
  const _PresenceLabel({required this.text, required this.color, required this.dot});
  final String text;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Chat menu ─────────────────────────────────────────────────────────────────

enum _ChatMenuAction { viewContact, searchInChat, disappearing, clearChat, block }

// ── Display list item types ───────────────────────────────────────────────────

sealed class _DmDisplayItem {}

class _DmMessageItem extends _DmDisplayItem {
  _DmMessageItem({required this.message});
  final DmMessage message;
}

class _DmSeparatorItem extends _DmDisplayItem {
  _DmSeparatorItem({required this.date});
  final DateTime date;
}

// ── Reply strip ───────────────────────────────────────────────────────────────

class _ReplyStrip extends StatelessWidget {
  const _ReplyStrip({
    required this.message,
    required this.currentUserId,
    required this.onCancel,
  });

  final DmMessage message;
  final String currentUserId;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final isMe = message.senderUserId == currentUserId;

    // Icon + preview text per message type
    final (IconData typeIcon, String preview) = switch (message.type) {
      DmMessageType.payment        => (SolarIconsBold.transferHorizontal, '💸 Payment'),
      DmMessageType.vibe           => (SolarIconsBold.star,              '✨ Vibe'),
      DmMessageType.paymentRequest => (SolarIconsBold.bill,               '↙ Payment request'),
      _                            => (SolarIconsBold.chatRound,          message.displayContent ?? ''),
    };
    final previewShort = preview.length > 60
        ? '${preview.substring(0, 60)}…'
        : preview;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hairline separator above the strip
        Divider(height: 1, color: zt.border.withValues(alpha: 0.6)),
        Container(
          color: zt.bgSecondary,
          padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Accent pill bar
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  color: zt.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // "Replying to @zendtag" header
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(SolarIconsBold.reply, size: 11, color: zt.accent),
                        const SizedBox(width: 4),
                        Text(
                          isMe
                              ? 'Replying to yourself'
                              : 'Replying to @${message.senderZendtag ?? '…'}',
                          style: TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 11,
                            color: zt.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Preview row with type icon
                    Row(
                      children: [
                        Icon(typeIcon, size: 12, color: zt.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            previewShort,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 13,
                              color: zt.textSecondary,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Cancel button
              IconButton(
                onPressed: onCancel,
                icon: Icon(SolarIconsBold.closeCircle, size: 18, color: zt.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Flash highlight — animates a subtle tint on the message when the user
// taps a reply quote to jump back to the original ────────────────────────────

class _FlashHighlight extends StatefulWidget {
  const _FlashHighlight({
    super.key,
    required this.isFlashing,
    required this.child,
  });

  final bool isFlashing;
  final Widget child;

  @override
  State<_FlashHighlight> createState() => _FlashHighlightState();
}

class _FlashHighlightState extends State<_FlashHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _opacity = TweenSequence([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_ctrl);
  }

  @override
  void didUpdateWidget(_FlashHighlight old) {
    super.didUpdateWidget(old);
    if (widget.isFlashing && !old.isFlashing) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (ctx, child) => ColoredBox(
        color: ZendTheme.of(ctx).accent.withValues(alpha: _opacity.value * 0.18),
        child: child,
      ),
      child: widget.child,
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

// ── Date separator ─────────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});
  final DateTime date;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (date.year == now.year) return '${months[date.month - 1]} ${date.day}';
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: zt.border.withValues(alpha: 0.5))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label(),
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 11,
                color: zt.textSecondary.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(child: Divider(color: zt.border.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}
