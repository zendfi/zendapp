import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_format.dart';
import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_motion_widgets.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import '../../design/zend_verified_badge.dart';
import 'zapp_card.dart';
import 'zapp_card_sheet.dart';

/// Reaction and comment calls reuse the activity edge endpoints; the server routes this kind
/// to its own tables.
const kAppCardKind = 'app_card';

DateTime appCardTime(Map<String, dynamic> card) =>
    DateTime.tryParse(card['created_at'] as String? ?? '')?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

String appCardPosterName(Map<String, dynamic> card) {
  final p = card['poster'] as Map? ?? const {};
  final name = (p['display_name'] as String?)?.trim() ?? '';
  if (name.isNotEmpty) return name;
  final tag = (p['zendtag'] as String?) ?? '';
  return tag.isEmpty ? 'Someone' : '@$tag';
}

String _posterInitial(Map<String, dynamic> card) {
  final n = appCardPosterName(card).replaceFirst('@', '');
  return n.isEmpty ? '?' : n[0].toUpperCase();
}

/// A ZApp card shown as an Activity item: the poster's avatar and a one-line headline, the app's
/// own template as the body, then the same reactions and comment count as any other item.
/// Tapping opens the card with every comment.
class ZAppFeedCard extends StatefulWidget {
  const ZAppFeedCard({super.key, required this.card});

  final Map<String, dynamic> card;

  @override
  State<ZAppFeedCard> createState() => _ZAppFeedCardState();
}

class _ZAppFeedCardState extends State<ZAppFeedCard> {
  List<EdgeReactionCount> _reactions = const [];
  late int _comments = (widget.card['comment_count'] as num?)?.toInt() ?? 0;

  String get _id => widget.card['id'] as String;

  @override
  void initState() {
    super.initState();
    unawaited(_loadReactions());
  }

  Future<void> _loadReactions() async {
    final svc = ZendScope.read(context).activityDataService;
    // Same settle delay as the other items, so a fast scroll costs nothing.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    try {
      final r = await svc.getEdgeReactions(kAppCardKind, _id);
      if (mounted) setState(() => _reactions = r);
    } catch (_) {}
  }

  Future<void> _open() async {
    final svc = ZendScope.read(context).activityDataService;
    await showAppCardSheet(context, widget.card);
    if (!mounted) return;
    svc.invalidateEdgeReactions(kAppCardKind, _id);
    unawaited(_loadReactions());
    try {
      final c = await svc.getEdgeComments(kAppCardKind, _id);
      if (mounted) setState(() => _comments = c.length);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final poster = widget.card['poster'] as Map? ?? const {};
    final appName =
        (widget.card['app'] as Map?)?['name'] as String? ?? 'an app';
    final total = _reactions.fold<int>(0, (s, r) => s + r.count);
    return ZendPressScale(
      child: Material(
        color: zt.bgCard,
        borderRadius: BorderRadius.circular(ZendRadii.card),
        child: InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(ZendRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ZendAvatar(
                      radius: 24,
                      photoUrl: poster['avatar_url'] as String?,
                      initials: _posterInitial(widget.card),
                      seed: poster['user_id'] as String?,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 14.5,
                                color: zt.textPrimary,
                              ),
                              children: [
                                TextSpan(
                                  text: appCardPosterName(widget.card),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (poster['human_verified'] == true)
                                  verifiedBadgeSpan(),
                                const TextSpan(text: ' on '),
                                TextSpan(
                                  text: appName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatRelativeTime(appCardTime(widget.card)),
                            style: ZendTextStyles.caption.copyWith(
                              color: zt.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // The app's own card, drawn by core, inside this item rather than as its own box.
                Padding(
                  padding: const EdgeInsets.only(left: 62),
                  child: ZAppCard(card: widget.card, inBubble: true),
                ),
                const SizedBox(height: 10),
                _ReactionRow(
                  reactions: _reactions,
                  total: total,
                  comments: _comments,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({
    required this.reactions,
    required this.total,
    required this.comments,
  });

  final List<EdgeReactionCount> reactions;
  final int total;
  final int comments;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Row(
      children: [
        if (total == 0)
          Icon(
            PhosphorIconsRegular.smileyWink,
            size: 16,
            color: zt.textSecondary,
            semanticLabel: 'No reactions yet',
          )
        else
          for (final r in reactions.take(3))
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: r.reactedByMe ? zt.accent : (zt.isDark ? zt.bgElevated : zt.bgSecondary),
                  borderRadius: BorderRadius.circular(ZendRadii.chip),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: r.emoji,
                        style: ZendTextStyles.emoji.copyWith(fontSize: 13),
                      ),
                      TextSpan(text: ' ${r.count}'),
                    ],
                  ),
                  style: ZendTextStyles.micro.copyWith(
                    color: r.reactedByMe ? zt.onAccent : zt.textPrimary,
                  ),
                ),
              ),
            ),
        const SizedBox(width: 14),
        Icon(
          comments > 0
              ? PhosphorIconsFill.chatCircle
              : PhosphorIconsRegular.chatCircle,
          size: 15,
          color: comments > 0
              ? zt.accent
              : zt.textSecondary.withValues(alpha: 0.6),
        ),
        if (comments > 0) ...[
          const SizedBox(width: 4),
          Text(
            '$comments',
            style: ZendTextStyles.tabularNumeric.copyWith(
              fontSize: 12,
              color: zt.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
