import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
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
import '../../services/e2ee_service.dart' show kE2eePrefix;
import '../../services/push_notification_service.dart';
import '../../services/wallet_session_cache.dart';
import '../../models/qr_payment_intent.dart';
import '../profile/user_profile_screen.dart';
import '../send/qr_payment_sheet.dart';
import '../vibes/vibe_picker_sheet.dart';
import '../vibes/vibe_pin_prompt.dart';
import 'dm_message_bubble.dart';
import 'dm_input_bar.dart';
import 'dm_message_action_overlay.dart';
import 'dm_forward_sheet.dart';
import 'dm_message_info_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// State of the E2EE key exchange for the currently open room.
enum _E2eeStatus {
  /// Key exchange (publish mine, fetch theirs) is in flight.
  resolving,
  /// Counterparty pubkey is available — messages are encrypted.
  ready,
  /// Key exchange finished but the counterparty has no pubkey on file
  /// (old app version, or never unlocked since E2EE shipped). Messages
  /// send as plaintext by necessity, and the UI marks them as such.
  unavailable,
}

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
  bool _loadError = false;
  bool _theyAreTyping = false;
  bool _theyAreRecording = false;  // "recording audio..." indicator
  // WS connection banner state — mirrors mission_room.dart's pattern.
  // Previously the DM thread never surfaced any of this even though
  // PoolWebSocketService (which DmWebSocketService wraps) already exposes
  // a connectionState notifier: a WS that silently dropped and started
  // backing off gave the user zero indication that live delivery had
  // stopped, and after 5 consecutive failures it stops retrying entirely
  // until the next app resume — with nothing telling the user why messages
  // stopped arriving.
  bool _hasConnectedOnce = false;
  bool _showReconnecting = false;
  // Counterparty presence
  bool? _counterpartyOnline;        // null = unknown, true = online, false = offline
  DateTime? _counterpartyLastSeen;  // null = hidden by privacy setting
  // E2EE
  String? _counterpartyPubkey;      // counterparty's Ed25519 pubkey (base58)
  _E2eeStatus _e2eeStatus = _E2eeStatus.resolving;
  bool get _e2eeReady => _e2eeStatus == _E2eeStatus.ready;
  /// Completes once key exchange has settled (ready OR confirmed unavailable —
  /// never left pending). [_onSend]/[_onSendWithReply] await this (with a
  /// bound) before encrypting, so the very first messages in a new chat wait
  /// for the exchange instead of racing it and silently sending plaintext.
  final Completer<void> _e2eeResolution = Completer<void>();
  Timer? _typingClearTimer;
  Timer? _recordingClearTimer;
  String? _nextCursor;
  bool _loadingMore = false;
  bool _showScrollToBottom = false;
  // Count of counterparty messages that arrived while the user was scrolled
  // away from the bottom. Previously the scroll-to-bottom button was purely
  // scroll-position-driven — it gave zero indication that new content had
  // actually arrived below versus just "you happen to be scrolled up",
  // unlike most chat apps' "N new messages ↓" badge. Reset to 0 whenever
  // the user scrolls back near the bottom or taps the button.
  int _unseenWhileScrolledUp = 0;
  bool _showTimestamps = false;      // revealed by left-edge swipe
  DmMessage? _replyingTo;           // the message being replied to

  // Tracks clientIds for which we have already received the WS echo frame
  // (our own message echoed back by the server). This is recorded
  // synchronously as soon as the echo frame arrives -- BEFORE any async
  // decryption -- so the delayed HTTP fallback can check it and skip the
  // redundant HTTP send even when the decrypt hasn't finished yet.
  final Set<String> _wsEchoReceived = {};

  // Index-based scroll control (scrollable_positioned_list) instead of a
  // plain ScrollController — this is what lets _scrollToReplyOrigin jump
  // straight to a target index even when that message is far outside the
  // currently-built/visible region. A plain ListView.builder only builds
  // items near the viewport, so a GlobalKey-based Scrollable.ensureVisible
  // approach silently no-ops for any reply whose original message isn't
  // already mounted — exactly the "doesn't scroll when it's far away" bug.
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // One-shot read — ZendScope.of() throws in debug builds when called
    // before initState() completes.
    // Seed with cached messages immediately — no spinner for known rooms
    final model = ZendScope.read(context);
    // Route-aware push-notification suppression: while this thread is open,
    // don't pop a local/foreground notification for messages arriving in
    // this exact room — see PushNotificationService._listenForForegroundMessages.
    PushNotificationService.activeDmRoomId = widget.roomId;
    final cached = model.dmService.getCachedMessages(widget.roomId);
    if (cached.isNotEmpty) {
      _messages.addAll(cached);
      _loading = false;
    }
    _initWs();
    _loadMessages();
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
    _fetchCounterpartyPubkey();
  }

  Future<void> _fetchCounterpartyPubkey() async {
    final model = ZendScope.of(context);

    try {
      // Publish our key before checking the other user. The former ordering
      // only registered a key after a counterparty already had one, so two
      // newly upgraded users could never bootstrap E2EE. In the common case
      // this is a no-op network-wise: bootstrapE2ee() already ran at unlock,
      // and E2eeService.registerPubkey() short-circuits once registered.
      final walletAddress = await model.walletService.getWalletAddress();
      if (walletAddress != null) {
        await model.e2eeService.registerPubkey(walletAddress);
      }

      final pubkey = await model.e2eeService.fetchCounterpartyPubkey(
        widget.counterparty.userId,
      );
      if (!mounted) return;
      setState(() {
        _counterpartyPubkey = pubkey;
        _e2eeStatus = pubkey != null ? _E2eeStatus.ready : _E2eeStatus.unavailable;
      });
      // _loadMessages() may have already finished (or the room may have been
      // seeded from cache in initState) before the counterparty key arrived —
      // in that case any e2ee: messages were left as raw ciphertext because
      // _e2eeReady was false at load time. Decrypt the currently-held list now
      // that the key is available so we never display ciphertext to the user.
      await _decryptMessages(_messages);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _e2eeStatus = _E2eeStatus.unavailable);
    } finally {
      if (!_e2eeResolution.isCompleted) _e2eeResolution.complete();
    }
  }

  /// Waits for the E2EE key exchange to settle before sending, so the first
  /// message(s) of a new chat don't race the exchange and silently fall back
  /// to plaintext. Bounded so a slow/failed network call never blocks sending
  /// indefinitely — after the timeout we proceed with whatever state we have
  /// (ready or unavailable), matching [_encryptForSend]'s existing fallback.
  Future<void> _awaitE2eeResolution() {
    return _e2eeResolution.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () {},
    );
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
    _ws.connectionState.addListener(_onConnectionStateChanged);
    _ws.connect();

    _wsSub = _ws.frames.listen((frame) {
      if (!mounted) return;
      switch (frame.type) {
        case WsFrameType.message:
          final msg = DmMessage.fromJson(frame.data);
          // Defensively clear the typing indicator when the counterparty's
          // message actually arrives. The server sends "typing: false" and
          // "message" as two separate frames — if the "stopped typing"
          // frame is delayed or dropped relative to the message itself
          // (plausible under any latency jitter), the indicator would
          // otherwise sit there next to the now-delivered message until
          // its 4s auto-clear timeout expires.
          if (msg.senderUserId != model.currentUserId && _theyAreTyping) {
            _typingClearTimer?.cancel();
            setState(() => _theyAreTyping = false);
          }
          // If the counterparty's message arrives while the user is
          // scrolled away from the bottom, bump the unseen counter so the
          // scroll-to-bottom button can surface it as a "N new" badge
          // instead of leaving the user unaware anything new landed.
          if (msg.senderUserId != model.currentUserId && _showScrollToBottom) {
            _unseenWhileScrolledUp++;
          }
          // Track the echo synchronously BEFORE any async decrypt work so
          // the HTTP fallback timer can see it immediately and skip the
          // redundant send. Only record for our own messages (echoes).
          if (msg.senderUserId == model.currentUserId && msg.clientId != null) {
            _wsEchoReceived.add(msg.clientId!);
          }
          // Decrypt E2EE content inline before displaying
          if (msg.content != null && msg.content!.startsWith('e2ee:')) {
            _decryptIfNeeded(msg.content).then((plain) {
              if (!mounted) return;
              msg.content = plain ?? msg.content;
              msg.isEncrypted = true;
              setState(() {
                // Remove any prior copy of this exact message — matching on
                // EITHER clientId (covers our own optimistic message being
                // replaced by its server-confirmed echo) OR server id
                // (covers this same message having already been inserted
                // by a REST fetch — e.g. _loadMessages() resolving around
                // the same time a WS frame for it arrives on first open of
                // a thread). Matching on clientId alone missed the second
                // case, since an incoming message from the counterparty
                // has no clientId that matches anything we generated,
                // producing a visible duplicate bubble until the thread was
                // closed and reopened.
                _messages.removeWhere((m) =>
                    (m.clientId != null && m.clientId == msg.clientId) ||
                    (m.id.isNotEmpty && !m.id.startsWith('local-') && m.id == msg.id));
                _messages.insert(0, msg);
                _markMessagesStructureChanged();
                // Cleanup: echo fully processed, remove from tracking set.
                if (msg.clientId != null) _wsEchoReceived.remove(msg.clientId);
              });
            });
          } else {
            setState(() {
              // Remove any optimistic version of this message — see the
              // comment in the branch above for why both clientId and id
              // are checked.
              _messages.removeWhere((m) =>
                  (m.clientId != null && m.clientId == msg.clientId) ||
                  (m.id.isNotEmpty && !m.id.startsWith('local-') && m.id == msg.id));
              _messages.insert(0, msg);
              _markMessagesStructureChanged();
              // Cleanup: echo fully processed, remove from tracking set.
              if (msg.clientId != null) _wsEchoReceived.remove(msg.clientId);
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
        case WsFrameType.readReceipt:
          final readerUserId = frame.data['reader_user_id'] as String?;
          final lastReadId = frame.data['last_read_message_id'] as String?;
          // Ignore our own read receipts echoed back — only the
          // counterparty reading our messages should flip our sent bubbles
          // to "read".
          if (readerUserId != null && readerUserId != model.currentUserId && lastReadId != null) {
            final readIdx = _messages.indexWhere((m) => m.id == lastReadId);
            if (readIdx != -1) {
              setState(() {
                // _messages is newest-first — everything from the read
                // message onward (i.e. index >= readIdx, meaning
                // equally-old-or-older) that I sent and isn't already
                // failed gets upgraded to "read".
                for (var i = readIdx; i < _messages.length; i++) {
                  final m = _messages[i];
                  if (m.senderUserId == model.currentUserId &&
                      m.localStatus != DmLocalStatus.failed &&
                      m.localStatus != DmLocalStatus.read) {
                    m.localStatus = DmLocalStatus.read;
                  }
                }
              });
            }
          }
        case WsFrameType.messageDeleted:
          final deletedId = frame.data['message_id'] as String?;
          if (deletedId != null) {
            final idx = _messages.indexWhere((m) => m.id == deletedId);
            if (idx != -1) {
              setState(() {
                _messages[idx].isDeleted = true;
                _messages[idx].content = null;
              });
            }
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

  void _onConnectionStateChanged() {
    if (!mounted) return;
    final state = _ws.connectionState.value;
    final shouldShow = _hasConnectedOnce &&
        (state == WsConnectionState.reconnecting ||
            state == WsConnectionState.disconnected);
    if (shouldShow != _showReconnecting) {
      setState(() => _showReconnecting = shouldShow);
    }
    if (state == WsConnectionState.connected) {
      final wasReconnect = _hasConnectedOnce;
      _hasConnectedOnce = true;
      if (_showReconnecting) setState(() => _showReconnecting = false);
      // Resync on every successful (re)connect, not just on app resume.
      // Previously a WS that dropped and reconnected while the app stayed
      // foregrounded (a plain transient blip, well under the 5-failure
      // give-up threshold) never re-triggered _loadMessages() — any
      // messages the counterparty sent during that gap were simply never
      // fetched until the next full app resume or thread reopen.
      if (wasReconnect) _loadMessages();
    }
  }

  Future<void> _loadMessages({bool more = false}) async {
    final model = ZendScope.of(context);
    if (more && (_loadingMore || _nextCursor == null)) return;
    // If everything left to paginate is at or before the clear boundary,
    // there's nothing older worth fetching — stop here instead of hitting
    // the server for a page that will be filtered down to nothing.
    final clearedBefore = model.dmService.getClearedBefore(widget.roomId);
    if (more && clearedBefore != null && _messages.isNotEmpty &&
        !_messages.last.createdAt.isAfter(clearedBefore)) {
      return;
    }
    // Only show the full-screen spinner if we have nothing to display yet
    if (!more) setState(() { _loading = _messages.isEmpty; _loadError = false; });
    if (more) setState(() => _loadingMore = true);

    try {
      final model = ZendScope.of(context);
      final result = await model.dmService.getMessages(
        widget.roomId,
        cursor: more ? _nextCursor : null,
      );
      if (!mounted) return;
      // Apply this room's clear-chat boundary, if any — hides messages at
      // or before the moment the user cleared history, on every fetch
      // (first load, pagination, and reconnect-triggered resyncs alike),
      // rather than the old approach of blocking the fetch outright and
      // un-blocking it wholesale the instant any new message arrived.
      final clearedBefore = model.dmService.getClearedBefore(widget.roomId);
      final fetched = clearedBefore == null
          ? result.messages
          : result.messages.where((m) => m.createdAt.isAfter(clearedBefore)).toList();
      setState(() {
        if (more) {
          _messages.addAll(fetched);
        } else {
          // Merge: keep any optimistic messages (local-only) and replace the rest
          final localOnly = _messages.where((m) => m.id.startsWith('local-')).toList();
          _messages
            ..clear()
            ..addAll(fetched)
            ..insertAll(0, localOnly);
        }
        _markMessagesStructureChanged();
        // Once we've fetched a page that reaches back to (or past) the
        // clear boundary, there's nothing older left to show — stop
        // paginating even if the server still has more/an older cursor.
        _nextCursor = (clearedBefore != null && fetched.length < result.messages.length)
            ? null
            : result.nextCursor;
        _loading = false;
        _loadingMore = false;
        // Hydrate "read" status on our own sent messages from the
        // counterparty's read cursor — without this, reopening a thread the
        // counterparty had already fully read would show single ticks
        // until the next live read_receipt frame arrives.
        final cpReadId = result.counterpartyLastReadMessageId;
        if (cpReadId != null) {
          final readIdx = _messages.indexWhere((m) => m.id == cpReadId);
          if (readIdx != -1) {
            for (var i = readIdx; i < _messages.length; i++) {
              final m = _messages[i];
              if (m.senderUserId == model.currentUserId &&
                  m.localStatus != DmLocalStatus.failed) {
                m.localStatus = DmLocalStatus.read;
              }
            }
          }
        }
      });
      // Decrypt E2EE messages after loading
      if (_e2eeReady) {
        await _decryptMessages(_messages);
        if (mounted) setState(() {});
      }
      // Mark as read. Must use the newest message with a real server ID —
      // `_messages.first` can be a locally-pending optimistic message (the
      // merge above always re-inserts local-only messages at index 0,
      // ahead of the fetched history) whose `id` is a `local-<uuid>`
      // string, not a real server message UUID. Sending that as
      // `last_message_id` to the read-receipt endpoint would either fail
      // server-side or, worse, silently not advance the read cursor past
      // the actual latest real message — and the failure was previously
      // swallowed by markRead's own catch, so this could go unnoticed
      // indefinitely.
      final latestReal = _messages.where((m) => !m.id.startsWith('local-')).firstOrNull;
      if (latestReal != null) {
        model.dmService.markRead(widget.roomId, latestReal.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          // Only surface the error state on a genuinely empty first load —
          // a failed "load older messages" pagination fetch, or a refresh
          // that already has cached/optimistic messages on screen, should
          // just leave the existing history visible rather than replacing
          // it with an error (the user can still see and send messages).
          if (!more && _messages.isEmpty) _loadError = true;
        });
      }
    }
  }

  /// Replaces the old pixel-offset-based `_onScroll` — scrollable_positioned_list
  /// reports visible item *indices* instead of a ScrollController position,
  /// so paginating and toggling the scroll-to-bottom button both key off the
  /// max visible index now instead of `pixels`/`maxScrollExtent`.
  void _onItemPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final maxIndex = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    final totalCount = _lastBuiltItemCount;

    // Load more when near the end of the built list (reversed list, end = oldest)
    if (totalCount > 0 && maxIndex >= totalCount - 5) {
      _loadMessages(more: true);
    }

    // Show scroll-to-bottom button once index 0 (newest) is no longer visible.
    final minIndex = positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    final shouldShow = minIndex > 0;
    if (shouldShow != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = shouldShow;
        if (!shouldShow) _unseenWhileScrolledUp = 0;
      });
    }
  }

  /// Item count of the most recently built list — set at the top of the
  /// ScrollablePositionedList.builder call in build(). Used by
  /// _onItemPositionsChanged to know when the visible window is nearing the
  /// end of what's currently loaded.
  int _lastBuiltItemCount = 0;

  void _onSend(String text) {
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final model = ZendScope.of(context);
    final clientId = const Uuid().v4();

    final optimistic = DmMessage.optimistic(
      roomId: widget.roomId,
      senderUserId: model.currentUserId ?? '',
      senderZendtag: model.currentZendtag ?? '',
      senderAvatarUrl: model.currentAvatarUrl,
      content: text,
      clientId: clientId,
    );

    setState(() {
      _messages.insert(0, optimistic);
      _markMessagesStructureChanged();
    });

    // Wait for the E2EE key exchange to settle (bounded — see
    // _awaitE2eeResolution) before encrypting, so the first message(s) of a
    // brand-new chat don't race the exchange and get sent as plaintext just
    // because the counterparty's pubkey hadn't arrived yet.
    _awaitE2eeResolution().then((_) => _encryptForSend(text)).then((wireContent) {
      if (mounted) {
        setState(() => optimistic.isEncrypted = wireContent.startsWith(kE2eePrefix));
      } else {
        optimistic.isEncrypted = wireContent.startsWith(kE2eePrefix);
      }
      // Try WebSocket first
      _ws.sendMessage(clientId, wireContent);

      // HTTP fallback after 1.5s if WS ack not received — covers dropped frames
      // or a WS that went silent without closing cleanly.
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        // If the WS echo for this message was already received (even if
        // async decrypt is still in progress), skip the HTTP fallback to
        // avoid sending a duplicate that the server treats as a new message.
        if (_wsEchoReceived.contains(clientId)) return;
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

    // Build the quoted preview — use the actual message ID for reliable lookup.
    // Payment/vibe/payment_request previews include the actual amount
    // (parsed from the quoted message's own paymentData/vibeData/
    // paymentRequestData, already resolved client-side) instead of a bare
    // generic label — otherwise every quoted payment reads as "💸 Payment"
    // regardless of amount.
    final quoteContent = switch (quotedMsg.type) {
      DmMessageType.payment => '💸 \$${(double.tryParse(quotedMsg.paymentData?.amountUsdc ?? '') ?? 0.0).toStringAsFixed(2)}',
      DmMessageType.vibe => '${quotedMsg.vibeData?.displayEmoji ?? '✨'} Vibe · \$${(double.tryParse(quotedMsg.vibeData?.amountUsdc ?? '') ?? 0.0).toStringAsFixed(2)}',
      DmMessageType.paymentRequest => '💬 Payment request · \$${(double.tryParse(quotedMsg.paymentRequestData?.amountUsdc ?? '') ?? 0.0).toStringAsFixed(2)}',
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

    setState(() {
      _messages.insert(0, optimistic);
      _markMessagesStructureChanged();
    });

    _awaitE2eeResolution().then((_) => _encryptForSend(text)).then((wireContent) {
      if (mounted) {
        setState(() => optimistic.isEncrypted = wireContent.startsWith(kE2eePrefix));
      } else {
        optimistic.isEncrypted = wireContent.startsWith(kE2eePrefix);
      }
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
        // If the WS echo for this message was already received (even if
        // async decrypt is still in progress), skip the HTTP fallback to
        // avoid sending a duplicate that the server treats as a new message.
        if (_wsEchoReceived.contains(clientId)) return;
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
              style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 11, color: zt.textSecondary)),
          if (streak != null && streak.isActive)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '🔥 ${streak.streakWeeks}w',
                style: const TextStyle(fontSize: 11, decoration: TextDecoration.none, decorationColor: Colors.transparent),
              ),
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

  String? _flashingMsgId;
  // Guards against overlapping _scrollToReplyOrigin calls triggering
  // multiple concurrent "load more" chains if the user taps several quotes
  // in quick succession.
  bool _resolvingReplyJump = false;

  /// Finds the index of the original message a reply quotes, within
  /// [_messages] (newest-first, matching how the display list is built).
  /// Returns -1 if not currently loaded.
  int _findReplyOriginIndex(DmMessage replyMsg) {
    final replyContent = replyMsg.replyToContent;
    final replySender = replyMsg.replyToSenderZendtag;
    final replyMsgId = replyMsg.replyToMessageId;

    // Prefer ID-based lookup (exact, works for all message types including
    // payment/vibe which have null content)
    if (replyMsgId != null) {
      final idx = _messages.indexWhere((m) => m.id == replyMsgId);
      if (idx != -1) return idx;
    }

    // Fallback: content+sender match for messages sent before ID tracking
    if (replyContent != null) {
      return _messages.indexWhere((m) =>
          m.content == replyContent &&
          (replySender == null || m.senderZendtag == replySender));
    }
    return -1;
  }

  /// Scrolls to the original message a reply quotes and flashes it.
  ///
  /// Unlike a GlobalKey + Scrollable.ensureVisible approach, this uses
  /// ScrollablePositionedList's index-based ItemScrollController, which can
  /// jump straight to any built list index regardless of whether it's
  /// currently near the viewport — fixing the bug where tapping a reply to
  /// a message far above the current scroll position (but already loaded)
  /// silently did nothing.
  ///
  /// If the original message hasn't been paginated into [_messages] yet
  /// (older than what's loaded so far), this fetches older pages — up to a
  /// bounded number of attempts — before giving up and telling the user,
  /// rather than silently no-oping either way.
  Future<void> _scrollToReplyOrigin(DmMessage replyMsg) async {
    if (_resolvingReplyJump) return;
    _resolvingReplyJump = true;
    try {
      var idx = _findReplyOriginIndex(replyMsg);

      // Original not loaded yet — try paginating further back. Bounded to
      // avoid an unbounded fetch loop if the message was deleted server-side
      // or the reply metadata is stale/corrupt.
      var attempts = 0;
      while (idx == -1 && _nextCursor != null && attempts < 8) {
        await _loadMessages(more: true);
        idx = _findReplyOriginIndex(replyMsg);
        attempts++;
      }

      if (idx == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Original message not found', style: TextStyle(fontFamily: 'Geist')),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final targetId = _messages[idx].id;
      // Map the _messages index to the display-list index (which interleaves
      // date separators) — this is what the ScrollablePositionedList's
      // itemBuilder actually indexes into.
      final displayList = _buildDisplayList();
      final displayIdx = displayList.indexWhere(
        (item) => item is _DmMessageItem && item.message.id == targetId,
      );
      if (displayIdx == -1 || !_itemScrollController.isAttached) return;

      await _itemScrollController.scrollTo(
        index: displayIdx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );

      if (mounted) {
        setState(() => _flashingMsgId = targetId);
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) setState(() => _flashingMsgId = null);
        });
      }
    } finally {
      _resolvingReplyJump = false;
    }
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
          onTap: () {
            setState(() => _unseenWhileScrolledUp = 0);
            if (_itemScrollController.isAttached) {
              _itemScrollController.scrollTo(
                index: 0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: zt.bgSecondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: zt.border),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Icon(PhosphorIconsRegular.caretDown, size: 18, color: zt.textSecondary),
              ),
              // "N new" badge — only shown once we know something actually
              // arrived below, not just because the user happens to be
              // scrolled up with no new content.
              if (_unseenWhileScrolledUp > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: zt.accent,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                    ),
                    child: Text(
                      _unseenWhileScrolledUp > 9 ? '9+' : '$_unseenWhileScrolledUp',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Geist', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, height: 1.3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Long-press entry point — shows the iMessage/WhatsApp-style action
  /// overlay: the bubble lifts and bounces into a focused position, the
  /// background blurs, a quick-reaction row appears above it, and an
  /// action menu (Reply / Forward / Copy / Info / Delete) appears below.
  void _showMessageActions(BuildContext ctx, DmMessage msg, Rect originRect) {
    // Dismiss the keyboard before the overlay opens — otherwise the
    // backdrop blur and lifted bubble render with the keyboard still up,
    // which looks wrong and eats a big chunk of the vertical space the
    // overlay needs to lay out the reaction row + action menu.
    FocusScope.of(context).unfocus();
    final isMe = msg.senderUserId == ZendScope.of(context).currentUserId;
    final isTextMessage = msg.type == DmMessageType.text && !msg.isDeleted;

    showMessageActionOverlay(
      context,
      message: msg,
      isMe: isMe,
      originRect: originRect,
      previewBuilder: (previewCtx) => _buildBubbleFor(msg, forPreview: true),
      onReactionTap: (emoji) => _onToggleReaction(msg, emoji),
      actions: DmMessageActions(
        onReply: msg.isDeleted ? null : () => setState(() => _replyingTo = msg),
        onForward: msg.isDeleted ? null : () => _forwardMessage(msg),
        onCopy: isTextMessage && (msg.displayContent?.isNotEmpty ?? false)
            ? () => _copyMessage(msg)
            : null,
        // Read receipts only make sense from the sender's side — matches
        // WhatsApp, which doesn't offer "Info" on messages you received.
        onInfo: isMe && !msg.isDeleted ? () => _showMessageInfo(msg) : null,
        onDelete: isMe && !msg.isDeleted ? () => _deleteMessage(msg) : null,
      ),
    );
  }

  void _copyMessage(DmMessage msg) {
    final text = msg.displayContent;
    if (text == null || text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard', style: TextStyle(fontFamily: 'Geist')),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _forwardMessage(DmMessage msg) async {
    // Only text messages are forwardable for now — payment/vibe messages
    // carry transfer-specific state (transfer_id, on-chain references) that
    // can't be meaningfully re-sent as a copy without re-triggering an
    // actual transfer, which is a materially different action from a plain
    // "forward this content" the menu implies.
    if (msg.type != DmMessageType.text) return;
    final text = msg.displayContent;
    if (text == null || text.isEmpty) return;

    final target = await showDmForwardSheet(context);
    if (target == null || !mounted) return;

    final model = ZendScope.of(context);
    final clientId = const Uuid().v4();
    try {
      await model.dmService.sendMessage(
        target.roomId,
        text,
        clientId,
        forwarded: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Forwarded to @${target.counterparty.zendtag}', style: const TextStyle(fontFamily: 'Geist')),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't forward message", style: TextStyle(fontFamily: 'Geist')),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showMessageInfo(DmMessage msg) {
    showDmMessageInfoSheet(
      context,
      roomId: widget.roomId,
      message: msg,
      previewBuilder: (previewCtx) => _buildBubbleFor(msg, forPreview: true),
    );
  }

  Future<void> _deleteMessage(DmMessage msg) async {
    final zt = ZendTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: zt.bgElevated,
        title: const Text('Delete message?', style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700)),
        content: const Text(
          'This message will be deleted for everyone in this chat.',
          style: TextStyle(fontFamily: 'Geist'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Geist')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(fontFamily: 'Geist', color: ZendColors.destructive)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final idx = _messages.indexWhere((m) => m.id == msg.id);
    if (idx == -1) return;

    // Optimistic — flip to deleted immediately, revert on failure.
    setState(() => _messages[idx].isDeleted = true);
    final model = ZendScope.of(context);
    try {
      await model.dmService.deleteMessage(widget.roomId, msg.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages[idx].isDeleted = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't delete message", style: TextStyle(fontFamily: 'Geist')),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Builds a standalone [DmMessageBubble] for [msg] with no wiring back
  /// into this screen's interactive callbacks — used by the long-press
  /// overlay and message-info sheet, both of which just need to render the
  /// bubble's visuals, not react to further taps/gestures on it.
  Widget _buildBubbleFor(DmMessage msg, {required bool forPreview}) {
    final model = ZendScope.of(context);
    final isMe = msg.senderUserId == model.currentUserId;
    // Preview contexts (long-press overlay, message-info sheet) always use
    // the bubble's default, fully-rounded shape — isFirst/isLast both true —
    // regardless of where this message actually sits within a sender group
    // in the thread. Showing the grouping-derived shape (tight inner
    // corners fused to a neighbor that isn't even present here) reads as a
    // rendering glitch once the bubble is isolated on its own.
    if (forPreview) {
      return DmMessageBubble(
        message: msg,
        isMe: isMe,
        isFirst: true,
        isLast: true,
        showTimestamp: _showTimestamps,
      );
    }
    final msgIdx = _messages.indexWhere((m) => m.id == msg.id);
    final isFirst = msgIdx >= 0 ? _isFirstInGroup(msgIdx) : true;
    final isLast = msgIdx >= 0 ? _isLastInGroup(msgIdx) : true;
    return DmMessageBubble(
      message: msg,
      isMe: isMe,
      isFirst: isFirst,
      isLast: isLast,
      showTimestamp: _showTimestamps,
    );
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
                          Text('Request from', style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 11, color: zt.textSecondary)),
                          Text('@${widget.counterparty.zendtag}', style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w700, color: zt.textPrimary)),
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
                            Text('\$', style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 32, color: zt.textSecondary)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: TextField(
                                controller: amountCtrl,
                                autofocus: true,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 48, color: zt.textPrimary, height: 1),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  hintStyle: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 48, color: zt.textSecondary.withValues(alpha: 0.4)),
                                  border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (_) => setModalState(() => errorMsg = null),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (errorMsg != null)
                        Text(errorMsg!, style: const TextStyle(fontFamily: 'Geist', fontSize: 12, color: ZendColors.destructive)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Note field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: noteCtrl,
                    style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Add a note…',
                      hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary.withValues(alpha: 0.5)),
                      filled: true, fillColor: zt.bgPrimary,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZendRadii.pill), borderSide: BorderSide.none),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.pill)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Send request', style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w700)),
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
    setState(() {
      _messages.insert(0, optimistic);
      _markMessagesStructureChanged();
    });
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
            Text(label, style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: color, fontWeight: FontWeight.w500)),
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
        setState(() {
          _messages.clear();
          _markMessagesStructureChanged();
          // Nothing left to paginate against right after a clear — the
          // fetch-time boundary filter in _loadMessages would eventually
          // stop pagination anyway, but resetting the cursor here means a
          // stray "load more" trigger firing in the same frame (e.g. from
          // scroll position listeners) can't kick off a pointless fetch.
          _nextCursor = null;
        });
        ZendScope.of(context).dmService.clearRoomCache(widget.roomId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Chat cleared', style: TextStyle(fontFamily: 'Geist')), backgroundColor: zt.bgSecondary),
        );
      case _ChatMenuAction.block:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Block feature coming soon', style: TextStyle(fontFamily: 'Geist')), backgroundColor: zt.bgSecondary),
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
      // Prefixed with 'local-' like every other optimistic message (see
      // DmMessage.optimistic() and the reply/payment-request send paths).
      // This one was previously a bare clientId, which meant
      // _loadMessages()'s merge logic — which preserves pending sends by
      // checking `id.startsWith('local-')` — silently dropped an in-flight
      // Vibe if a REST refresh happened to run while it was still sending
      // (e.g. the app backgrounds/resumes mid-send). The Vibe sticker would
      // disappear from the thread until the WS echo or next poll arrived.
      id: 'local-$clientId',
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
    setState(() {
      _messages.insert(0, optimistic);
      _markMessagesStructureChanged();
    });
    HapticFeedback.mediumImpact();

    await _sendVibeBackground(clientId, vibe);
  }

  /// Retries a previously-failed Vibe send. Reconstructs a [VibeSendResult]
  /// from the failed message's own [DmVibeData] (stickerId/emoji/label were
  /// already captured optimistically, so no re-fetch is needed) and re-runs
  /// the same prepare/sign/submit flow against the existing [clientId] —
  /// this lets the server's `client_id` idempotency key correctly treat a
  /// retry-after-actual-success as a no-op rather than double-charging.
  Future<void> _retryVibe(String clientId) async {
    final idx = _messages.indexWhere((m) => m.clientId == clientId);
    if (idx == -1) return;
    final vd = _messages[idx].vibeData;
    if (vd == null) return;
    final amount = double.tryParse(vd.amountUsdc);
    if (amount == null) return;

    setState(() => _messages[idx].localStatus = DmLocalStatus.sending);

    await _sendVibeBackground(
      clientId,
      VibeSendResult(
        stickerId: vd.stickerId,
        stickerEmoji: vd.stickerSlug,
        stickerLabel: vd.stickerName,
        amountUsdc: amount,
      ),
    );
  }

  /// Runs the prepare -> sign -> submit steps for a Vibe send (used by both
  /// the initial send and retry-after-failure), updating the optimistic
  /// message identified by [clientId] to delivered or failed in place.
  Future<void> _sendVibeBackground(String clientId, VibeSendResult vibe) async {
    final model = ZendScope.of(context);
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
    // Only clear if we're still the active room — a second DmThreadScreen
    // instance for a different room may have already overwritten this
    // (e.g. navigating from thread A directly into thread B without A ever
    // fully disposing first). Unconditionally nulling it out here could
    // erase B's active-room marker after B has already claimed it.
    if (PushNotificationService.activeDmRoomId == widget.roomId) {
      PushNotificationService.activeDmRoomId = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    _ws.connectionState.removeListener(_onConnectionStateChanged);
    _ws.dispose();
    _itemPositionsListener.itemPositions.removeListener(_onItemPositionsChanged);
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

  // Memoization for the display list — see _markMessagesStructureChanged()
  // doc comment for why this exists.
  List<_DmDisplayItem>? _cachedDisplayList;
  bool _displayListDirty = true;

  /// Call this from inside any `setState` that inserts, removes, clears, or
  /// reorders [_messages] (NOT for in-place mutations to an existing
  /// message's fields, like reactions or localStatus — those don't change
  /// which items exist or their order, so the cached display list is still
  /// valid for them).
  ///
  /// Without this, [_buildDisplayList] previously reconstructed the entire
  /// chronological + date-separated list — a full reverse, iterate, and
  /// second reverse over every message — on EVERY build() call, including
  /// ones triggered by things that never change the message list at all
  /// (typing-indicator ticks, presence updates, WS reconnect banners). For
  /// any thread with real history this was real, wasted synchronous work
  /// landing on the UI thread right as the thread screen slides in — a
  /// major contributor to the DM-list → DM-thread transition feeling
  /// janky, since that's exactly when a burst of WS connect/typing/presence
  /// frames tends to arrive and trigger rebuilds.
  void _markMessagesStructureChanged() {
    _displayListDirty = true;
  }

  List<_DmDisplayItem> _buildDisplayList() {
    if (!_displayListDirty && _cachedDisplayList != null) {
      return _cachedDisplayList!;
    }
    if (_messages.isEmpty) {
      _cachedDisplayList = const [];
      _displayListDirty = false;
      return _cachedDisplayList!;
    }

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
    _cachedDisplayList = items.reversed.toList();
    _displayListDirty = false;
    return _cachedDisplayList!;
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final cp = widget.counterparty;

    return PopScope(
      // Intercept both the in-app back caret AND the system back
      // button/gesture with the exact same logic: if there's in-screen
      // state to back out of first (an active reply draft, or the
      // timestamp-reveal swipe still held open), clear that instead of
      // immediately leaving the thread. Only pop the route once there's
      // nothing left to back out of — matches the pattern most chat apps
      // use where "back" backs out of a mode before it backs out of the
      // screen.
      canPop: _replyingTo == null && !_showTimestamps,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPressed();
      },
      child: Scaffold(
      // Distinct chat-canvas colour (not the app-wide scaffold background) —
      // gives bubbles a surface to visibly sit on top of, matching the
      // WhatsApp/iMessage "canvas vs. bubble" depth.
      backgroundColor: zt.chatBg,
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
                    onPressed: _handleBackPressed,
                    icon: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary, size: 26),
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
                                  style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w700, color: zt.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_e2eeReady) ...[
                                const SizedBox(width: 5),
                                Icon(PhosphorIconsRegular.lockSimple, size: 13, color: ZendColors.positive),
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
                    icon: Icon(PhosphorIconsRegular.dotsThreeVertical, color: zt.textSecondary, size: 24),
                    color: zt.bgSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.xl)),
                    elevation: 1,
                    shadowColor: Colors.black.withValues(alpha: 0.08),
                    popUpAnimationStyle: AnimationStyle.noAnimation,
                    onSelected: (action) => _handleMenuAction(context, zt, cp, action),
                    itemBuilder: (ctx) => [
                      _popupItem(ctx, zt, _ChatMenuAction.viewContact, PhosphorIconsRegular.user, 'View contact'),
                      _popupItem(ctx, zt, _ChatMenuAction.searchInChat, PhosphorIconsRegular.magnifyingGlass, 'Search in chat', disabled: true),
                      _popupItem(ctx, zt, _ChatMenuAction.disappearing, PhosphorIconsRegular.clock, 'Disappearing messages', disabled: true),
                      _popupItem(ctx, zt, _ChatMenuAction.clearChat, PhosphorIconsRegular.trash, 'Clear chat'),
                      const PopupMenuDivider(),
                      _popupItem(ctx, zt, _ChatMenuAction.block, PhosphorIconsRegular.prohibit, 'Block @${cp.zendtag}', isDestructive: true),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: zt.border),

            // ── Reconnecting banner ──
            if (_showReconnecting)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: zt.bgSecondary,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: zt.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Text('Reconnecting...', style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textSecondary)),
                  ],
                ),
              ),

            // ── Could not connect banner — shown once the WS has given up
            // retrying automatically (5 consecutive failures). Tapping it
            // resets the failure counter and reconnects.
            if (!_showReconnecting && _ws.connectionState.value == WsConnectionState.disconnected && _hasConnectedOnce)
              GestureDetector(
                onTap: () => _ws.resetAndReconnect(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: ZendColors.destructive.withValues(alpha: 0.1),
                  child: Text(
                    'Could not connect. Tap to retry.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textPrimary),
                  ),
                ),
              ),

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
                      : _loadError
                      ? ZendErrorState(
                          title: "Couldn't load this conversation",
                          onRetry: () => _loadMessages(),
                        )
                      : Builder(builder: (ctx) {
                          final displayList = _buildDisplayList();
                          final typingOffset = _theyAreTyping ? 1 : 0;
                          final moreOffset  = _loadingMore ? 1 : 0;
                          final totalCount  = displayList.length + typingOffset + moreOffset;
                          _lastBuiltItemCount = totalCount;

                          return ScrollablePositionedList.builder(
                          itemScrollController: _itemScrollController,
                          itemPositionsListener: _itemPositionsListener,
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
                                        ? (msg.type == DmMessageType.vibe
                                            ? () => _retryVibe(msg.clientId ?? '')
                                            : () => _onRetry(msg.clientId ?? ''))
                                        : null,
                                    onPayRequest: _onPayRequest,
                                    onLongPress: _showMessageActions,
                                    onReactionTap: _onToggleReaction,
                                  ),
                                ),
                              ],
                            );

                            // When this message carries reactions, the floating
                            // badge (drawn inside DmMessageBubble via a
                            // Positioned widget with a negative bottom offset,
                            // so it doesn't affect the Row's own height / the
                            // avatar's cross-axis-end alignment above) needs
                            // somewhere below the bubble to actually sit in.
                            // Grouped messages normally sit almost flush
                            // together (1-5px gap), which isn't enough room —
                            // without this spacer the badge bleeds onto the
                            // next message's bubble. Adding the extra gap
                            // HERE (as a sibling below the Row, not inside it)
                            // reserves that space without dragging the avatar
                            // down with it.
                            Widget itemContent = msg.reactions.isNotEmpty
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      bubbleRow,
                                      const SizedBox(height: 14),
                                    ],
                                  )
                                : bubbleRow;

                            // Flash highlight — AnimatedContainer tint that
                            // fades in and out when tapping a reply to jump
                            // back to the original message.
                            return _FlashHighlight(
                              key: ValueKey(msg.id),
                              isFlashing: isFlashing,
                              child: itemContent,
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

            // "Securing chat…" strip — shown only while the E2EE key exchange
            // for this room is still in flight. Messages sent during this
            // window still wait for resolution (see _awaitE2eeResolution),
            // this is purely informational so the user isn't left guessing
            // why the lock icon in the AppBar hasn't appeared yet.
            if (_e2eeStatus == _E2eeStatus.resolving)
              _SecuringChatStrip(zt: zt),

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
              initialDraft: model.dmService.getDraft(widget.roomId),
              onDraftChanged: (text) => model.dmService.setDraft(widget.roomId, text),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Shared "back" handler for both the in-app caret and the system back
  /// button/gesture (wired via [PopScope] in build()) — backs out of any
  /// active in-screen mode first (reply draft, timestamp-reveal swipe)
  /// before actually leaving the thread, rather than always immediately
  /// popping the route regardless of what's currently open.
  void _handleBackPressed() {
    if (_replyingTo != null) {
      setState(() => _replyingTo = null);
      return;
    }
    if (_showTimestamps) {
      setState(() => _showTimestamps = false);
      return;
    }
    Navigator.of(context).pop();
  }
}

// ── Securing chat strip ─────────────────────────────────────────────────────
//
// Thin informational banner shown above the composer while the E2EE key
// exchange (publish our pubkey, fetch theirs) is still in flight. Sends are
// already gated on this via _awaitE2eeResolution — this is just a visual cue
// so the wait isn't invisible to the user.

class _SecuringChatStrip extends StatelessWidget {
  const _SecuringChatStrip({required this.zt});
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: zt.bgSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: zt.textSecondary),
          ),
          const SizedBox(width: 8),
          Text(
            'Securing chat…',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 12,
              color: zt.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
            fontFamily: 'Geist',
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

    // Icon + preview text per message type — payment/vibe/payment_request
    // show the actual amount rather than a bare generic label.
    final (IconData typeIcon, String preview) = switch (message.type) {
      DmMessageType.payment => (
          PhosphorIconsRegular.arrowsLeftRight,
          '💸 \$${(double.tryParse(message.paymentData?.amountUsdc ?? '') ?? 0.0).toStringAsFixed(2)}',
        ),
      DmMessageType.vibe => (
          PhosphorIconsRegular.star,
          '${message.vibeData?.displayEmoji ?? '✨'} Vibe · \$${(double.tryParse(message.vibeData?.amountUsdc ?? '') ?? 0.0).toStringAsFixed(2)}',
        ),
      DmMessageType.paymentRequest => (
          PhosphorIconsRegular.receipt,
          '💬 Payment request · \$${(double.tryParse(message.paymentRequestData?.amountUsdc ?? '') ?? 0.0).toStringAsFixed(2)}',
        ),
      _ => (PhosphorIconsRegular.chatCircle, message.displayContent ?? ''),
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
                        Icon(PhosphorIconsRegular.arrowBendUpLeft, size: 11, color: zt.accent),
                        const SizedBox(width: 4),
                        Text(
                          isMe
                              ? 'Replying to yourself'
                              : 'Replying to @${message.senderZendtag ?? '…'}',
                          style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 11, color: zt.accent, fontWeight: FontWeight.w600),
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
                              fontFamily: 'Geist',
                              fontSize: 13,
                              color: zt.textSecondary,
                              height: 1.2,
                              // previewShort embeds raw emoji prefixes
                              // (💸/✨/💬) — guard against the stray
                              // underline artifact.
                              decoration: TextDecoration.none,
                              decorationColor: Colors.transparent,
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
                icon: Icon(PhosphorIconsRegular.xCircle, size: 18, color: zt.textSecondary),
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

/// Telegram/WhatsApp-style date pill — a solid rounded badge floating
/// centered on the chat canvas, with no divider lines through it. Replaces
/// the previous "Divider — text — Divider" layout, which read as a plain
/// section rule rather than the sticker-like date chip both reference apps
/// use.
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: zt.isDark ? zt.bgElevated : Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(ZendRadii.pill),
          ),
          child: Text(
            _label(),
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: zt.isDark ? zt.textSecondary : zt.textPrimary.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}
