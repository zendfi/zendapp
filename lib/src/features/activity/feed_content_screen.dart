import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import '../../navigation/zend_routes.dart';
import '../dm/dm_thread_screen.dart';
import '../shell/zend_entry_sheet.dart';
import 'activity_comment_sheet.dart';
import 'activity_grouping.dart';
import 'activity_receipt_builder.dart';
import 'transaction_receipt_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Formats a balance for the restrained header gateway — plain dollars,
/// 2dp only when needed.
String _formatBalance(double balance) {
  if (balance == balance.roundToDouble()) {
    return '\$${balance.toStringAsFixed(0)}';
  }
  return '\$${balance.toStringAsFixed(2)}';
}

/// Feed — ZEND BETA spec §5-7, §21-24: a single flat, reverse-chronological
/// timeline mixing the viewer's own private Activities with the
/// public-to-Mutual Activities their mutuals have chosen to share.
/// Answers "what's happening between me and my people?" — deliberately
/// NOT a per-counterparty threaded/grouped view (that's
/// [ThreadedActivityScreen], still reachable but no longer the default
/// mental model) and NOT a balance-first dashboard.
///
/// Data source is unchanged: `ZendAppModel.threadedActivityEdges`, already
/// populated with both direct-participant and Shared_Network-authorized
/// external edges by `fetchThreadedActivity()`. This screen's only job is
/// to render that same authorized data as one flat feed instead of
/// grouping it by counterparty — no new authorization logic, per spec §66
/// ("the backend must enforce this, not merely the UI").
class FeedContentScreen extends StatefulWidget {
  const FeedContentScreen({super.key, required this.onOpenWallet});

  final VoidCallback onOpenWallet;

  @override
  State<FeedContentScreen> createState() => _FeedContentScreenState();
}

