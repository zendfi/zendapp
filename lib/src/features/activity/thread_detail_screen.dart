import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import 'activity_comment_sheet.dart';
import 'activity_grouping.dart';
import 'activity_receipt_builder.dart';
import 'transaction_receipt_sheet.dart';

const _kReactionEmojis = ['🔥', '💰', '🙏', '👑', '😭', '⚡', '🎯', '💸', '🎉', '👀', '✅', '🚀'];

/// A Twitter/X-feed-style view of every Activity_Edge between the viewer
/// and one Counterparty — the destination of tapping a User thread on
/// [ThreadedActivityScreen]. Each edge renders as a feed post: sentence
/// headline, note, reaction row, and a tap-through to the full receipt.
///
/// Reactions and "make public" both round-trip through the server
/// (`activity_data_service.rs`'s `/reactions` and `/make-public` endpoints)
/// — nothing here re-implements authorization; every edge shown was already
/// authorized by the same Activity_Data_Service query that populated the
/// thread list this screen was opened from.
class ThreadDetailScreen extends StatefulWidget {
  const ThreadDetailScreen({super.key, required this.counterparty, required this.edges});

  final ActivityCounterparty counterparty;
  final List<ActivityEdge> edges;

  @override
  State<ThreadDetailScreen> createState() => _ThreadDetailScreenState();
}

class _ThreadDetailScreenState extends State<ThreadDetailScreen> {
  late List<ActivityEdge> _edges;
  final Map<String, List<EdgeReactionCount>> _reactionsByEdgeId = {};
  final Set<String> _reactionsLoading = {};

