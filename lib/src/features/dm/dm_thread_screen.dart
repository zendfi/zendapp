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
import '../../services/wallet_session_cache.dart';
import '../../models/qr_payment_intent.dart';
import '../profile/user_profile_screen.dart';
import '../send/qr_payment_sheet.dart';
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
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          final bottomPad = MediaQuery.of(ctx).viewPadding.bottom;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Container(
              margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + (bottomInset > 0 ? 0 : bottomPad)),
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(ZendRadii.xxl),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(ZendRadii.pill)),
                    ),
                  ),
                  Text(
                    'Request from @${widget.counterparty.zendtag}',
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700, color: zt.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'They\'ll see a Pay button in the chat',
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  // Amount field
                  Container(
                    decoration: BoxDecoration(
                      color: zt.bgPrimary,
                      borderRadius: BorderRadius.circular(ZendRadii.lg),
                      border: Border.all(color: errorMsg != null ? ZendColors.destructive : zt.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Text('\$', style: TextStyle(fontFamily: 'DMMono', fontSize: 22, color: zt.textSecondary)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: amountCtrl,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(fontFamily: 'DMMono', fontSize: 22, color: zt.textPrimary),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              hintStyle: TextStyle(fontFamily: 'DMMono', fontSize: 22, color: zt.textSecondary.withValues(alpha: 0.4)),
                              border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (_) => setModalState(() => errorMsg = null),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (errorMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(errorMsg!, style: const TextStyle(fontFamily: 'DMSans', fontSize: 11, color: ZendColors.destructive)),
                    ),
                  const SizedBox(height: 10),
                  // Optional note
                  TextField(
                    controller: noteCtrl,
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Add a note (optional)',
                      hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: zt.bgPrimary,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZendRadii.lg), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Send request', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
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
    final clientId = 'req_${DateTime.now().millisecondsSinceEpoch}';
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

  void _showChatMenu(BuildContext context, ZendTheme zt, DmCounterparty cp) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewPadding.bottom;
        return Container(
          margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
          decoration: BoxDecoration(
            color: zt.bgSecondary,
            borderRadius: BorderRadius.circular(ZendRadii.xxl),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(ZendRadii.pill)),
                ),
              ),
              _ChatMenuTile(
                zt: zt,
                icon: SolarIconsBold.user,
                label: 'View contact',
                onTap: () {
                  Navigator.pop(ctx);
                  pushZendSlide(context, UserProfileScreen(zendtag: cp.zendtag));
                },
              ),
              _ChatMenuTile(
                zt: zt,
                icon: SolarIconsBold.magnifier,
                label: 'Search in chat',
                subtitle: 'Coming soon',
                onTap: () => Navigator.pop(ctx),
                disabled: true,
              ),
              _ChatMenuTile(
                zt: zt,
                icon: SolarIconsBold.clockCircle,
                label: 'Disappearing messages',
                subtitle: 'Coming soon',
                onTap: () => Navigator.pop(ctx),
                disabled: true,
              ),
              _ChatMenuTile(
                zt: zt,
                icon: SolarIconsBold.trashBinMinimalistic,
                label: 'Clear chat',
                subtitle: 'Remove all messages locally',
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _messages.clear());
                },
              ),
              _ChatMenuTile(
                zt: zt,
                icon: SolarIconsBold.userBlock,
                label: 'Block @${cp.zendtag}',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  // Block is a future feature — show info for now
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Block feature coming soon',
                        style: const TextStyle(fontFamily: 'DMSans'),
                      ),
                      backgroundColor: zt.bgSecondary,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onSendVibe(VibeSendResult vibe) async {
    final model = ZendScope.of(context);
    final clientId = 'vibe_${DateTime.now().millisecondsSinceEpoch}';

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

      // Use session cache if available (session-signing policy), else PIN not
      // needed for Vibes — they're micro amounts. We fall back gracefully.
      final cached = WalletSessionCache.instance.keypair;
      if (cached != null) {
        signedTx = await model.walletService.buildAndSignTransactionFromCache(
          keypairBytes: cached,
          amountUsdc: vibe.amountUsdc,
          recipientAddress: recipientAddress,
          blockhash: blockhash,
          feePayerAddress: feePayerAddress,
          senderAtaOverride: senderAta,
          recipientAtaOverride: recipientAta,
        );
        for (var i = 0; i < cached.length; i++) { cached[i] = 0; }
      } else {
        // Session not cached — skip the Vibe silently, mark as failed.
        // In practice this shouldn't happen if the user is authenticated,
        // but we never want to surface a PIN dialog for a sticker send.
        throw Exception('Session expired — re-open to send Vibes');
      }

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
                  // ── Menu button ───────────────────────────────────────
                  IconButton(
                    onPressed: () => _showChatMenu(context, zt, cp),
                    icon: Icon(SolarIconsBold.menuDots, color: zt.textSecondary, size: 20),
                    tooltip: 'Chat options',
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
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      itemCount: _messages.length +
                          (_theyAreTyping ? 1 : 0) +
                          (_loadingMore ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        // Load more spinner
                        if (_loadingMore &&
                            i == _messages.length + (_theyAreTyping ? 1 : 0)) {
                          return const Padding(
                            padding: EdgeInsets.all(8),
                            child: Center(child: ZendLoader(size: 18)),
                          );
                        }
                        // Typing indicator at top (reversed = visually bottom)
                        if (_theyAreTyping && i == 0) {
                          return _TypingIndicator(avatarUrl: cp.avatarUrl, initial: cp.initialLetter);
                        }
                        final msgIdx = _theyAreTyping ? i - 1 : i;
                        final msg = _messages[msgIdx];
                        final isMe = msg.senderUserId == model.currentUserId;
                        final isCont = _isContinuation(msgIdx);

                        // Date separator: show when day changes between messages
                        // (list is reversed, so msgIdx+1 is the older message)
                        Widget? separator;
                        final isLastInList = msgIdx == _messages.length - 1;
                        if (!isLastInList) {
                          final older = _messages[msgIdx + 1];
                          final msgDay = DateTime(msg.createdAt.year, msg.createdAt.month, msg.createdAt.day);
                          final olderDay = DateTime(older.createdAt.year, older.createdAt.month, older.createdAt.day);
                          if (msgDay != olderDay) {
                            separator = _DateSeparator(date: olderDay);
                          }
                        }

                        final bubble = DmMessageBubble(
                          message: msg,
                          isMe: isMe,
                          isContinuation: isCont,
                          onRetry: msg.localStatus == DmLocalStatus.failed
                              ? () => _onRetry(msg.clientId ?? '')
                              : null,
                          onPayRequest: _onPayRequest,
                        );

                        if (separator != null) {
                          return Column(
                            children: [bubble, separator],
                          );
                        }
                        return bubble;
                      },
                    ),
            ),

            // ── Input ─────────────────────────────────────────────────────
            DmInputBar(
              onSend: _onSend,
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

// ── Chat menu tile ─────────────────────────────────────────────────────────────

class _ChatMenuTile extends StatelessWidget {
  const _ChatMenuTile({
    required this.zt,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.isDestructive = false,
    this.disabled = false,
  });

  final ZendTheme zt;
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? ZendColors.destructive : zt.textPrimary;
    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: ListTile(
        onTap: disabled ? null : onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: isDestructive
                ? ZendColors.destructive.withValues(alpha: 0.1)
                : zt.bgPrimary,
            borderRadius: BorderRadius.circular(ZendRadii.md),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: zt.textSecondary),
              )
            : null,
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