class _FeedContentScreenState extends State<FeedContentScreen> {
  bool _searchActive = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = ZendScope.of(context);
      model.fetchHistory();
      model.fetchThreadedActivity();
    });
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _searchController.clear();
        _searchFocus.unfocus();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
      }
    });
  }

  Future<void> _openDm(ActivityCounterparty counterparty) async {
    final model = ZendScope.of(context);
    final zendtag = counterparty.displayLabel.replaceFirst('@', '');
    final cached = model.dmService.cachedThreads
        .where((t) => t.counterparty.zendtag.toLowerCase() == zendtag.toLowerCase())
        .firstOrNull;
    if (cached != null) {
      pushZendSlide(context, DmThreadScreen(roomId: cached.roomId, counterparty: cached.counterparty));
      return;
    }
    try {
      final result = await model.dmService.getOrCreateRoom(counterparty.id);
      if (!context.mounted) return;
      pushZendSlide(context, DmThreadScreen( // ignore: use_build_context_synchronously
        roomId: result.roomId,
        counterparty: result.counterparty,
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open this chat — try again", style: TextStyle(fontFamily: 'Geist'))),
        );
      }
    }
  }

  void _openActivity(ActivityEdge edge) {
    final model = ZendScope.of(context);
    final isDirect = edge.isDirectParticipant;
    final isOutgoing = edge.isOutgoing;
    final isVibe = isVibeEdge(edge);
    final isPoolContrib = edge.edgeKind == ActivityEdgeKind.poolContribution;

    // Build the headline + avatar identically for direct and external
    // edges, and figure out which party (if any) the chat icon should open.
    final String headline;
    ActivityCounterparty? chatTarget;
    String avatarInitial;
    String? avatarUrl;

    if (isDirect) {
      final counterparty = edge.counterparty;
      chatTarget = counterparty;
      if (isVibe) {
        headline = isOutgoing ? 'You sent a Vibe ✨ to ${counterparty.displayLabel}' : '✨ Vibe from ${counterparty.displayLabel}';
      } else if (isPoolContrib) {
        headline = isOutgoing ? 'You contributed to ${counterparty.displayLabel}' : '${counterparty.displayLabel} contributed';
      } else {
        final verb = feedVerbFor(edge);
        headline = isOutgoing ? 'You $verb ${counterparty.displayLabel}' : '${counterparty.displayLabel} $verb you';
      }
      final selfInitial = model.currentZendtag?.isNotEmpty == true
          ? model.currentZendtag![0].toUpperCase()
          : (model.currentDisplayName?.isNotEmpty == true ? model.currentDisplayName![0].toUpperCase() : 'Y');
      avatarInitial = isOutgoing ? selfInitial : counterparty.initialLetter;
      avatarUrl = isOutgoing ? model.currentAvatarUrl : counterparty.avatarUrl;
    } else {
      // External (public-to-Mutual) edge — neither party is the viewer.
      final senderTag = edge.senderZendtag;
      final recipientTag = edge.recipientZendtag;
      final senderLabel = senderTag != null && senderTag.isNotEmpty ? '@$senderTag' : 'Someone';
      final recipientLabel = recipientTag != null && recipientTag.isNotEmpty ? '@$recipientTag' : 'someone';
      final verb = feedVerbFor(edge);
      headline = isVibe
          ? '$senderLabel sent a Vibe ✨ to $recipientLabel'
          : isPoolContrib
              ? '$senderLabel contributed to a pool'
              : '$senderLabel $verb $recipientLabel';
      avatarInitial = senderTag?.isNotEmpty == true ? senderTag![0].toUpperCase() : '?';
      avatarUrl = edge.senderAvatarUrl;
      // No single "the other person" to chat with on an external edge
      // (spec §21's chat shortcut only makes sense between the viewer and
      // one counterparty) — chatTarget stays null and the sheet hides the
      // chat icon in that case.
    }

    showActivityCommentSheet(
      context,
      edge: edge,
      headline: headline,
      avatarUrl: avatarUrl,
      avatarInitial: avatarInitial,
      onViewReceipt: () => _openReceipt(edge),
      onOpenChat: chatTarget != null ? () => _openDm(chatTarget!) : null,
    );
  }

  void _openReceipt(ActivityEdge edge) {
    final model = ZendScope.of(context);
    final entry = entryFromEdgeForViewer(edge, model);
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Details for this activity are not available', style: TextStyle(fontFamily: 'Geist'))),
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
    final model = ZendScope.of(context);

    // Flat, mixed, reverse-chronological — spec §6.2 priority (private
    // involving the viewer, then public-to-mutual) is expressed as a
    // natural consequence of sorting by recency across both sets, not a
    // rigid two-section split; nothing here re-filters by visibility,
    // that's already been decided server-side before this list arrives.
    final allEdges = List<ActivityEdge>.of(model.threadedActivityEdges)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final edges = _searchQuery.isEmpty
        ? allEdges
        : allEdges.where((e) {
            final label = e.isDirectParticipant ? e.counterparty.displayLabel.toLowerCase() : '';
            final sender = (e.senderZendtag ?? '').toLowerCase();
            final recipient = (e.recipientZendtag ?? '').toLowerCase();
            final note = (e.note ?? '').toLowerCase();
            return label.contains(_searchQuery) ||
                sender.contains(_searchQuery) ||
                recipient.contains(_searchQuery) ||
                note.contains(_searchQuery);
          }).toList();

    final isLoading = model.threadedActivityLoading && allEdges.isEmpty;
    final isNewUser = !isLoading && allEdges.isEmpty && model.spendableBalance == 0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header — "Activities" + restrained balance gateway ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Activities',
                      style: TextStyle(fontFamily: 'Geist', fontSize: 26, fontWeight: FontWeight.w700, color: zt.textPrimary),
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onOpenWallet,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Text(
                        model.balanceHidden ? '•••' : _formatBalance(model.spendableBalance),
                        style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w500, color: zt.textSecondary),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _toggleSearch,
                    icon: Icon(
                      _searchActive ? PhosphorIconsRegular.magnifyingGlassMinus : PhosphorIconsRegular.magnifyingGlass,
                      color: _searchActive ? zt.accent : zt.textSecondary,
                    ),
                    tooltip: _searchActive ? 'Close search' : 'Search',
                  ),
                ],
              ),
            ),

            // ── Search — blends in, no dominant search module (spec §5) ──
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _searchActive
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
                          filled: true,
                          fillColor: zt.bgSecondary,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(ZendRadii.pill),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? GestureDetector(
                                  onTap: () => _searchController.clear(),
                                  child: Icon(PhosphorIconsRegular.xCircle, size: 18, color: zt.textSecondary),
                                )
                              : null,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Content ──
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => model.fetchThreadedActivity(),
                child: isLoading
                    ? const ActivityFeedSkeleton()
                    : isNewUser
                        ? _buildNewUserState(zt)
                        : edges.isEmpty
                            ? _buildEmptyOrNoMatch(zt)
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                itemCount: edges.length,
                                itemBuilder: (context, i) {
                                  final edge = edges[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _FeedActivityCard(
                                      key: ValueKey(edge.edgeId),
                                      edge: edge,
                                      onTap: () => _openActivity(edge),
                                    ),
                                  );
                                },
                              ),
              ),
            ),
            // Network failure — existing content stays, no full-screen
            // takeover (spec §62): only a small inline notice.
            if (model.lastThreadedActivityError != null && allEdges.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  "Couldn't refresh Activities. Try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewUserState(ZendTheme zt) {
    // Spec §6.1 — no onboarding clutter, one line + one action.
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nothing here yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w600, color: zt.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Zend someone to get things started.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Zend', onPressed: () => showZendEntrySheet(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyOrNoMatch(ZendTheme zt) {
    // Spec §6.3 — the feed simply ends; no "you're all caught up" copy for
    // a returning user with existing history but no new activity right now.
    // A search with no matches is the one case that does get a short line,
    // since silence there reads as broken rather than "caught up".
    if (_searchQuery.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 200,
          child: Center(
            child: Text(
              'No matches for "$_searchQuery"',
              style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single Feed card — spec §5's wireframe: avatar, sentence headline,
/// optional note, amount (private edges always; public-to-Mutual edges
/// only when the sharer chose the amount-visible preset — reflects
/// `edge.amountHidden` exactly as the server computed it, no client-side
/// re-deciding), and a reaction count. No privacy badge — per spec §6.4,
/// the pronoun ("You" vs a name) already communicates who this is between.
class _FeedActivityCard extends StatefulWidget {
  const _FeedActivityCard({super.key, required this.edge, required this.onTap});

  final ActivityEdge edge;
  final VoidCallback onTap;

  @override
  State<_FeedActivityCard> createState() => _FeedActivityCardState();
}

class _FeedActivityCardState extends State<_FeedActivityCard> {
  List<EdgeReactionCount> _reactions = const [];

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
    _loadReactions();
  }

  Future<void> _loadReactions() async {
    final model = ZendScope.of(context);
    try {
      final reactions = await model.activityDataService.getEdgeReactions(_edgeKindStr, widget.edge.edgeId);
      if (mounted) setState(() => _reactions = reactions);
    } catch (_) {
      // Non-fatal — card renders without a reaction count.
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
    final isDirect = edge.isDirectParticipant;
    final isOutgoing = edge.isOutgoing;
    final isVibe = isVibeEdge(edge);
    final isPoolContrib = edge.edgeKind == ActivityEdgeKind.poolContribution;
    final showAmount = !edge.amountHidden && edge.amountUsdc != null;
    final amountLabel = '\$${edge.amountUsdc ?? '0'}';
    final totalReactions = _reactions.fold<int>(0, (sum, r) => sum + r.count);

    late final String avatarInitial;
    late final String? avatarUrl;
    late final Widget headline;

    if (isDirect) {
      final counterparty = edge.counterparty;
      final selfInitial = model.currentZendtag?.isNotEmpty == true
          ? model.currentZendtag![0].toUpperCase()
          : (model.currentDisplayName?.isNotEmpty == true ? model.currentDisplayName![0].toUpperCase() : 'Y');
      avatarInitial = isOutgoing ? selfInitial : counterparty.initialLetter;
      avatarUrl = isOutgoing ? model.currentAvatarUrl : counterparty.avatarUrl;

      final verb = feedVerbFor(edge);
      final subject = counterparty.displayLabel;
      headline = RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: TextStyle(fontFamily: 'Geist', fontSize: 14.5, color: zt.textPrimary),
          children: isVibe
              ? [
                  TextSpan(text: isOutgoing ? 'You sent a Vibe ✨ to ' : '✨ Vibe from '),
                  TextSpan(text: subject, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]
              : isPoolContrib
                  ? [
                      TextSpan(text: isOutgoing ? 'You contributed to ' : ''),
                      TextSpan(text: subject, style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: isOutgoing ? '' : ' contributed to a pool'),
                    ]
                  : [
                      TextSpan(text: isOutgoing ? 'You $verb ' : ''),
                      TextSpan(text: subject, style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: isOutgoing ? '' : ' $verb you'),
                    ],
        ),
      );
    } else {
      // Public-to-Mutual — presence of a name that isn't "you" already
      // signals this is someone else's shared activity (spec §6.4).
      final senderTag = edge.senderZendtag;
      final recipientTag = edge.recipientZendtag;
      final senderLabel = senderTag != null && senderTag.isNotEmpty ? '@$senderTag' : 'Someone';
      final recipientLabel = recipientTag != null && recipientTag.isNotEmpty ? '@$recipientTag' : 'someone';
      avatarInitial = senderTag?.isNotEmpty == true ? senderTag![0].toUpperCase() : '?';
      avatarUrl = edge.senderAvatarUrl;
      final verb = feedVerbFor(edge);
      headline = RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: TextStyle(fontFamily: 'Geist', fontSize: 14.5, color: zt.textPrimary),
          children: isVibe
              ? [
                  TextSpan(text: senderLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' sent a Vibe ✨ to '),
                  TextSpan(text: recipientLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]
              : isPoolContrib
                  ? [
                      TextSpan(text: senderLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' contributed to a pool'),
                    ]
                  : [
                      TextSpan(text: senderLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' $verb '),
                      TextSpan(text: recipientLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
        ),
      );
    }

    return Material(
      color: zt.bgSecondary,
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZendAvatar(radius: 18, photoUrl: avatarUrl, initials: avatarInitial),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        headline,
                        const SizedBox(height: 2),
                        Text(
                          _relativeTime(edge.createdAt),
                          style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 10.5, color: zt.textSecondary.withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                  if (showAmount && !isVibe) ...[
                    const SizedBox(width: 8),
                    Text(
                      amountLabel,
                      style: TextStyle(fontFamily: 'Geist', fontSize: 18, fontWeight: FontWeight.w700, color: zt.textPrimary),
                    ),
                  ],
                ],
              ),
              if (edge.note?.isNotEmpty == true && !isVibe) ...[
                const SizedBox(height: 8),
                Text(
                  edge.note!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Geist', fontSize: 14, height: 1.3, color: zt.textPrimary.withValues(alpha: 0.88)),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    totalReactions > 0 ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                    size: 15,
                    color: totalReactions > 0 ? zt.accent : zt.textSecondary.withValues(alpha: 0.6),
                  ),
                  if (totalReactions > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$totalReactions',
                      style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 12, color: zt.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
