import 'package:flutter/material.dart';

import '../../core/zend_format.dart';
import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import '../../models/api_exceptions.dart';
import 'zapp_card.dart';
import 'zapp_feed_card.dart';

const _kReactionEmojis = [
  '🔥',
  '💰',
  '🙏',
  '👑',
  '😭',
  '⚡',
  '🎯',
  '💸',
  '🎉',
  '👀',
  '✅',
  '🚀',
];

/// The card with its reactions and every comment. Anyone who can see the card can react and
/// comment: a card carries no payment, so writing isn't limited to the people in the match.
Future<void> showAppCardSheet(BuildContext context, Map<String, dynamic> card) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
  bool _sending = false;
  String? _error;

  String get _id => widget.card['id'] as String;

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

  Future<void> _load() async {
    final svc = ZendScope.read(context).activityDataService;
    try {
      final r = await Future.wait([
        svc.getEdgeReactions(kAppCardKind, _id),
        svc.getEdgeComments(kAppCardKind, _id),
      ]);
      if (!mounted) return;
      setState(() {
        _reactions = r[0] as List<EdgeReactionCount>;
        _comments = r[1] as List<EdgeComment>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _toggle(String emoji) async {
    final svc = ZendScope.read(context).activityDataService;
    final mine = _reactions.any((r) => r.emoji == emoji && r.reactedByMe);
    try {
      if (mine) {
        await svc.removeEdgeReaction(kAppCardKind, _id, emoji);
      } else {
        await svc.addEdgeReaction(kAppCardKind, _id, emoji);
      }
      final r = await svc.getEdgeReactions(kAppCardKind, _id);
      if (mounted) setState(() => _reactions = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final svc = ZendScope.read(context).activityDataService;
    try {
      await svc.addEdgeComment(kAppCardKind, _id, text);
      _ctrl.clear();
      final c = await svc.getEdgeComments(kAppCardKind, _id);
      if (mounted) setState(() => _comments = c);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(EdgeComment c) async {
    final svc = ZendScope.read(context).activityDataService;
    try {
      await svc.deleteEdgeComment(kAppCardKind, _id, c.id);
      if (mounted) {
        setState(
          () => _comments = _comments.where((x) => x.id != c.id).toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final me = ZendScope.read(context).currentUserId;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final poster = widget.card['poster'] as Map? ?? const {};
    final appName =
        (widget.card['app'] as Map?)?['name'] as String? ?? 'an app';

    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
        );

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: zt.bgPrimary,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZendRadii.xxl),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: zt.border,
                borderRadius: BorderRadius.circular(ZendRadii.pill),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                children: [
                  Row(
                    children: [
                      ZendAvatar(
                        radius: 22,
                        photoUrl: poster['avatar_url'] as String?,
                        initials: appCardPosterName(widget.card)
                            .replaceFirst('@', '')
                            .characters
                            .firstOrNull
                            ?.toUpperCase(),
                        seed: poster['user_id'] as String?,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${appCardPosterName(widget.card)} on $appName',
                              style: s(15, w: FontWeight.w700),
                            ),
                            Text(
                              formatRelativeTime(appCardTime(widget.card)),
                              style: s(12, c: zt.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ZAppCard(card: widget.card, inBubble: true),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in _kReactionEmojis)
                        _EmojiChip(
                          emoji: e,
                          count:
                              _reactions
                                  .where((r) => r.emoji == e)
                                  .firstOrNull
                                  ?.count ??
                              0,
                          mine: _reactions.any(
                            (r) => r.emoji == e && r.reactedByMe,
                          ),
                          onTap: () => _toggle(e),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No comments yet. Say something.',
                        style: s(13, c: zt.textSecondary),
                      ),
                    )
                  else
                    for (final c in _comments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ZendAvatar(
                              radius: 16,
                              photoUrl: c.authorAvatarUrl,
                              initials: c.authorZendtag.isEmpty
                                  ? '?'
                                  : c.authorZendtag[0].toUpperCase(),
                              seed: c.authorUserId,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '@${c.authorZendtag} · ${formatRelativeTime(c.createdAt.toLocal())}',
                                    style: s(12, c: zt.textSecondary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(c.body, style: s(14)),
                                ],
                              ),
                            ),
                            if (c.authorUserId == me)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: zt.textSecondary,
                                ),
                                onPressed: () => _delete(c),
                              ),
                          ],
                        ),
                      ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_error!, style: s(13, c: zt.destructive)),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        maxLength: 280,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: s(14),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Add a comment',
                          filled: true,
                          fillColor: zt.bgSecondary,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(ZendRadii.pill),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      style: IconButton.styleFrom(backgroundColor: zt.accent),
                      icon: const Icon(Icons.arrow_upward, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiChip extends StatelessWidget {
  const _EmojiChip({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: mine ? zt.accentPop : zt.bgElevated,
          borderRadius: BorderRadius.circular(ZendRadii.chip),
        ),
        child: Text(
          count > 0 ? '$emoji $count' : emoji,
          style: TextStyle(fontSize: 14, color: zt.textPrimary),
        ),
      ),
    );
  }
}
