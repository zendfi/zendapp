import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';

const _kCommentSheetReactionEmojis = ['🔥', '💰', '🙏', '👑', '😭', '⚡', '🎯', '💸', '🎉', '👀', '✅', '🚀'];

/// Twitter-style "tap into a post" destination for a single Activity_Edge —
/// shows the activity itself (like the original post) with its reaction
/// bar, then every comment on it (like replies) below it, plus a composer
/// for the edge's sender/recipient to add their own (enforced server-side;
/// this sheet just surfaces whatever the API allows).
///
/// This replaces the previous design where commenting was crammed into the
/// bottom of the formal transaction receipt. The receipt is still one tap
/// away via the "Receipt" button in this sheet's header — this sheet is now
/// the primary destination when an activity is tapped; the receipt is a
/// secondary, more formal drill-down from here.
Future<void> showActivityCommentSheet(
  BuildContext context, {
  required ActivityEdge edge,
  required String headline,
  String? avatarUrl,
  required String avatarInitial,
  required VoidCallback onViewReceipt,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ActivityCommentSheet(
      edge: edge,
      headline: headline,
      avatarUrl: avatarUrl,
      avatarInitial: avatarInitial,
      onViewReceipt: onViewReceipt,
    ),
  );
}

class _ActivityCommentSheet extends StatefulWidget {
  const _ActivityCommentSheet({
    required this.edge,
    required this.headline,
    required this.avatarUrl,
    required this.avatarInitial,
    required this.onViewReceipt,
  });

  final ActivityEdge edge;
  final String headline;
  final String? avatarUrl;
  final String avatarInitial;
  final VoidCallback onViewReceipt;

  @override
  State<_ActivityCommentSheet> createState() => _ActivityCommentSheetState();
}

class _ActivityCommentSheetState extends State<_ActivityCommentSheet> {
  List<EdgeReactionCount> _reactions = const [];
  List<EdgeComment> _comments = const [];
  bool _loading = true;
  final TextEditingController _commentController = TextEditingController();
  bool _postingComment = false;

