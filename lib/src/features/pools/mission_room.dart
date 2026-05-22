import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../services/sse_service.dart';
import 'mission_room_message.dart';
import 'pool.dart';

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
  final List<PoolMessage> _messages = [];
  bool _loading = true;
  String? _loadError;

  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  bool _sending = false;
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  // Tracks IDs of messages we sent optimistically so we can skip the SSE echo
  final Set<String> _pendingIds = {};

  StreamSubscription<SseEvent>? _sseSub;

  @override
  void initState() {
    super.initState();
    _pool = widget.pool;
    _loadMessages();
    _subscribeSse();
    WidgetsBinding.instance.addObserver(_LifecycleObserver(onResume: _onAppResume));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_LifecycleObserver(onResume: _onAppResume));
    _sseSub?.cancel();
    _scrollController.dispose();
    _textController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  /// Called when the app returns to the foreground.
  /// Silently reloads messages to catch up on anything missed while backgrounded.
  void _onAppResume() {
    if (!mounted) return;
    // Only reload if we're not already loading and the room is active
    if (!_loading) {
      _loadMessages();
    }
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final model = ZendScope.of(context);
      final msgs = await model.walletService.apiClient
          .listMessages(poolId: _pool.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        _loading = false;
      });
      _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  /// Adds [msg] to [_messages] only if no message with the same ID exists.
  /// Replaces a temp message by matching on both sender and content.
  void _upsertMessage(PoolMessage msg) {
    final realIdx = _messages.indexWhere((m) => m.id == msg.id);
    if (realIdx >= 0) return; // already present — skip

    // Find a temp placeholder from the same sender with the same content
    final tempIdx = _messages.indexWhere((m) =>
        m.id.startsWith('temp_') &&
        m.senderUserId == msg.senderUserId &&
        m.content == msg.content);

    if (tempIdx >= 0) {
      _messages[tempIdx] = msg;
    } else {
      _messages.add(msg);
    }
  }

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
      case SseEventType.poolMessage:
        final msg = PoolMessage.fromJson(data);
        // Skip if we sent this message — the send flow handles insertion.
        if (_pendingIds.remove(msg.id)) return;
        setState(() {
          _upsertMessage(msg);
        });
        _jumpToBottom();

      case SseEventType.poolContribution:
        final gatheredStr = data['gathered_amount_usdc'] as String?;
        if (gatheredStr != null) {
          final gathered = double.tryParse(gatheredStr);
          if (gathered != null) setState(() => _pool.gathered = gathered);
        }

      case SseEventType.poolReaction:
        final messageId = data['message_id'] as String?;
        final emoji = data['emoji'] as String?;
        final reactorZendtag = data['reactor_zendtag'] as String?;
        if (messageId != null && emoji != null) {
          _updateReaction(messageId, emoji, reactorZendtag, increment: true);
        }

      case SseEventType.poolReactionRemoved:
        final messageId = data['message_id'] as String?;
        final emoji = data['emoji'] as String?;
        final reactorZendtag = data['reactor_zendtag'] as String?;
        if (messageId != null && emoji != null) {
          _updateReaction(messageId, emoji, reactorZendtag, increment: false);
        }

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
      final idx = _messages.indexWhere((m) => m.id == messageId);
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
    });
  }

  // ── Sending ─────────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final content = _textController.text.trim();
    if (content.isEmpty || content.length > 280) return;

    _textController.clear();

    // Optimistic: add a temporary message immediately so the UI feels instant
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final model = ZendScope.of(context);
    final optimistic = PoolMessage(
      id: tempId,
      poolId: _pool.id,
      senderZendtag: model.currentZendtag,
      senderUserId: model.currentUserId,
      messageType: PoolMessageType.text,
      content: content,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(optimistic);
      _sending = true;
    });
    _jumpToBottom();

    try {
      final msg = await model.walletService.apiClient
          .postMessage(poolId: _pool.id, content: content);
      if (!mounted) return;

      // Register the real ID BEFORE setState so any concurrent SSE echo
      // that arrives between now and the setState is suppressed.
      _pendingIds.add(msg.id);

      setState(() {
        // Remove the optimistic temp regardless
        _messages.removeWhere((m) => m.id == tempId);
        // Add the real message only if SSE hasn't already added it
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages.add(msg);
        }
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Remove the optimistic message on failure
      setState(() {
        _messages.removeWhere((m) => m.id == tempId);
        _sending = false;
      });
    }
  }

  // ── Reactions ────────────────────────────────────────────────────────────────

  void _showReactionPicker(PoolMessage message) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmojiPickerSheet(
        onEmojiTap: (emoji) {
          Navigator.of(context).pop();
          _toggleReaction(message, emoji);
        },
      ),
    );
  }

  Future<void> _toggleReaction(PoolMessage message, String emoji) async {
    final model = ZendScope.of(context);
    final existing = message.reactions.firstWhere(
      (r) => r.emoji == emoji,
      orElse: () => const PoolReactionCount(emoji: '', count: 0, reactedByMe: false),
    );

    _updateReaction(message.id, emoji, model.currentZendtag,
        increment: !existing.reactedByMe);

    try {
      if (existing.reactedByMe) {
        await model.walletService.apiClient.removeReaction(
          poolId: _pool.id, messageId: message.id, emoji: emoji);
      } else {
        await model.walletService.apiClient.addReaction(
          poolId: _pool.id, messageId: message.id, emoji: emoji);
      }
    } catch (_) {
      if (mounted) {
        _updateReaction(message.id, emoji, model.currentZendtag,
            increment: existing.reactedByMe);
      }
    }
  }

  // ── Recording (stub) ─────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    setState(() { _isRecording = true; _recordingSeconds = 0; });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _recordingSeconds++);
      if (_recordingSeconds >= 30) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (!mounted) return;
    setState(() => _isRecording = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice notes coming soon 🎙️'),
          duration: Duration(seconds: 2)),
    );
  }

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
          msg.messageType == PoolMessageType.text;

      items.add(_MessageItem(message: msg, isContinuation: isContinuation));
      lastSenderId = msg.senderUserId;
      lastMessageTime = msg.createdAt;
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    // Read model once outside the builder — avoids per-item dependency tracking
    final model = ZendScope.of(context);
    final currentUserId = model.currentUserId;

    return Column(
      children: [
        // ── Closed-pool archive banner ──
        if (!_isActive)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: ZendSpacing.lg, vertical: ZendSpacing.xs),
            color: ZendColors.bgSecondary,
            child: const Text(
              'This pool has closed — messages are read-only',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                color: ZendColors.textSecondary,
              ),
            ),
          ),

        // ── Message list ──
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(ZendColors.accentBright),
                  ),
                )
              : _loadError != null
                  ? Center(
                      child: TextButton(
                        onPressed: _loadMessages,
                        child: const Text('Retry',
                            style: TextStyle(color: ZendColors.accentBright)),
                      ),
                    )
                  : _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet. Say something! 👋',
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 14,
                              color: ZendColors.textSecondary,
                            ),
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
                                itemCount: displayList.length,
                                itemBuilder: (_, i) {
                                  final item = displayList[i];
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
                                      onReactionTap: (emoji) =>
                                          _toggleReaction(msg, emoji),
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
  final PoolMessage message;
  final bool isContinuation;
}

