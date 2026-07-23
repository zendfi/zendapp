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
  bool _showScrollToBottom = false;

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
              children: emojis.take(8).map((e) => GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  entry.remove();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text(e, style: const TextStyle(fontSize: 26, decoration: TextDecoration.none)),
                ),
              )).toList(),
            ),
          ),
        ),
      ),
    ]));
    overlay.insert(entry);
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
                SizedBox(height: 16 + (bottomInset > 0 ? 0 : MediaQuery.of(ctx).viewPadding.bottom)),
                // Confirm button
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset > 0 ? bottomInset : 16),
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

  /// Whether the message at [index] is the FIRST (topmost) in its sender run.
  /// In the reversed list, the message before (index - 1) is newer.
  bool _isFirstInGroup(int index) {
    if (index == 0) return true; // newest message = always starts a group visually
    final current = _messages[index];
    final newer = _messages[index - 1];
    if (current.senderUserId != newer.senderUserId) return true;
    return current.createdAt.difference(newer.createdAt).inSeconds.abs() >= 60;
  }

  /// Whether the message at [index] is the LAST (bottommost) in its sender run — gets the tail.
  bool _isLastInGroup(int index) {
    if (index >= _messages.length - 1) return true;
    final current = _messages[index];
    final older = _messages[index + 1];
    if (current.senderUserId != older.senderUserId) return true;
    return current.createdAt.difference(older.createdAt).inSeconds.abs() >= 60;
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
                    child: ZendAvatar(radius: 20, photoUrl: cp.avatarUrl, initials: cp.initialLetter),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => pushZendSlide(context, UserProfileScreen(zendtag: cp.zendtag)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            cp.displayName.trim().isEmpty ? '@${cp.zendtag}' : cp.displayName,
                            style: TextStyle(fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700, color: zt.textPrimary),
                          ),
                          Row(
                            children: [
                              Text('@${cp.zendtag}', style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary)),
                              Builder(builder: (ctx) {
                                final streak = model.activeStreaks[cp.userId];
                                if (streak == null || !streak.isActive) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text('🔥 ${streak.streakWeeks}w', style: const TextStyle(fontSize: 11)),
                                );
                              }),
                            ],
                          ),
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
              child: Stack(
                children: [
                  _loading
                      ? const Center(child: ZendLoader(size: 24))
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                          itemCount: _messages.length +
                              (_theyAreTyping ? 1 : 0) +
                              (_loadingMore ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (_loadingMore &&
                                i == _messages.length + (_theyAreTyping ? 1 : 0)) {
                              return const Padding(
                                padding: EdgeInsets.all(8),
                                child: Center(child: ZendLoader(size: 18)),
                              );
                            }
                            if (_theyAreTyping && i == 0) {
                              return _TypingIndicator(avatarUrl: cp.avatarUrl, initial: cp.initialLetter);
                            }
                            final msgIdx = _theyAreTyping ? i - 1 : i;
                            final msg = _messages[msgIdx];
                            final isMe = msg.senderUserId == model.currentUserId;
                            final isCont = _isContinuation(msgIdx);
                            final isFirst = _isFirstInGroup(msgIdx);
                            final isLast = _isLastInGroup(msgIdx);
                            final isGroupEnd = !isMe && isLast;

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

                            final bubble = Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Avatar slot — only shown on group-end for incoming
                                if (!isMe) SizedBox(
                                  width: 32,
                                  child: isGroupEnd
                                      ? ZendAvatar(radius: 13, photoUrl: cp.avatarUrl, initials: cp.initialLetter)
                                      : null,
                                ),
                                Expanded(
                                  child: DmMessageBubble(
                                    message: msg,
                                    isMe: isMe,
                                    isContinuation: isCont,
                                    isFirst: isFirst,
                                    isLast: isLast,
                                    onRetry: msg.localStatus == DmLocalStatus.failed
                                        ? () => _onRetry(msg.clientId ?? '')
                                        : null,
                                    onPayRequest: _onPayRequest,
                                    onLongPress: _showMessageReactions,
                                  ),
                                ),
                              ],
                            );

                            if (separator != null) {
                              return Column(children: [bubble, separator]);
                            }
                            return bubble;
                          },
                        ),
                  // ── Scroll-to-bottom button ─────────────────────────────
                  _buildScrollToBottomButton(zt),
                ],
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

// ── Chat menu ─────────────────────────────────────────────────────────────────

enum _ChatMenuAction { viewContact, searchInChat, disappearing, clearChat, block }

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
