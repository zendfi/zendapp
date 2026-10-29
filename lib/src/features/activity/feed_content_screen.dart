import 'package:flutter/material.dart';

import 'dart:async';

import '../../core/zend_selector.dart';
import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../design/zend_money.dart';
import '../../design/zend_mark.dart';
import '../../design/zend_motion_widgets.dart';
import '../../services/zend_analytics.dart';
import '../send/qr_scanner_screen.dart';
import '../../models/activity_edge.dart';
import '../../navigation/zend_routes.dart';
import '../dm/dm_thread_screen.dart';
import '../shell/zend_entry_sheet.dart';
import 'activity_comment_sheet.dart';
import 'activity_grouping.dart';
import 'activity_receipt_builder.dart';
import 'transaction_receipt_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/zend_format.dart';
import '../../models/handle_label.dart';
import '../../design/zend_gif.dart';

/// Formats a balance for the restrained header gateway — plain dollars,
/// 2dp only when needed.
String _formatBalance(double balance) => formatUsd(balance);

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
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _listScrollController = ScrollController();

  // Morph the full search bar into a compact pill once the list has
  // scrolled past this offset — the bar starts fully formed (spec-styled
  // like Chats' search bar) at rest, then collapses down to an icon
  // alongside the balance as the user scrolls into the feed.
  static const _collapseAbove = 180.0;
  static const _expandBelow = 120.0;
  bool _collapsed = false;
  bool _searchOpen = false;

  // ── Derived feed state, computed off the build path ────────────────────
  //
  // Sorting the whole edge list and then filtering it used to happen inside
  // build(). That made every rebuild O(n log n) + O(n) with a string
  // allocation per edge — and this widget rebuilds on *every*
  // notifyListeners() from the app model (an SSE transfer alone fans out
  // into several), plus on every keystroke and every scroll-morph toggle.
  //
  // Split by what actually invalidates each one:
  //   * [_sortedEdges] depends only on model data → recomputed in
  //     didChangeDependencies, which InheritedNotifier fires exactly once
  //     per notify.
  //   * [_visibleEdges] depends on data *and* the query → recomputed on
  //     either, so a keystroke re-filters without re-sorting.
  // build() now just reads them.
  List<ActivityEdge> _sortedEdges = const [];
  List<ActivityEdge> _visibleEdges = const [];

  // The viewer's own initial and avatar, resolved here and handed to every
  // card. Previously each card read these from the app model itself, which
  // subscribed every visible card to it — see [_FeedActivityCard]'s doc.
  String _selfInitial = 'Y';
  String? _selfAvatarUrl;

  /// The model's edge list as of the last recompute, compared by identity to
  /// skip redundant work — see [_rebuildSortedEdges].
  List<ActivityEdge>? _lastSourceEdges;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = ZendScope.of(context);
      model.fetchHistory();
      model.fetchThreadedActivity();
    });
    _searchController.addListener(_onQueryChanged);
    _listScrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildSortedEdges();
  }

  void _onQueryChanged() {
    final next = _searchController.text.toLowerCase().trim();
    if (next == _searchQuery) return;
    setState(() {
      _searchQuery = next;
      _applyFilter();
    });
  }

  /// Flat, mixed, reverse-chronological — spec §6.2 priority (private
  /// involving the viewer, then public-to-mutual) is expressed as a natural
  /// consequence of sorting by recency across both sets, not a rigid
  /// two-section split. Nothing here re-filters by visibility; that's
  /// already been decided server-side before this list arrives.
  void _rebuildSortedEdges() {
    final model = ZendScope.of(context);
    final source = model.threadedActivityEdges;

    final nextSelfInitial = model.selfInitial;
    final nextSelfAvatarUrl = model.currentAvatarUrl;
    final viewerChanged =
        nextSelfInitial != _selfInitial || nextSelfAvatarUrl != _selfAvatarUrl;

    // Bail out when nothing this screen renders has actually changed.
    //
    // This runs on every notifyListeners(), and without the guard it re-sorted
    // the entire edge list and allocated a fresh one every time — which also
    // defeats the ZendSelector around the card list below, since a brand-new
    // list instance always compares unequal. ZendAppModel assigns a *new* list
    // whenever activity data changes (`threadedActivityEdges = response.edges`
    // / `[...existing, ...new]`) and never mutates it in place, so identity is
    // a sound change signal here.
    if (identical(source, _lastSourceEdges) && !viewerChanged) return;

    _lastSourceEdges = source;
    _selfInitial = nextSelfInitial;
    _selfAvatarUrl = nextSelfAvatarUrl;

    _sortedEdges = List<ActivityEdge>.of(source)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _applyFilter();
  }

  void _applyFilter() {
    final q = _searchQuery;
    if (q.isEmpty) {
      // Share the list rather than copying it — nothing mutates it.
      _visibleEdges = _sortedEdges;
      return;
    }
    _visibleEdges = _sortedEdges.where((e) {
      final label = e.isDirectParticipant
          ? e.counterparty.displayLabel.toLowerCase()
          : '';
      final sender = (e.senderZendtag ?? '').toLowerCase();
      final recipient = (e.recipientZendtag ?? '').toLowerCase();
      final note = (e.note ?? '').toLowerCase();
      return label.contains(q) ||
          sender.contains(q) ||
          recipient.contains(q) ||
          note.contains(q);
    }).toList();
  }

  void _onScroll() {
    if (!_listScrollController.hasClients) return;
    final offset = _listScrollController.offset;
    // Hysteresis: collapse once the hero is mostly off-screen, expand only
    // after scrolling clearly back, so hovering at the edge can't flicker.
    final next = _collapsed ? offset > _expandBelow : offset > _collapseAbove;
    if (next != _collapsed) setState(() => _collapsed = next);
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _searchFocus.requestFocus(),
      );
    } else {
      _searchController.clear();
      _searchFocus.unfocus();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _listScrollController.removeListener(_onScroll);
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _openDm(ActivityCounterparty counterparty) async {
    final model = ZendScope.of(context);
    final zendtag = counterparty.displayLabel.replaceFirst('@', '');
    final cached = model.dmService.cachedThreads
        .where(
          (t) => t.counterparty.zendtag.toLowerCase() == zendtag.toLowerCase(),
        )
        .firstOrNull;
    if (cached != null) {
      pushZendSlide(
        context,
        DmThreadScreen(
          roomId: cached.roomId,
          counterparty: cached.counterparty,
        ),
      );
      return;
    }
    try {
      final result = await model.dmService.getOrCreateRoom(counterparty.id);
      // `mounted` on the State, which is what actually governs whether
      // `context` is still usable here. (Was an `// ignore:` comment that
      // dart format displaced onto an inner argument, where it silently
      // stopped suppressing anything.)
      if (!mounted) return;
      pushZendSlide(
        context,
        DmThreadScreen(
          roomId: result.roomId,
          counterparty: result.counterparty,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't open this chat — try again",
              style: TextStyle(fontFamily: 'Geist'),
            ),
          ),
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
        headline = isOutgoing
            ? 'You sent a Vibe ✨ to ${counterparty.displayLabel}'
            : '✨ Vibe from ${counterparty.displayLabel}';
      } else if (isPoolContrib) {
        headline = isOutgoing
            ? 'You contributed to ${counterparty.displayLabel}'
            : '${counterparty.displayLabel} contributed';
      } else {
        final verb = feedVerbFor(edge);
        headline = isOutgoing
            ? 'You $verb ${counterparty.displayLabel}'
            : '${counterparty.displayLabel} $verb';
      }
      final selfInitial = model.selfInitial;
      avatarInitial = isOutgoing ? selfInitial : counterparty.initialLetter;
      avatarUrl = isOutgoing ? model.currentAvatarUrl : counterparty.avatarUrl;
    } else {
      // External (public-to-Mutual) edge — neither party is the viewer.
      final senderTag = edge.senderZendtag;
      final recipientTag = edge.recipientZendtag;
      final senderLabel = senderTag != null && senderTag.isNotEmpty
          ? handleLabel(senderTag)
          : 'Someone';
      final recipientLabel = recipientTag != null && recipientTag.isNotEmpty
          ? handleLabel(recipientTag)
          : 'someone';
      final verb = feedVerbFor(edge);
      headline = isVibe
          ? '$senderLabel sent a Vibe ✨ to $recipientLabel'
          : isPoolContrib
          ? '$senderLabel contributed to a pool'
          : '$senderLabel $verb $recipientLabel';
      avatarInitial = senderTag?.isNotEmpty == true
          ? senderTag![0].toUpperCase()
          : '?';
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
        const SnackBar(
          content: Text(
            'Details for this activity are not available',
            style: TextStyle(fontFamily: 'Geist'),
          ),
        ),
      );
      return;
    }
    final tx = zendTransactionFromEdge(
      edge,
      entry,
      avatarLabel: edge.counterparty.initialLetter,
      avatarUrl: edge.counterparty.avatarUrl,
    );
    ZendAnalytics.track(ZendEvent.receiptOpened);
    showTransactionReceipt(context, tx: tx);
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

    // Both lists are derived off the build path — see the fields' doc.
    final allEdges = _sortedEdges;
    final edges = _visibleEdges;

    final isLoading = model.threadedActivityLoading && allEdges.isEmpty;
    final isNewUser =
        !isLoading && allEdges.isEmpty && model.sendableBalance == 0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header — no "Activities" heading. At rest: a fully-formed
            // search bar (same styling as Chats' search pill). Once the
            // feed scrolls past a small threshold, it morphs into a
            // compact search icon sitting in a pill alongside the balance —
            // spec §5's "search should blend into the interface rather
            // than become a dominant module" holds at both ends of that
            // morph, just expressed differently once there's content to
            // scroll past.
            // Fixed-height bar: it never changes size, so scrolling can't
            // resize the list underneath it. The compact balance only fades
            // in once the hero (which scrolls with the feed) is gone.
            _FeedTopBar(
              collapsed: _collapsed,
              searchOpen: _searchOpen,
              balanceLabel: model.balanceHidden
                  ? '•••'
                  : _formatBalance(model.sendableBalance),
              onOpenWallet: widget.onOpenWallet,
              onToggleSearch: _toggleSearch,
            ),
            if (_searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  style: ZendTextStyles.body.copyWith(color: zt.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search activity',
                    prefixIcon: Icon(
                      PhosphorIconsRegular.magnifyingGlass,
                      size: 18,
                      color: zt.textSecondary,
                    ),
                    filled: true,
                    fillColor: zt.bgCard,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ZendRadii.pill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

            // ── Content ──
            Expanded(
              child: ZendRefresh(
                onRefresh: () => model.fetchThreadedActivity(),
                child: isLoading
                    ? const ActivityFeedSkeleton()
                    : isNewUser || edges.isEmpty
                    ? ListView(
                        controller: _listScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        children: [
                          if (!_searchOpen)
                            _BalanceHero(
                              balance: model.sendableBalance,
                              hidden: model.balanceHidden,
                              onOpenWallet: widget.onOpenWallet,
                            ),
                          SizedBox(
                            height: 320,
                            child: isNewUser
                                ? _buildNewUserState(zt)
                                : _buildEmptyOrNoMatch(zt),
                          ),
                        ],
                      )
                    // The card list is the expensive part of this
                    // screen, and it depends on exactly one thing:
                    // which edges are visible. Selecting on the list's
                    // identity means an unrelated notify (a balance
                    // refresh, an incoming DM, the transfer poll) no
                    // longer rebuilds every visible card to produce
                    // the same output. `_applyFilter` assigns a new
                    // list only when the data or the query actually
                    // changed, which is what makes identity the right
                    // signal here.
                    : ZendSelector<List<ActivityEdge>>(
                        selector: (_) => _visibleEdges,
                        builder: (context, visible, _) => ListView.builder(
                          controller: _listScrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          // Slot 0 is the hero; it scrolls away naturally.
                          itemCount: visible.length + 1,
                          itemBuilder: (context, slot) {
                            if (slot == 0) {
                              return _searchOpen
                                  ? const SizedBox(height: 4)
                                  : _BalanceHero(
                                      balance: model.sendableBalance,
                                      hidden: model.balanceHidden,
                                      onOpenWallet: widget.onOpenWallet,
                                    );
                            }
                            final i = slot - 1;
                            final edge = visible[i];
                            final day = formatDayGroup(edge.createdAt);
                            final showDay =
                                i == 0 ||
                                formatDayGroup(visible[i - 1].createdAt) != day;
                            final card = Padding(
                              padding: const EdgeInsets.only(
                                bottom: ZendSpacing.betweenCards,
                              ),
                              // Each card owns an async reaction fetch
                              // that repaints it independently of its
                              // neighbours, so a boundary here stops one
                              // card's count arriving from repainting the
                              // whole visible list.
                              child: RepaintBoundary(
                                child: _FeedActivityCard(
                                  key: ValueKey(edge.edgeId),
                                  edge: edge,
                                  // Passed down rather than read from the
                                  // model inside the card — see
                                  // _FeedActivityCard's doc.
                                  selfInitial: _selfInitial,
                                  selfAvatarUrl: _selfAvatarUrl,
                                  onTap: () => _openActivity(edge),
                                ),
                              ),
                            );
                            if (!showDay) return card;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _DayHeader(day, first: i == 0),
                                card,
                              ],
                            );
                          },
                        ),
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
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    color: zt.textSecondary,
                  ),
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
            const ZendMark(size: 72),
            const SizedBox(height: 20),
            Text(
              'Nothing here yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Send your first Zend: pick a person, an amount and an emoji.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 14,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Zend',
              onPressed: () => showZendEntrySheet(context),
            ),
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
    return Center(
      child: Text(
        'No matches for "$_searchQuery"',
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 14,
          color: zt.textSecondary,
        ),
      ),
    );
  }
}