  @override
  void initState() {
    super.initState();
    _edges = List.of(widget.edges)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final edge in _edges) {
      _loadReactions(edge);
    }
  }

  Future<void> _loadReactions(ActivityEdge edge) async {
    final model = ZendScope.of(context);
    try {
      final reactions = await model.activityDataService.getEdgeReactions(_edgeKindStr(edge.edgeKind), edge.edgeId);
      if (mounted) setState(() => _reactionsByEdgeId[edge.edgeId] = reactions);
    } catch (_) {
      // Non-fatal — the feed post just renders with no reaction row.
    }
  }

  String _edgeKindStr(ActivityEdgeKind kind) {
    switch (kind) {
      case ActivityEdgeKind.zendTransfer:
        return 'zend_transfer';
      case ActivityEdgeKind.poolContribution:
        return 'pool_contribution';
      case ActivityEdgeKind.requestFulfillment:
        return 'request_fulfillment';
    }
  }

  Future<void> _toggleReaction(ActivityEdge edge, String emoji) async {
    final model = ZendScope.of(context);
    final current = _reactionsByEdgeId[edge.edgeId] ?? [];
    final existing = current.where((r) => r.emoji == emoji).firstOrNull;
    final alreadyReacted = existing?.reactedByMe ?? false;

    // Optimistic update.
    setState(() {
      final updated = List<EdgeReactionCount>.of(current);
      if (alreadyReacted) {
        final idx = updated.indexWhere((r) => r.emoji == emoji);
        if (idx != -1) {
          final newCount = updated[idx].count - 1;
          if (newCount <= 0) {
            updated.removeAt(idx);
          } else {
            updated[idx] = EdgeReactionCount(emoji: emoji, count: newCount, reactedByMe: false);
          }
        }
      } else {
        final idx = updated.indexWhere((r) => r.emoji == emoji);
        if (idx != -1) {
          updated[idx] = EdgeReactionCount(emoji: emoji, count: updated[idx].count + 1, reactedByMe: true);
        } else {
          updated.add(EdgeReactionCount(emoji: emoji, count: 1, reactedByMe: true));
        }
      }
      _reactionsByEdgeId[edge.edgeId] = updated;
    });

    try {
      if (alreadyReacted) {
        await model.activityDataService.removeEdgeReaction(_edgeKindStr(edge.edgeKind), edge.edgeId, emoji);
      } else {
        await model.activityDataService.addEdgeReaction(_edgeKindStr(edge.edgeKind), edge.edgeId, emoji);
      }
    } catch (_) {
      // Revert on failure by refetching the authoritative state.
      if (mounted) _loadReactions(edge);
    }
  }

  void _showReactionPicker(ActivityEdge edge) {
    final reactedEmojis = (_reactionsByEdgeId[edge.edgeId] ?? const [])
        .where((r) => r.reactedByMe)
        .map((r) => r.emoji)
        .toSet();

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
                  for (final emoji in _kReactionEmojis)
                    _ReactionPickerChip(
                      emoji: emoji,
                      selected: reactedEmojis.contains(emoji),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _toggleReaction(edge, emoji);
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

  Future<void> _makePublic(ActivityEdge edge) async {
    final model = ZendScope.of(context);
    setState(() => _reactionsLoading.add(edge.edgeId));
    try {
      await model.activityDataService.makeEdgePublic(_edgeKindStr(edge.edgeKind), edge.edgeId);
      if (mounted) {
        setState(() {
          final idx = _edges.indexWhere((e) => e.edgeId == edge.edgeId);
          if (idx != -1) {
            _edges[idx] = ActivityEdge(
              edgeId: edge.edgeId,
              edgeKind: edge.edgeKind,
              counterparty: edge.counterparty,
              amountUsdc: edge.amountUsdc,
              amountHidden: edge.amountHidden,
              direction: edge.direction,
              effectiveTier: VisibilityTier.sharedNetwork,
              isDirectParticipant: edge.isDirectParticipant,
              note: edge.note,
              createdAt: edge.createdAt,
              transactionSignature: edge.transactionSignature,
              status: edge.status,
              senderZendtag: edge.senderZendtag,
              senderDisplayName: edge.senderDisplayName,
              senderAvatarUrl: edge.senderAvatarUrl,
              recipientZendtag: edge.recipientZendtag,
              recipientDisplayName: edge.recipientDisplayName,
              recipientAvatarUrl: edge.recipientAvatarUrl,
            );
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Now visible to your shared network', style: TextStyle(fontFamily: 'DMSans'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not make this public — try again', style: TextStyle(fontFamily: 'DMSans'))),
        );
      }
    } finally {
      if (mounted) setState(() => _reactionsLoading.remove(edge.edgeId));
    }
  }

  /// Tapping a feed post now opens the Twitter-style comment sheet
  /// (activity tile + reactions + replies) instead of jumping straight to
  /// the formal receipt — the receipt is one tap further via the comment
  /// sheet's own "Receipt" header button (see `_openReceipt`).
  void _openActivity(ActivityEdge edge) {
    final isOutgoing = edge.isOutgoing;
    final verb = feedVerbFor(edge);
    final headline = isOutgoing ? 'You $verb ${widget.counterparty.displayLabel}' : '${widget.counterparty.displayLabel} $verb you';
    final model = ZendScope.of(context);
    final selfAvatarUrl = model.currentAvatarUrl;
    final selfInitial = model.currentZendtag?.isNotEmpty == true
        ? model.currentZendtag![0].toUpperCase()
        : (model.currentDisplayName?.isNotEmpty == true ? model.currentDisplayName![0].toUpperCase() : 'Y');

    showActivityCommentSheet(
      context,
      edge: edge,
      headline: headline,
      avatarUrl: isOutgoing ? selfAvatarUrl : widget.counterparty.avatarUrl,
      avatarInitial: isOutgoing ? selfInitial : widget.counterparty.initialLetter,
      onViewReceipt: () => _openReceipt(edge),
    );
  }

  void _openReceipt(ActivityEdge edge) {
    final model = ZendScope.of(context);
    final entry = entryFromEdgeForViewer(edge, model);
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Details for this activity are not available', style: TextStyle(fontFamily: 'DMSans'))),
      );
      return;
    }
    final tx = zendTransactionFromEdge(
      edge,
      entry,
      avatarLabel: edge.counterparty.initialLetter,
      avatarUrl: edge.counterparty.avatarUrl,
    );
    showTransactionReceipt(context, tx: tx);
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: zt.textPrimary),
                  ),
                  ZendAvatar(radius: 18, photoUrl: widget.counterparty.avatarUrl, initials: widget.counterparty.initialLetter),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.counterparty.displayLabel,
                          style: TextStyle(fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700, color: zt.textPrimary),
                        ),
                        Text(
                          '${_edges.length} activit${_edges.length == 1 ? 'y' : 'ies'} together',
                          style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: zt.border, height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _edges.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, i) {
                  final edge = _edges[i];
                  return _FeedPost(
                    edge: edge,
                    counterparty: widget.counterparty,
                    reactions: _reactionsByEdgeId[edge.edgeId] ?? const [],
                    isMakingPublic: _reactionsLoading.contains(edge.edgeId),
                    onTap: () => _openActivity(edge),
                    onReactionTap: (emoji) => _toggleReaction(edge, emoji),
                    onAddReaction: () => _showReactionPicker(edge),
                    onMakePublic: edge.isDirectParticipant && edge.effectiveTier == VisibilityTier.private
                        ? () => _makePublic(edge)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single large, tappable emoji option in the reaction picker sheet —
/// highlights when it's the viewer's current reaction, and does a small
/// press-scale animation for a bit of tactile feedback.
class _ReactionPickerChip extends StatefulWidget {
  const _ReactionPickerChip({required this.emoji, required this.selected, required this.onTap});

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ReactionPickerChip> createState() => _ReactionPickerChipState();
}

class _ReactionPickerChipState extends State<_ReactionPickerChip> {
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
            color: widget.selected ? zt.accent.withValues(alpha: 0.18) : zt.bgPrimary,
            borderRadius: BorderRadius.circular(ZendRadii.lg),
            border: widget.selected ? Border.all(color: zt.accent.withValues(alpha: 0.6), width: 1.5) : null,
          ),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 26)),
        ),
      ),
    );
  }
}

