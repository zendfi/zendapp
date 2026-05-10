import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../services/sse_service.dart';
import 'mission_room_message.dart';
import 'pool.dart';
import 'pool_progress_bar.dart';

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
  List<PoolMessage> _messages = [];
  bool _loading = true;
  String? _loadError;

  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  bool _sending = false;
  final _audioRecorder = AudioRecorder();
  String? _recordingPath;
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  StreamSubscription<SseEvent>? _sseSub;

  @override
  void initState() {
    super.initState();
    _pool = widget.pool;
    _loadMessages();
    _subscribeSse();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _scrollController.dispose();
    _textController.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

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
        _messages = msgs;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

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
        // Deduplicate: the sender already added the message optimistically
        // from the API response; skip if we already have it by ID.
        if (!_messages.any((m) => m.id == msg.id)) {
          setState(() => _messages.add(msg));
          _scrollToBottom();
        }

      case SseEventType.poolContribution:
        final gatheredStr = data['gathered_amount_usdc'] as String?;
        if (gatheredStr != null) {
          final gathered = double.tryParse(gatheredStr);
          if (gathered != null) {
            setState(() => _pool.gathered = gathered);
          }
        }
      case SseEventType.poolReaction:
        final messageId = data['message_id'] as String?;
        final emoji = data['emoji'] as String?;
        final reactorZendtag = data['reactor_zendtag'] as String?;
        if (messageId != null && emoji != null) {
          _updateReaction(
              messageId, emoji, reactorZendtag, increment: true);
        }

      case SseEventType.poolReactionRemoved:
        final messageId = data['message_id'] as String?;
        final emoji = data['emoji'] as String?;
        final reactorZendtag = data['reactor_zendtag'] as String?;
        if (messageId != null && emoji != null) {
          _updateReaction(
              messageId, emoji, reactorZendtag, increment: false);
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
          if (status != null) {
            setState(() => _pool.status = status);
          }
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
          reactions.add(PoolReactionCount(
            emoji: emoji,
            count: 1,
            reactedByMe: isMe,
          ));
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

  Future<void> _sendMessage() async {
    final content = _textController.text.trim();
    if (content.isEmpty || content.length > 280) return;

    setState(() => _sending = true);
    _textController.clear();

    try {
      final model = ZendScope.of(context);
      final msg = await model.walletService.apiClient
          .postMessage(poolId: _pool.id, content: content);
      if (!mounted) return;
      // Add the message from the API response. The SSE event will also arrive
      // but _onSseEvent deduplicates by ID, so it won't be added twice.
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages.add(msg);
        }
        _sending = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

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
      orElse: () => const PoolReactionCount(
          emoji: '', count: 0, reactedByMe: false),
    );

    // Optimistic update
    _updateReaction(message.id, emoji, model.currentZendtag,
        increment: !existing.reactedByMe);

    try {
      if (existing.reactedByMe) {
        await model.walletService.apiClient.removeReaction(
          poolId: _pool.id,
          messageId: message.id,
          emoji: emoji,
        );
      } else {
        await model.walletService.apiClient.addReaction(
          poolId: _pool.id,
          messageId: message.id,
          emoji: emoji,
        );
      }
    } catch (_) {
      if (mounted) {
        _updateReaction(message.id, emoji, model.currentZendtag,
            increment: existing.reactedByMe);
      }
    }
  }

  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
      }
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      _recordingPath =
          '${dir.path}/pool_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: _recordingPath!,
      );

      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });

      _recordingTimer =
          Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= 30) _stopRecording();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final duration = _recordingSeconds;
    final path = _recordingPath;

    if (!mounted) return;
    setState(() => _isRecording = false);

    if (path == null || duration < 1) return;

    try {
      await _audioRecorder.stop();

      final file = File(path);
      if (!await file.exists()) return;
      final audioBytes = await file.readAsBytes();
      try { await file.delete(); } catch (_) {}

      if (!mounted) return;
      setState(() => _sending = true);

      final model = ZendScope.of(context);
      final msg = await model.walletService.apiClient.postVoiceNote(
        poolId: _pool.id,
        audioBytes: audioBytes,
        mimeType: 'audio/m4a',
        durationSeconds: duration,
      );

      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages.add(msg);
        }
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice note: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool get _isActive => _pool.status == PoolStatus.active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ZendSpacing.lg, vertical: ZendSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(color: ZendColors.border, height: 1),
              const SizedBox(height: ZendSpacing.xs),
              PoolProgressBar(progress: _pool.progress),
              const SizedBox(height: ZendSpacing.xxs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _pool.formattedGathered,
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 11,
                      color: ZendColors.accentBright,
                    ),
                  ),
                  Text(
                    _pool.formattedTarget,
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 11,
                      color: ZendColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

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

        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                        ZendColors.accentBright),
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
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: ZendSpacing.lg,
                              vertical: ZendSpacing.xs),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final msg = _messages[i];
                            final model = ZendScope.of(context);
                            return MissionRoomMessage(
                              message: msg,
                              currentUserId: model.currentUserId,
                              onLongPress: () => _showReactionPicker(msg),
                              onReactionTap: (emoji) =>
                                  _toggleReaction(msg, emoji),
                            );
                          },
                        ),
        ),

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
    widget.controller.addListener(() {
      setState(() => _charCount = widget.controller.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = 280 - _charCount;
    final overLimit = remaining < 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          ZendSpacing.md, ZendSpacing.xs, ZendSpacing.md, ZendSpacing.md),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ZendColors.border)),
      ),
      child: widget.isRecording
          // ── Recording indicator ──────────────────────────────────────
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
                  child: const Text(
                    'Stop',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontWeight: FontWeight.w600,
                      color: ZendColors.destructive,
                    ),
                  ),
                ),
              ],
            )
          // ── Normal input row ─────────────────────────────────────────
          : Row(
              children: [
                // Text field
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    maxLines: 4,
                    minLines: 1,
                    maxLength: 280,
                    buildCounter: (_, {required currentLength,
                        required isFocused, maxLength}) {
                      if (!isFocused) return null;
                      return Text(
                        '$remaining',
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 11,
                          color: overLimit
                              ? ZendColors.destructive
                              : ZendColors.textSecondary,
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
                        borderRadius:
                            BorderRadius.circular(ZendRadii.pill),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: ZendSpacing.xs),

                // Mic button — hold to record
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
                    child: const Icon(
                      Icons.mic_none,
                      size: 20,
                      color: ZendColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: ZendSpacing.xs),

                // Send button
                GestureDetector(
                  onTap: overLimit || widget.sending ? null : widget.onSend,
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
    );
  }
}

class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet({required this.onEmojiTap});
  final ValueChanged<String> onEmojiTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
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
          Wrap(
            spacing: ZendSpacing.sm,
            runSpacing: ZendSpacing.sm,
            alignment: WrapAlignment.center,
            children: _curatedEmojis.map((emoji) {
              return GestureDetector(
                onTap: () => onEmojiTap(emoji),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ZendColors.bgSecondary,
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