/// The balance as the hero, with Zend and Scan beneath it. Lives inside
/// the feed's scroll view so it scrolls away with the content.
class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.balance,
    required this.hidden,
    required this.onOpenWallet,
  });

  final double balance;
  final bool hidden;
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: 'Balance, open wallet',
            child: GestureDetector(
              onTap: onOpenWallet,
              behavior: HitTestBehavior.opaque,
              child: ZendGlow(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        'Balance',
                        style: ZendTextStyles.caption.copyWith(
                          color: zt.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ZendRollingAmount(balance, hidden: hidden),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Zend',
                  onPressed: () => showZendEntrySheet(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlineActionButton(
                  label: 'Scan',
                  onPressed: () =>
                      pushZendSlide(context, const QrScannerScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fixed 52px bar: brand, a compact balance that fades in once the hero has
/// scrolled away, and search. Its size never changes.
class _FeedTopBar extends StatelessWidget {
  const _FeedTopBar({
    required this.collapsed,
    required this.searchOpen,
    required this.balanceLabel,
    required this.onOpenWallet,
    required this.onToggleSearch,
  });

  final bool collapsed;
  final bool searchOpen;
  final String balanceLabel;
  final VoidCallback onOpenWallet;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final showBalance = collapsed || searchOpen;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
        child: Row(
          children: [
            Text(
              'Zend!',
              style: ZendTextStyles.title.copyWith(
                fontWeight: FontWeight.w700,
                color: zt.textPrimary,
              ),
            ),
            const Spacer(),
            IgnorePointer(
              ignoring: !showBalance,
              child: AnimatedOpacity(
                opacity: showBalance ? 1 : 0,
                duration: ZendMotion.quick,
                child: AnimatedSlide(
                  offset: showBalance ? Offset.zero : const Offset(0, 0.3),
                  duration: ZendMotion.quick,
                  curve: ZendMotion.springSnappy,
                  child: GestureDetector(
                    onTap: onOpenWallet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: zt.bgCard,
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                      child: Text(
                        balanceLabel,
                        style: ZendTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: zt.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: searchOpen ? 'Close search' : 'Search activity',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(
                searchOpen
                    ? PhosphorIconsRegular.x
                    : PhosphorIconsRegular.magnifyingGlass,
                size: 20,
                color: zt.textSecondary,
              ),
              onPressed: onToggleSearch,
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label, {required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 8 : 16, bottom: 8, left: 4),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: ZendTextStyles.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: zt.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A single Feed card — spec §5's wireframe: avatar, sentence headline,
/// optional note, amount (private edges always; public-to-Mutual edges
/// only when the sharer chose the amount-visible preset — reflects
/// `edge.amountHidden` exactly as the server computed it, no client-side
/// re-deciding), and a reaction count. No privacy badge — per spec §6.4,
/// the pronoun ("You" vs a name) already communicates who this is between.
/// ── Deliberately has no ZendScope dependency ────────────────────────────
/// This card used to call `ZendScope.of(context)` in its own `build`, purely
/// to read three scalars about the viewer. Because each card is its own
/// element, that registered a dependency on the whole app model *per card* —
/// so every `notifyListeners()` (an SSE transfer fans out into several)
/// dirtied every card on screen, to render values that hadn't changed.
///
/// The viewer's initials and avatar are now resolved once by the parent and
/// passed in, which makes this card a pure function of its inputs.
class _FeedActivityCard extends StatefulWidget {
  const _FeedActivityCard({
    super.key,
    required this.edge,
    required this.selfInitial,
    required this.selfAvatarUrl,
    required this.onTap,
  });

  final ActivityEdge edge;

  /// The viewer's own initial and avatar, for the outgoing case where the
  /// card shows *them* rather than the counterparty.
  final String selfInitial;
  final String? selfAvatarUrl;

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

  /// Cards that fly past during a fast scroll are built and disposed within a
  /// few frames. Waiting this long before asking the network means they cost
  /// nothing at all — only cards the user actually comes to rest on fetch.
  static const _fetchSettleDelay = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    unawaited(_loadReactions());
  }

  Future<void> _loadReactions() async {
    // `read`, not `of`: this runs from initState, where registering an
    // inherited-widget dependency is illegal (it throws in debug and quietly
    // subscribes this card to the whole app model in release).
    final model = ZendScope.read(context);

    await Future<void>.delayed(_fetchSettleDelay);
    if (!mounted) return; // scrolled past — never worth a request

    try {
      // Shared, deduped and short-lived TTL cache, so scrolling back over a
      // card the user already saw costs nothing. See ActivityDataService.
      final reactions = await model.activityDataService.getEdgeReactions(
        _edgeKindStr,
        widget.edge.edgeId,
      );
      if (mounted) setState(() => _reactions = reactions);
    } catch (_) {
      // Non-fatal — card renders without a reaction count.
    }
  }

  String _relativeTime(DateTime dt) => formatRelativeTime(dt);

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final edge = widget.edge;
    final isDirect = edge.isDirectParticipant;
    final isOutgoing = edge.isOutgoing;
    final isVibe = isVibeEdge(edge);
    final isPoolContrib = edge.edgeKind == ActivityEdgeKind.poolContribution;
    final emojiNote = isEmojiNote(edge.note) ? edge.note!.trim() : null;
    final totalReactions = _reactions.fold<int>(0, (sum, r) => sum + r.count);

    late final String avatarInitial;
    late final String? avatarUrl;
    late final Widget headline;

    if (isDirect) {
      final counterparty = edge.counterparty;
      avatarInitial = isOutgoing
          ? widget.selfInitial
          : counterparty.initialLetter;
      avatarUrl = isOutgoing ? widget.selfAvatarUrl : counterparty.avatarUrl;

      final verb = feedVerbFor(edge);
      final subject = counterparty.displayLabel;
      headline = RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 14.5,
            color: zt.textPrimary,
          ),
          children: isVibe
              ? [
                  TextSpan(
                    text: isOutgoing ? 'You sent a Vibe ✨ to ' : '✨ Vibe from ',
                  ),
                  TextSpan(
                    text: subject,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ]
              : isPoolContrib
              ? [
                  TextSpan(text: isOutgoing ? 'You contributed to ' : ''),
                  TextSpan(
                    text: subject,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: isOutgoing ? '' : ' contributed to a pool'),
                ]
              : [
                  TextSpan(text: isOutgoing ? 'You $verb ' : ''),
                  TextSpan(
                    text: subject,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: isOutgoing ? '' : ' $verb'),
                ],
        ),
      );
    } else {
      // Public-to-Mutual — presence of a name that isn't "you" already
      // signals this is someone else's shared activity (spec §6.4).
      final senderTag = edge.senderZendtag;
      final recipientTag = edge.recipientZendtag;
      final senderLabel = senderTag != null && senderTag.isNotEmpty
          ? handleLabel(senderTag)
          : 'Someone';
      final recipientLabel = recipientTag != null && recipientTag.isNotEmpty
          ? handleLabel(recipientTag)
          : 'someone';
      avatarInitial = senderTag?.isNotEmpty == true
          ? senderTag![0].toUpperCase()
          : '?';
      avatarUrl = edge.senderAvatarUrl;
      final verb = feedVerbFor(edge);
      headline = RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 14.5,
            color: zt.textPrimary,
          ),
          children: isVibe
              ? [
                  TextSpan(
                    text: senderLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' sent a Vibe ✨ to '),
                  TextSpan(
                    text: recipientLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ]
              : isPoolContrib
              ? [
                  TextSpan(
                    text: senderLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' contributed to a pool'),
                ]
              : [
                  TextSpan(
                    text: senderLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' $verb '),
                  TextSpan(
                    text: recipientLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
        ),
      );
    }

    return ZendPressScale(
      child: Material(
        color: zt.bgCard,
        borderRadius: BorderRadius.circular(ZendRadii.card),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(ZendRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  // Centred, not top-aligned: at radius 26 the avatar is taller
                  // than the headline + timestamp beside it, so start-alignment
                  // would pin the text to the avatar's top edge and leave a gap
                  // under it. Matches the chat tile.
                  children: [
                    ZendAvatar(
                      radius: 24,
                      photoUrl: avatarUrl,
                      initials: avatarInitial,
                      seed: isDirect && !isOutgoing
                          ? edge.counterparty.id
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          headline,
                          const SizedBox(height: 2),
                          Text(
                            _relativeTime(edge.createdAt),
                            style: ZendTextStyles.caption.copyWith(
                              color: zt.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (gifIdFromNote(edge.note) != null && !isVibe) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 62),
                    child: ZendGifTile(gifIdFromNote(edge.note)!),
                  ),
                ] else if (emojiNote != null && !isVibe) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 62),
                    child: ZendEmojiTile(
                      emojiNote,
                      burst:
                          !isOutgoing &&
                          DateTime.now().difference(edge.createdAt).inMinutes <
                              5,
                    ),
                  ),
                ] else if (edge.note?.isNotEmpty == true &&
                    !isVibe &&
                    !isMediaNote(edge.note)) ...[
                  const SizedBox(height: 8),
                  Text(
                    edge.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 14,
                      height: 1.3,
                      color: zt.textPrimary.withValues(alpha: 0.88),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    // One reaction system: the same emoji set as the Activity
                    // sheet, shown as counts. Tapping opens the sheet to react.
                    if (totalReactions == 0)
                      Icon(
                        PhosphorIconsRegular.smileyWink,
                        size: 16,
                        color: zt.textSecondary,
                        semanticLabel: 'No reactions yet',
                      )
                    else
                      for (final r in _reactions.take(3))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: r.reactedByMe
                                  ? zt.accentPop
                                  : zt.bgElevated,
                              borderRadius: BorderRadius.circular(
                                ZendRadii.chip,
                              ),
                            ),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: r.emoji,
                                    style: ZendTextStyles.emoji.copyWith(
                                      fontSize: 13,
                                    ),
                                  ),
                                  TextSpan(text: ' ${r.count}'),
                                ],
                              ),
                              style: ZendTextStyles.micro.copyWith(
                                color: zt.textPrimary,
                              ),
                            ),
                          ),
                        ),
                    // Comment indicator, mirroring the reaction one: filled with
                    // the accent when there is something to read, outlined and
                    // muted when there is not. Shown even at zero so the row
                    // advertises that commenting is possible — the same reason
                    // the heart is always present.
                    const SizedBox(width: 14),
                    Icon(
                      edge.commentCount > 0
                          ? PhosphorIconsFill.chatCircle
                          : PhosphorIconsRegular.chatCircle,
                      size: 15,
                      color: edge.commentCount > 0
                          ? zt.accent
                          : zt.textSecondary.withValues(alpha: 0.6),
                    ),
                    if (edge.commentCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${edge.commentCount}',
                        style: ZendTextStyles.tabularNumeric.copyWith(
                          fontSize: 12,
                          color: zt.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
