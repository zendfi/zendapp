import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_format.dart';
import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_money.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import '../../models/api_exceptions.dart';
import '../activity/activity_comment_sheet.dart'
    show
        CommentRow,
        CommentSheetReactionChip,
        CommentSkeleton,
        kCommentSheetReactionEmojis;
import 'zapp_card.dart';
import 'zapp_feed_card.dart';
import 'zapp_sheet.dart';

/// A ZApp card opened from the Feed. Laid out like the payment Activity sheet: a header, the card
/// as the "post" with its reactions, then the comments and a composer. Anyone who can see the
/// card can react and comment: a card carries no payment, so writing isn't limited to the people
/// in the match.
Future<void> showAppCardSheet(BuildContext context, Map<String, dynamic> card) {
  return showZendModalSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    inDetailPane: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AppCardSheet(card: card),
  );
}

class _AppCardSheet extends StatefulWidget {
  const _AppCardSheet({required this.card});
  final Map<String, dynamic> card;

  @override
  State<_AppCardSheet> createState() => _AppCardSheetState();
}

class _AppCardSheetState extends State<_AppCardSheet> {
  final _ctrl = TextEditingController();
  List<EdgeReactionCount> _reactions = const [];
  List<EdgeComment> _comments = const [];
  bool _loading = true;
  bool _loadError = false;
  bool _sending = false;