  String get _edgeKindStr {
    switch (widget.edge.edgeKind) {
      case ActivityEdgeKind.zendTransfer:
        return 'zend_transfer';
      case ActivityEdgeKind.poolContribution:
        return 'pool_contribution';
      case ActivityEdgeKind.requestFulfillment:
        return 'request_fulfillment';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final model = ZendScope.of(context);
    try {
      final results = await Future.wait([
        model.activityDataService.getEdgeReactions(_edgeKindStr, widget.edge.edgeId),
        model.activityDataService.getEdgeComments(_edgeKindStr, widget.edge.edgeId),
      ]);
      if (mounted) {
        setState(() {
          _reactions = results[0] as List<EdgeReactionCount>;
          _comments = results[1] as List<EdgeComment>;
        });
      }
    } catch (_) {
      // Non-fatal — the sheet still renders the activity tile without
      // reactions/comments if the fetch fails.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleReaction(String emoji) async {
    final model = ZendScope.of(context);
    final existing = _reactions.where((r) => r.emoji == emoji).firstOrNull;
    final alreadyReacted = existing?.reactedByMe ?? false;

    setState(() {
      final updated = List<EdgeReactionCount>.of(_reactions);
      final idx = updated.indexWhere((r) => r.emoji == emoji);
      if (alreadyReacted && idx != -1) {
        final newCount = updated[idx].count - 1;
        if (newCount <= 0) {
          updated.removeAt(idx);
        } else {
          updated[idx] = EdgeReactionCount(emoji: emoji, count: newCount, reactedByMe: false);
        }
      } else if (idx != -1) {
        updated[idx] = EdgeReactionCount(emoji: emoji, count: updated[idx].count + 1, reactedByMe: true);
      } else {
        updated.add(EdgeReactionCount(emoji: emoji, count: 1, reactedByMe: true));
      }
      _reactions = updated;
    });

    try {
      if (alreadyReacted) {
        await model.activityDataService.removeEdgeReaction(_edgeKindStr, widget.edge.edgeId, emoji);
      } else {
        await model.activityDataService.addEdgeReaction(_edgeKindStr, widget.edge.edgeId, emoji);
      }
    } catch (_) {
      if (mounted) _load();
    }
  }

  void _showReactionPicker() {
    final reactedEmojis = _reactions.where((r) => r.reactedByMe).map((r) => r.emoji).toSet();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final zt = ZendTheme.of(sheetContext);
        final bottomInset = MediaQuery.of(sheetContext).viewPadding.bottom;
        return Container(
          margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(color: zt.bgSecondary, borderRadius: BorderRadius.circular(ZendRadii.xxl)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(ZendRadii.pill)),
                ),
              ),
              Text(
                'React to this',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w700, color: zt.textPrimary),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final emoji in _kCommentSheetReactionEmojis)
                    _CommentSheetReactionChip(
                      emoji: emoji,
                      selected: reactedEmojis.contains(emoji),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _toggleReaction(emoji);
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _postComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty || _postingComment) return;
    final model = ZendScope.of(context);
    setState(() => _postingComment = true);
    try {
      await model.activityDataService.addEdgeComment(_edgeKindStr, widget.edge.edgeId, body);
      _commentController.clear();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not post comment — try again', style: TextStyle(fontFamily: 'DMSans'))),
        );
      }
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  Future<void> _deleteComment(EdgeComment comment) async {
    final model = ZendScope.of(context);
    setState(() => _comments = _comments.where((c) => c.id != comment.id).toList());
    try {
      await model.activityDataService.deleteEdgeComment(_edgeKindStr, widget.edge.edgeId, comment.id);
    } catch (_) {
      if (mounted) _load();
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final edge = widget.edge;
    final amountLabel = edge.amountHidden ? 'Hidden' : '\$${edge.amountUsdc ?? '0'}';
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      // Full-screen height, matching the receipt sheet — the comment sheet
      // is a primary destination, not a peek; it needs all the space.
      height: screenHeight,
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          const ZendSheetHandle(),
          const SizedBox(height: 8),

          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Activity',
                    style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 22, fontWeight: FontWeight.w700, color: zt.textPrimary),
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onViewReceipt,
                  icon: Icon(SolarIconsBold.bill, size: 16, color: zt.accent),
                  label: Text('Receipt', style: TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600, color: zt.accent)),
                ),
              ],
            ),
          ),
          Divider(color: zt.border, height: 1),

          // ── Activity tile (the "post") ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ZendAvatar(radius: 22, photoUrl: widget.avatarUrl, initials: widget.avatarInitial),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Headline is the primary text — larger, more prominent
                      Text(
                        widget.headline,
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w600, color: zt.textPrimary, height: 1.3),
                      ),
                      const SizedBox(height: 6),
                      // Note (payment memo) rendered as post body copy
                      if (edge.note?.isNotEmpty == true) ...[
                        Text(
                          edge.note!,
                          style: TextStyle(fontFamily: 'DMSans', fontSize: 15, height: 1.45, color: zt.textPrimary.withValues(alpha: 0.88)),
                        ),
                        const SizedBox(height: 10),
                      ],
                      // Amount + timestamp on the same row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: edge.isOutgoing ? zt.border.withValues(alpha: 0.5) : ZendColors.positive.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(ZendRadii.pill),
                            ),
                            child: Text(
                              '${edge.isOutgoing ? '-' : '+'}$amountLabel',
                              style: TextStyle(fontFamily: 'DMMono', fontSize: 12, fontWeight: FontWeight.w700,
                                  color: edge.isOutgoing ? zt.textSecondary : ZendColors.positive),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_relativeTime(edge.createdAt), style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary.withValues(alpha: 0.8))),
                        ],
                      ),
                      // ── Existing reactions (tappable pills) ──
                      if (_reactions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final r in _reactions)
                              GestureDetector(
                                onTap: () => _toggleReaction(r.emoji),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: r.reactedByMe ? zt.accent.withValues(alpha: 0.18) : zt.bgSecondary,
                                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                                    border: r.reactedByMe ? Border.all(color: zt.accent.withValues(alpha: 0.5)) : null,
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(r.emoji, style: const TextStyle(fontSize: 13)),
                                    const SizedBox(width: 4),
                                    Text('${r.count}', style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary)),
                                  ]),
                                ),
                              ),
                          ],
                        ),
                      ],
                      // ── Inline 6-emoji quick-react bar ──
                      // Always visible below the note — no modal needed for
                      // the common case of adding one of the 6 core reactions.
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final emoji in _kCommentSheetReactionEmojis.take(6))
                            GestureDetector(
                              onTap: () => _toggleReaction(emoji),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(emoji, style: const TextStyle(fontSize: 22)),
                              ),
                            ),
                          // "More" button opens the full 12-emoji picker
                          GestureDetector(
                            onTap: _showReactionPicker,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: zt.bgSecondary, borderRadius: BorderRadius.circular(ZendRadii.pill)),
                              child: Icon(SolarIconsBold.emojiFunnyCircle, size: 16, color: zt.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(color: zt.border, height: 1),

          // ── Comments (replies) ──
          Expanded(
            child: _loading
                ? _CommentSkeleton()
                : _comments.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No comments yet — be the first to say something.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'DMSans', fontSize: 13.5, color: zt.textSecondary),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: _comments.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, i) {
                          final comment = _comments[i];
                          return _CommentRow(
                            comment: comment,
                            isMine: comment.authorUserId == model.currentUserId,
                            relativeTime: _relativeTime(comment.createdAt),
                            onDelete: () => _deleteComment(comment),
                          );
                        },
                      ),
          ),

          // ── Composer ──
          // Elevated card-style bar: user avatar | field | send button.
          // A top border + slight elevation separates it from the comment list
          // without an ugly flat band. Keyboard-aware via viewInsets.
          Container(
            decoration: BoxDecoration(
              color: zt.bgPrimary,
              border: Border(top: BorderSide(color: zt.border)),
            ),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Current user's avatar — pinned to bottom
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ZendAvatar(
                    radius: 16,
                    photoUrl: model.currentAvatarUrl,
                    initials: model.currentZendtag?.isNotEmpty == true
                        ? model.currentZendtag![0].toUpperCase()
                        : (model.currentDisplayName?.isNotEmpty == true
                            ? model.currentDisplayName![0].toUpperCase()
                            : 'Y'),
                  ),
                ),
                const SizedBox(width: 10),
                // Composed input bubble
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(ZendRadii.pill),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            maxLength: 280,
                            maxLines: 4,
                            minLines: 1,
                            textInputAction: TextInputAction.newline,
                            style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Add a comment…',
                              hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                              border: InputBorder.none,
                              counterText: '',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Send button — bottom-aligned so it stays at the baseline
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: GestureDetector(
                            onTap: _postingComment ? null : _postComment,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _postingComment ? zt.accent.withValues(alpha: 0.5) : zt.accent,
                                shape: BoxShape.circle,
                              ),
                              child: _postingComment
                                  ? Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: ZendLoader(size: 16, strokeWidth: 1.5, color: Colors.white),
                                    )
                                  : const Icon(SolarIconsBold.plain, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.isMine, required this.relativeTime, required this.onDelete});

  final EdgeComment comment;
  final bool isMine;
  final String relativeTime;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onLongPress: isMine
          ? () => showDialog<void>(
                context: context,
                barrierDismissible: true,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete comment?'),
                  content: const Text("This can't be undone."),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onDelete();
                      },
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: ZendColors.destructive),
                      ),
                    ),
                  ],
                ),
              )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ZendAvatar(
            radius: 16,
            photoUrl: comment.authorAvatarUrl,
            initials: comment.authorZendtag.isNotEmpty ? comment.authorZendtag[0].toUpperCase() : '?',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('@${comment.authorZendtag}',
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w700, color: zt.textPrimary)),
                    const SizedBox(width: 6),
                    Text(relativeTime, style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5, color: zt.textSecondary.withValues(alpha: 0.8))),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.body, style: TextStyle(fontFamily: 'DMSans', fontSize: 13.5, height: 1.3, color: zt.textPrimary.withValues(alpha: 0.9))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton loading placeholder — 3 shimmering comment rows shown while