// ── Date separator widget ─────────────────────────────────────────────────────

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: ZendColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _label(),
              style: const TextStyle(
                fontFamily: 'DMMono',
                fontSize: 11,
                color: ZendColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const Expanded(child: Divider(color: ZendColors.border)),
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
            color: ZendColors.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white,
            size: 22,
          ),
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
  });

  final TextEditingController controller;
  final bool sending;
  final bool isRecording;
  final int recordingSeconds;
  final VoidCallback onSend;
  final Future<void> Function() onMicStart;
  final Future<void> Function() onMicStop;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final len = widget.controller.text.length;
    if (len != _charCount) setState(() => _charCount = len);
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
        padding: const EdgeInsets.fromLTRB(
            ZendSpacing.md, ZendSpacing.xs, ZendSpacing.md, ZendSpacing.sm),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: ZendColors.border)),
        ),
        child: widget.isRecording
            // ── Recording indicator ──
            ? Row(
                children: [
                  const Icon(Icons.fiber_manual_record,
                      color: ZendColors.destructive, size: 14),
                  const SizedBox(width: ZendSpacing.xs),
                  Text(
                    'Recording ${widget.recordingSeconds}s / 30s',
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 13,
                      color: ZendColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => unawaited(widget.onMicStop()),
                    child: const Text('Stop',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontWeight: FontWeight.w600,
                          color: ZendColors.destructive,
                        )),
                  ),
                ],
              )
            // ── Normal input row ──
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
                      buildCounter: (_, {required currentLength,
                          required isFocused, maxLength}) {
                        if (!isFocused || !overLimit) return null;
                        return Text(
                          '$remaining',
                          style: const TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 11,
                            color: ZendColors.destructive,
                          ),
                        );
                      },
                      decoration: InputDecoration(
                        hintText: 'Message the group...',
                        hintStyle: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 14,
                          color: ZendColors.textSecondary,
                        ),
                        filled: true,
                        fillColor: ZendColors.bgSecondary,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(ZendRadii.pill),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: ZendSpacing.xs),

                  // Mic button
                  GestureDetector(
                    onLongPressStart: (_) => unawaited(widget.onMicStart()),
                    onLongPressEnd: (_) => unawaited(widget.onMicStop()),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: ZendColors.bgSecondary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic_none,
                          size: 20, color: ZendColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: ZendSpacing.xs),

                  // Send button
                  GestureDetector(
                    onTap: overLimit || widget.sending || _charCount == 0
                        ? null
                        : widget.onSend,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: overLimit || _charCount == 0
                            ? ZendColors.bgSecondary
                            : ZendColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: widget.sending
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : Icon(
                              Icons.send,
                              size: 18,
                              color: overLimit || _charCount == 0
                                  ? ZendColors.textSecondary
                                  : Colors.white,
                            ),
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
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        0,
        14,
        0,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: ZendColors.bgPrimary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: ZendColors.border,
              borderRadius: BorderRadius.circular(ZendRadii.pill),
            ),
          ),
          const SizedBox(height: ZendSpacing.md),
          // Two rows of 6 emojis — each cell square, full width
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
                          decoration: BoxDecoration(
                            color: ZendColors.bgSecondary,
                            borderRadius: BorderRadius.circular(ZendRadii.md),
                          ),
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
  @override
  bool operator ==(Object other) =>
      other is _LifecycleObserver && other.onResume == onResume;

  @override
  int get hashCode => onResume.hashCode;
}