class _FeedPost extends StatelessWidget {
  const _FeedPost({
    required this.edge,
    required this.counterparty,
    required this.reactions,
    required this.isMakingPublic,
    required this.onTap,
    required this.onReactionTap,
    required this.onAddReaction,
    this.onMakePublic,
  });

  final ActivityEdge edge;
  final ActivityCounterparty counterparty;
  final List<EdgeReactionCount> reactions;
  final bool isMakingPublic;
  final VoidCallback onTap;
  final void Function(String emoji) onReactionTap;
  final VoidCallback onAddReaction;
  final VoidCallback? onMakePublic;

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
    final isOutgoing = edge.isOutgoing;
    final amountLabel = edge.amountHidden ? 'Hidden' : '\$${edge.amountUsdc ?? '0'}';
    final verb = feedVerbFor(edge);
    final actionSpan = isOutgoing ? 'You $verb ' : '';
    final trailingSpan = isOutgoing ? '' : ' $verb';
    final selfAvatarUrl = model.currentAvatarUrl;
    final selfInitial = model.currentZendtag?.isNotEmpty == true
        ? model.currentZendtag![0].toUpperCase()
        : (model.currentDisplayName?.isNotEmpty == true ? model.currentDisplayName![0].toUpperCase() : 'Y');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ZendRadii.xl),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ZendAvatar(
                      radius: 18,
                      photoUrl: isOutgoing ? selfAvatarUrl : counterparty.avatarUrl,
                      initials: isOutgoing ? selfInitial : counterparty.initialLetter,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
                              children: [
                                if (actionSpan.isNotEmpty) TextSpan(text: actionSpan),
                                TextSpan(
                                  text: counterparty.displayLabel,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                if (trailingSpan.isNotEmpty) TextSpan(text: trailingSpan),
                              ],
                            ),
                          ),
                          Text(
                            _relativeTime(edge.createdAt),
                            style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5, color: zt.textSecondary.withValues(alpha: 0.8)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isOutgoing ? zt.border.withValues(alpha: 0.5) : ZendColors.positive.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                      child: Text(
                        '${isOutgoing ? '-' : '+'}$amountLabel',
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isOutgoing ? zt.textSecondary : ZendColors.positive,
                        ),
                      ),
                    ),
                  ],
                ),
                if (edge.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    edge.note!,
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 14, height: 1.35, color: zt.textPrimary.withValues(alpha: 0.9)),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final r in reactions)
                            GestureDetector(
                              onTap: () => onReactionTap(r.emoji),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: r.reactedByMe ? zt.accent.withValues(alpha: 0.18) : zt.bgPrimary,
                                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                                  border: r.reactedByMe ? Border.all(color: zt.accent.withValues(alpha: 0.5)) : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(r.emoji, style: const TextStyle(fontSize: 13)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${r.count}',
                                      style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          GestureDetector(
                            onTap: onAddReaction,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: zt.bgPrimary, borderRadius: BorderRadius.circular(ZendRadii.pill)),
                              child: Icon(Icons.add_reaction_outlined, size: 15, color: zt.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onMakePublic != null)
                      TextButton(
                        onPressed: isMakingPublic ? null : onMakePublic,
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: isMakingPublic
                            ? ZendLoader(size: 14, strokeWidth: 2, color: zt.accent)
                            : Text(
                                'Make public',
                                style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.accent, fontWeight: FontWeight.w600),
                              ),
                      )
                    else if (edge.effectiveTier == VisibilityTier.sharedNetwork)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.public, size: 12, color: zt.textSecondary.withValues(alpha: 0.7)),
                          const SizedBox(width: 3),
                          Text(
                            'Public',
                            style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5, color: zt.textSecondary.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