  String get _id => widget.card['id'] as String;
  String get _slug => ((widget.card['app'] as Map?)?['slug'] as String?) ?? '';
  String get _appName =>
      ((widget.card['app'] as Map?)?['name'] as String?) ?? 'App';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Geist')),
      ),
    );
  }

  Future<void> _load() async {
    final svc = ZendScope.read(context).activityDataService;
    setState(() => _loadError = false);
    try {
      final r = await Future.wait([
        svc.getEdgeReactions(kAppCardKind, _id),
        svc.getEdgeComments(kAppCardKind, _id),
      ]);
      if (!mounted) return;
      setState(() {
        _reactions = r[0] as List<EdgeReactionCount>;
        _comments = r[1] as List<EdgeComment>;
      });
    } catch (_) {
      if (mounted && _comments.isEmpty) setState(() => _loadError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String emoji) async {
    ZendFeel.reaction();
    final svc = ZendScope.read(context).activityDataService;
    final mine = _reactions.any((r) => r.emoji == emoji && r.reactedByMe);
    final before = _reactions;
    // Optimistic, reverted if the server refuses.
    setState(() {
      final next = List<EdgeReactionCount>.of(_reactions);
      final i = next.indexWhere((r) => r.emoji == emoji);
      if (mine && i != -1) {
        final n = next[i].count - 1;
        if (n <= 0) {
          next.removeAt(i);
        } else {
          next[i] = EdgeReactionCount(
            emoji: emoji,
            count: n,
            reactedByMe: false,
          );
        }
      } else if (i != -1) {
        next[i] = EdgeReactionCount(
          emoji: emoji,
          count: next[i].count + 1,
          reactedByMe: true,
        );
      } else {
        next.add(EdgeReactionCount(emoji: emoji, count: 1, reactedByMe: true));
      }
      _reactions = next;
    });
    try {
      if (mine) {
        await svc.removeEdgeReaction(kAppCardKind, _id, emoji);
      } else {
        await svc.addEdgeReaction(kAppCardKind, _id, emoji);
      }
    } catch (e) {
      if (mounted) setState(() => _reactions = before);
      _toast(friendlyError(e));
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final svc = ZendScope.read(context).activityDataService;
    try {
      await svc.addEdgeComment(kAppCardKind, _id, text);
      _ctrl.clear();
      final c = await svc.getEdgeComments(kAppCardKind, _id);
      if (mounted) setState(() => _comments = c);
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(EdgeComment c) async {
    final svc = ZendScope.read(context).activityDataService;
    final before = _comments;
    setState(() => _comments = _comments.where((x) => x.id != c.id).toList());
    try {
      await svc.deleteEdgeComment(kAppCardKind, _id, c.id);
    } catch (_) {
      if (mounted) setState(() => _comments = before);
      _toast("Couldn't delete comment. Try again.");
    }
  }

  void _showPicker() {
    final mine = _reactions
        .where((r) => r.reactedByMe)
        .map((r) => r.emoji)
        .toSet();
    showZendModalSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      inDetailPane: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final zt = ZendTheme.of(ctx);
        return Container(
          margin: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            12 + MediaQuery.of(ctx).viewPadding.bottom,
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: zt.bgSecondary,
            borderRadius: BorderRadius.circular(ZendRadii.xxl),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: zt.border,
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                  ),
                ),
              ),
              Text(
                'React to this',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in kCommentSheetReactionEmojis)
                    CommentSheetReactionChip(
                      emoji: e,
                      selected: mine.contains(e),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _toggle(e);
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

  static String _stateLabel(String? s) => switch (s) {
    'sent' => 'Waiting',
    'accepted' => 'Accepted',
    'in_progress' => 'In progress',
    'resolved' => 'Done',
    'expired' => 'Expired',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final poster = widget.card['poster'] as Map? ?? const {};
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final stateLabel = _stateLabel(widget.card['state'] as String?);
    final name = appCardPosterName(widget.card);

    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
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
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary,
                    ),
                  ),
                ),
                if (_slug.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => openZApp(context, _slug),
                    icon: Icon(
                      PhosphorIconsRegular.arrowSquareOut,
                      size: 16,
                      color: zt.accent,
                    ),
                    label: Text(
                      'Open $_appName',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: zt.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(color: zt.border, height: 1),

          // ── The card (the "post") ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ZendAvatar(
                  radius: 22,
                  photoUrl: poster['avatar_url'] as String?,
                  initials: name.replaceFirst('@', '').isEmpty
                      ? '?'
                      : name.replaceFirst('@', '')[0].toUpperCase(),
                  seed: poster['user_id'] as String?,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name on $_appName',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: zt.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // The app's own card, drawn by core.
                      ZAppCard(card: widget.card, inBubble: true),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (stateLabel.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: zt.border.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(
                                  ZendRadii.pill,
                                ),
                              ),
                              child: Text(
                                stateLabel,
                                style: ZendTextStyles.tabularNumeric.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: zt.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            formatRelativeTime(appCardTime(widget.card)),
                            style: ZendTextStyles.tabularNumeric.copyWith(
                              fontSize: 11,
                              color: zt.textSecondary.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      // Existing reactions (tappable pills)
                      if (_reactions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final r in _reactions)
                              GestureDetector(
                                onTap: () => _toggle(r.emoji),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: r.reactedByMe
                                        ? zt.accent.withValues(alpha: 0.18)
                                        : zt.bgSecondary,
                                    borderRadius: BorderRadius.circular(
                                      ZendRadii.pill,
                                    ),
                                    border: r.reactedByMe
                                        ? Border.all(
                                            color: zt.accent.withValues(
                                              alpha: 0.5,
                                            ),
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        r.emoji,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${r.count}',
                                        style: ZendTextStyles.tabularNumeric
                                            .copyWith(
                                              fontSize: 11,
                                              color: zt.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      // Quick-react bar: six core reactions and a "more" button.
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final e in kCommentSheetReactionEmojis.take(6))
                            GestureDetector(
                              onTap: () => _toggle(e),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),
                            ),
                          GestureDetector(
                            onTap: _showPicker,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: zt.bgSecondary,
                                borderRadius: BorderRadius.circular(
                                  ZendRadii.pill,
                                ),
                              ),
                              child: Icon(
                                PhosphorIconsRegular.smiley,
                                size: 16,
                                color: zt.textSecondary,
                              ),
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
                ? const CommentSkeleton()
                : _loadError
                ? ZendErrorState(
                    title: "Couldn't load comments",
                    onRetry: _load,
                  )
                : _comments.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No comments yet. Be the first to say something.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13.5,
                          color: zt.textSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _comments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final c = _comments[i];
                      return CommentRow(
                        comment: c,
                        isMine: c.authorUserId == model.currentUserId,
                        relativeTime: formatRelativeTime(c.createdAt.toLocal()),
                        onDelete: () => _delete(c),
                      );
                    },
                  ),
          ),

          // ── Composer ──
          Container(
            decoration: BoxDecoration(
              color: zt.bgPrimary,
              border: Border(top: BorderSide(color: zt.border)),
            ),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ZendAvatar(
                    radius: 16,
                    photoUrl: model.currentAvatarUrl,
                    initials: model.selfInitial,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(ZendRadii.pill),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                    child: TextField(
                      controller: _ctrl,
                      maxLength: 280,
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 14,
                        color: zt.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Add a comment…',
                        hintStyle: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 14,
                          color: zt.textSecondary,
                        ),
                        border: InputBorder.none,
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: _sending ? null : _send,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _sending
                            ? zt.accent.withValues(alpha: 0.5)
                            : zt.accent,
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: ZendLoader(
                                size: 16,
                                strokeWidth: 1.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              PhosphorIconsRegular.paperPlaneTilt,
                              size: 17,
                              color: Colors.white,
                            ),
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