/// reactions and comments are being fetched from the server.
class _CommentSkeleton extends StatefulWidget {
  @override
  State<_CommentSkeleton> createState() => _CommentSkeletonState();
}

class _CommentSkeletonState extends State<_CommentSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final opacity = 0.3 + 0.35 * _anim.value;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, i) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 32, height: 32, decoration: BoxDecoration(color: zt.border.withValues(alpha: opacity), shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 11, width: 80, decoration: BoxDecoration(color: zt.border.withValues(alpha: opacity), borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 6),
                  Container(height: 13, width: double.infinity, decoration: BoxDecoration(color: zt.border.withValues(alpha: opacity * 0.7), borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 4),
                  Container(height: 13, width: i == 1 ? 160 : 120, decoration: BoxDecoration(color: zt.border.withValues(alpha: opacity * 0.5), borderRadius: BorderRadius.circular(4))),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Large, tappable emoji option in the reaction picker sheet
class _CommentSheetReactionChip extends StatefulWidget {
  const _CommentSheetReactionChip({required this.emoji, required this.selected, required this.onTap});

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CommentSheetReactionChip> createState() => _CommentSheetReactionChipState();
}

class _CommentSheetReactionChipState extends State<_CommentSheetReactionChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.85 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected ? zt.accent.withValues(alpha: 0.18) : zt.bgSecondary,
            borderRadius: BorderRadius.circular(ZendRadii.lg),
            border: widget.selected ? Border.all(color: zt.accent.withValues(alpha: 0.6), width: 1.5) : null,
          ),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 26)),
        ),
      ),
    );
  }
}
