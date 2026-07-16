import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import '../../models/email_intent.dart';
import '../../models/payment_request_item.dart';
import '../../models/qr_payment_intent.dart';
import '../send/qr_payment_sheet.dart';
import 'activity_grouping.dart';
import 'legacy_activity_list_view.dart';
import 'public_feed_screen.dart';
import 'search_screen.dart';
import 'thread_detail_screen.dart';
import '../../navigation/zend_routes.dart';
import 'package:solar_icons/solar_icons.dart';

/// Phase 2 Threaded_Activity_View — groups a User's visible Activity_Edges
/// by Counterparty (Req 11) instead of showing a flat chronological list.
/// Structurally parallel to `legacy_activity_list_view.dart`'s
/// `LegacyActivityListView`, which remains reachable via the view toggle
/// (Req 12).
///
/// Consumes data exclusively from `ZendAppModel.threadedActivityEdges`
/// (populated by `fetchThreadedActivity()`, itself backed by
/// `Activity_Data_Service` — Req 11.5, Req 13) and applies no additional
/// authorization/visibility filtering of its own (Req 13.2).
///
/// Pending email intents, outbound requests, and inbound requests are not
/// Activity_Edges (per design.md's tap-through table) and so are not part
/// of the Counterparty-grouped list; they're rendered in a compact "Pending"
/// section above it, reusing the exact same existing sheets as the Legacy
/// view for tap-through (Req 15.2-15.4).
class ThreadedActivityScreen extends StatefulWidget {
  const ThreadedActivityScreen({
    super.key,
    required this.onToggleView,
    this.onOpenGraphView,
  });

  /// Invoked when the user taps the view-toggle control to switch to the
  /// Legacy_Activity_View.
  final VoidCallback onToggleView;

  /// Invoked when the user taps the opt-in control to switch to the Phase 3
  /// Graph_View (Req 16.5 — reachable only via explicit User action).
  /// Optional so this widget remains usable standalone without requiring a
  /// router that supports the Graph_View mode.
  final VoidCallback? onOpenGraphView;

  @override
  State<ThreadedActivityScreen> createState() => _ThreadedActivityScreenState();
}

class _ThreadedActivityScreenState extends State<ThreadedActivityScreen> {
  bool _notificationsMuted = false;
  bool _filterActive = false;
  String _filterQuery = '';
  final TextEditingController _filterController = TextEditingController();
  final FocusNode _filterFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = ZendScope.of(context);
      // fetchHistory() is untouched (Req 22.4) but also populates
      // pendingEmailIntents/outboundPaymentRequests/inboundPaymentRequests,
      // which this screen's "Pending" section reuses for tap-through data —
      // exactly like LegacyActivityListView already does.
      model.fetchHistory();
      model.fetchThreadedActivity();
    });
    _loadMutePreference();
    _filterController.addListener(() {
      setState(() => _filterQuery = _filterController.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  void _toggleFilter() {
    setState(() {
      _filterActive = !_filterActive;
      if (!_filterActive) {
        _filterController.clear();
        _filterFocus.unfocus();
      } else {
        // Give the field a frame to mount before requesting focus.
        WidgetsBinding.instance.addPostFrameCallback((_) => _filterFocus.requestFocus());
      }
    });
  }

  Future<void> _loadMutePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _notificationsMuted = prefs.getBool('notifications_muted') ?? false);
    }
  }

  Future<void> _toggleNotificationMute() async {
    final prefs = await SharedPreferences.getInstance();
    final newValue = !_notificationsMuted;
    await prefs.setBool('notifications_muted', newValue);
    setState(() => _notificationsMuted = newValue);
  }

  // ── Tap-through routing (Req 15) ────────────────────────────────────────
  //
  // Tapping a User thread opens the Twitter-feed-style thread detail screen
  // (every activity with that person, reactions, make-public); tapping a
  // Pool thread still opens the contributor sheet directly.
  void _openThread(CounterpartyThread thread) {
    if (thread.counterparty.isPool) {
      _openPoolContributorSheet(thread.counterparty.id);
      return;
    }
    pushZendSlide(context, ThreadDetailScreen(counterparty: thread.counterparty, edges: thread.edges));
  }

  void _openPoolContributorSheet(String poolId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PoolContributorSheet(poolId: poolId),
    );
  }

  void _openPendingIntent(EmailIntent intent) {
    showPendingIntentDetail(context, intent, ZendScope.of(context));
  }

  void _openOutboundRequest(PaymentRequestItem request) {
    showOutboundRequestDetail(context, request);
  }

  void _openInboundRequest(PaymentRequestItem request) {
    final intent = QrPaymentIntent(
      zendtag: request.requesterZendtag ?? '',
      amountUsdc: request.amountUsdc,
      note: request.description,
      requestLinkId: request.requestLinkId,
    );
    showQrPaymentSheet(context, intent: intent);
  }

  bool _intentIsRenderable(EmailIntent intent) {
    return intent.recipientHint.isNotEmpty &&
        intent.amountUsdc > 0 &&
        intent.expiry.isAfter(DateTime.fromMillisecondsSinceEpoch(0));
  }

  void _openRequestsThread(_RequestsGroup group) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RequestsThreadSheet(
        group: group,
        onOpenIntent: _openPendingIntent,
        onOpenInbound: _openInboundRequest,
        onOpenOutbound: _openOutboundRequest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

    final allThreads = groupByCounterparty(
      model.threadedActivityEdges,
      countIsExact: !model.threadedActivityHasMore,
    );

    // Client-side filter: match counterparty label OR most-recent note.
    // Requests thread is never hidden by the filter — it has no single
    // counterparty name to match against.
    final threads = _filterQuery.isEmpty
        ? allThreads
        : allThreads.where((t) {
            final label = t.counterparty.displayLabel.toLowerCase();
            final note = (t.mostRecentEdge.note ?? '').toLowerCase();
            return label.contains(_filterQuery) || note.contains(_filterQuery);
          }).toList();

    final pendingIntents = model.pendingEmailIntents
        .where((i) => i.isPending && _intentIsRenderable(i))
        .toList();
    final pendingInbound = model.inboundPaymentRequests.where((r) => r.isPending).toList();
    final pendingOutbound = model.outboundPaymentRequests.where((r) => r.amountUsdc > 0).toList();

    // Requests (pending email intents + inbound + outbound payment requests)
    // are not Activity_Edges (per design.md's tap-through table), so they
    // don't naturally fall out of groupByCounterparty(). They're folded into
    // one synthetic "Requests" thread here instead, so they take their place
    // in the same recency-sorted feed as every other thread rather than
    // living in a separate pinned section above it.
    final requestsGroup = _RequestsGroup(
      intents: pendingIntents,
      inbound: pendingInbound,
      outbound: pendingOutbound,
    );

    final feedItems = <_FeedItem>[
      for (final thread in threads) _FeedItem.thread(thread),
      if (requestsGroup.isNotEmpty) _FeedItem.requests(requestsGroup),
    ]..sort((a, b) => b.mostRecentAt.compareTo(a.mostRecentAt));

    final isLoading = model.threadedActivityLoading && threads.isEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Activity',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  // Legacy Ledger view toggle temporarily disabled — not
                  // surfaced in the header for now. widget.onToggleView is
                  // still wired through from ActivityScreen's router so
                  // it's a one-line change to re-enable.
                  IconButton(
                    onPressed: () => pushZendSlide(context, const PublicFeedScreen()),
                    icon: Icon(SolarIconsBold.shareCircle, color: zt.textSecondary),
                    tooltip: 'Public feed',
                  ),
                  if (widget.onOpenGraphView != null)
                    IconButton(
                      onPressed: widget.onOpenGraphView,
                      icon: Icon(SolarIconsBold.shareCircle, color: zt.textSecondary),
                      tooltip: 'Your mutuals',
                    ),
                  // Short-press: toggle inline activity filter.
                  // Long-press: open full global search (transactions, pools, users).
                  GestureDetector(
                    onTap: _toggleFilter,
                    onLongPress: () => pushZendSlide(context, const SearchScreen()),
                    child: IconButton(
                      onPressed: null, // handled by GestureDetector above
                      icon: Icon(
                        _filterActive ? SolarIconsBold.magnifierZoomOut : SolarIconsBold.magnifier,
                        color: _filterActive ? zt.accent : zt.textSecondary,
                      ),
                      tooltip: _filterActive ? 'Clear filter (long-press for full search)' : 'Filter activity (long-press for full search)',
                    ),
                  ),
                  IconButton(
                    onPressed: _toggleNotificationMute,
                    icon: Icon(
                      _notificationsMuted
                          ? SolarIconsBold.bellOff
                          : SolarIconsBold.bell,
                      color: _notificationsMuted
                          ? zt.textSecondary.withValues(alpha: 0.5)
                          : zt.textSecondary,
                    ),
                    tooltip: _notificationsMuted ? 'Unmute notifications' : 'Mute notifications',
                  ),
                ],
              ),
            ),

            // ── Inline filter bar (shown when search icon is active) ──
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _filterActive
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        controller: _filterController,
                        focusNode: _filterFocus,
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Filter by person or note…',
                          hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                          prefixIcon: Icon(SolarIconsBold.magnifier, size: 18, color: zt.textSecondary),
                          suffixIcon: _filterQuery.isNotEmpty
                              ? GestureDetector(
                                  onTap: () => _filterController.clear(),
                                  child: Icon(SolarIconsBold.closeCircle, size: 18, color: zt.textSecondary),
                                )
                              : null,
                          filled: true,
                          fillColor: zt.bgSecondary,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(ZendRadii.pill),
                            borderSide: BorderSide.none,
                          ),
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
                    ? Center(child: ZendLoader(size: 24))
                    : feedItems.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 200,
                                child: Center(
                                  child: Text(
                                    _filterQuery.isNotEmpty
                                        ? 'No matches for "$_filterQuery"'
                                        : 'No activity yet',
                                    style: TextStyle(
                                      fontFamily: 'DMSans',
                                      fontSize: 14,
                                      color: zt.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: feedItems.length,
                            itemBuilder: (context, i) {
                              final item = feedItems[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: switch (item) {
                                  _ThreadFeedItem(thread: final thread) => thread.counterparty.isPool
                                      ? _PoolThreadTile(
                                          thread: thread,
                                          onTap: () => _openThread(thread),
                                        )
                                      : _UserThreadTile(
                                          thread: thread,
                                          onTap: () => _openThread(thread),
                                        ),
                                  _RequestsFeedItem(group: final group) => _RequestsThreadTile(
                                      group: group,
                                      onTap: () => _openRequestsThread(group),
                                    ),
                                },
                              );
                            },
                          ),
              ),
            ),
            if (model.lastThreadedActivityError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Could not load latest activity',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'DMSans',
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

}

// ── Requests grouping (folds pending intents/inbound/outbound requests into
// one synthetic thread, since none of these are Activity_Edges) ──────────

/// All of a User's non-Activity_Edge "asks": pending email intents, inbound
/// payment requests, and outbound payment requests — folded into a single
/// group so they render as one thread in the feed instead of a separate
/// pinned section.
class _RequestsGroup {
  const _RequestsGroup({
    required this.intents,
    required this.inbound,
    required this.outbound,
  });

  final List<EmailIntent> intents;
  final List<PaymentRequestItem> inbound;
  final List<PaymentRequestItem> outbound;

  bool get isNotEmpty => intents.isNotEmpty || inbound.isNotEmpty || outbound.isNotEmpty;

  int get totalCount => intents.length + inbound.length + outbound.length;

  DateTime get mostRecentAt {
    final dates = <DateTime>[
      ...intents.map((i) => i.createdAt),
      ...inbound.map((r) => r.createdAt),
      ...outbound.map((r) => r.createdAt),
    ];
    return dates.isEmpty ? DateTime.fromMillisecondsSinceEpoch(0) : dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

// ── Unified feed item (threads + the one Requests group, sorted together
// by recency so Requests takes its place in the normal feed) ──────────────

sealed class _FeedItem {
  DateTime get mostRecentAt;

  factory _FeedItem.thread(CounterpartyThread thread) = _ThreadFeedItem;
  factory _FeedItem.requests(_RequestsGroup group) = _RequestsFeedItem;
}

class _ThreadFeedItem implements _FeedItem {
  const _ThreadFeedItem(this.thread);
  final CounterpartyThread thread;
  @override
  DateTime get mostRecentAt => thread.mostRecentEdge.createdAt;
}

class _RequestsFeedItem implements _FeedItem {
  const _RequestsFeedItem(this.group);
  final _RequestsGroup group;
  @override
  DateTime get mostRecentAt => group.mostRecentAt;
}

// ── Requests thread tile (feed row) ─────────────────────────────────────────

class _RequestsThreadTile extends StatelessWidget {
  const _RequestsThreadTile({required this.group, required this.onTap});

  final _RequestsGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final owedToYou = group.inbound.length;
    final youOwe = group.outbound.length + group.intents.length;

    return Material(
      color: zt.bgSecondary,
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: ZendColors.destructive.withValues(alpha: 0.12),
                child: Icon(SolarIconsBold.bill, color: ZendColors.destructive, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Requests',
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 14.5, fontWeight: FontWeight.w700, color: zt.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Money asks between you and others',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (owedToYou > 0)
                          _CountPill(count: owedToYou, label: 'owed to you', color: ZendColors.positive),
                        if (owedToYou > 0 && youOwe > 0) const SizedBox(width: 6),
                        if (youOwe > 0)
                          _CountPill(count: youOwe, label: 'pending', color: zt.textSecondary),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(SolarIconsBold.altArrowRight, color: zt.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.label, required this.color});
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZendRadii.pill),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Requests thread detail sheet (tap-through destination) ─────────────────

class _RequestsThreadSheet extends StatelessWidget {
  const _RequestsThreadSheet({
    required this.group,
    required this.onOpenIntent,
    required this.onOpenInbound,
    required this.onOpenOutbound,
  });

  final _RequestsGroup group;
  final void Function(EmailIntent) onOpenIntent;
  final void Function(PaymentRequestItem) onOpenInbound;
  final void Function(PaymentRequestItem) onOpenOutbound;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xxl),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              'Requests',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 18, fontWeight: FontWeight.w700, color: zt.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              '${group.totalCount} total',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 12, color: zt.textSecondary),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final request in group.inbound)
                    _PendingRowTile(
                      zt: zt,
                      avatarLabel: request.avatarInitial,
                      title: request.counterpartyLabel,
                      subtitle: 'Requesting payment',
                      amount: '-${request.formattedAmount}',
                      onTap: () {
                        Navigator.of(context).pop();
                        onOpenInbound(request);
                      },
                    ),
                  for (final request in group.outbound)
                    _PendingRowTile(
                      zt: zt,
                      avatarLabel: request.avatarInitial,
                      title: request.counterpartyLabel,
                      subtitle: request.isPending ? 'Pending' : request.status,
                      amount: '+${request.formattedAmount}',
                      onTap: () {
                        Navigator.of(context).pop();
                        onOpenOutbound(request);
                      },
                    ),
                  for (final intent in group.intents)
                    _PendingRowTile(
                      zt: zt,
                      avatarLabel: intent.recipientHint.isNotEmpty ? intent.recipientHint[0].toUpperCase() : '?',
                      title: intent.recipientHint,
                      subtitle: 'Pending claim',
                      amount: '-${intent.amountFormatted}',
                      onTap: () {
                        Navigator.of(context).pop();
                        onOpenIntent(intent);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pending item row (non-grouped — email intents / requests) ─────────────

class _PendingRowTile extends StatelessWidget {
  const _PendingRowTile({
    required this.zt,
    required this.avatarLabel,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.onTap,
  });

  final ZendTheme zt;
  final String avatarLabel;
  final String title;
  final String subtitle;
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: zt.bgSecondary,
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ZendAvatar(radius: 20, initials: avatarLabel),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: zt.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: zt.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                amount,
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  color: zt.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── User thread tile (Req 11) ───────────────────────────────────────────────

class _UserThreadTile extends StatelessWidget {
  const _UserThreadTile({required this.thread, required this.onTap});

  final CounterpartyThread thread;
  final VoidCallback onTap;

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
    final counterparty = thread.counterparty;
    final mostRecent = thread.mostRecentEdge;
    final isOutgoing = mostRecent.isOutgoing;
    final amountLabel = mostRecent.amountHidden ? 'Hidden' : '\$${mostRecent.amountUsdc ?? '0'}';

    // Venmo-style feed sentence with word variety: "You paid/sent/zapped
    // @omooba" / "@omooba paid/sent/zapped you" — deterministic per edge
    // (feedVerbFor) so the same edge never flickers between phrasings on
    // rebuild, while different threads get visual variety.
    final verb = feedVerbFor(mostRecent);
    final actionSpan = isOutgoing ? 'You $verb ' : '';
    final subjectSpan = counterparty.displayLabel;
    final trailingSpan = isOutgoing ? '' : ' $verb';

    return Material(
      color: zt.bgSecondary,
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ZendAvatar(
                radius: 22,
                photoUrl: counterparty.avatarUrl,
                initials: counterparty.initialLetter,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sentence headline, feed-style.
                    RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 14.5, color: zt.textPrimary),
                        children: [
                          if (actionSpan.isNotEmpty) TextSpan(text: actionSpan),
                          TextSpan(
                            text: subjectSpan,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (trailingSpan.isNotEmpty) TextSpan(text: trailingSpan),
                        ],
                      ),
                    ),
                    if (mostRecent.note?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        mostRecent.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textPrimary.withValues(alpha: 0.85)),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          _relativeTime(mostRecent.createdAt),
                          style: TextStyle(fontFamily: 'DMMono', fontSize: 11, color: zt.textSecondary.withValues(alpha: 0.8)),
                        ),
                        if (thread.edges.length > 1) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: zt.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(ZendRadii.pill),
                            ),
                            child: Text(
                              thread.countIsExact
                                  ? '${thread.edges.length}x together'
                                  : '${thread.edges.length}+ together',
                              style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5, color: zt.accent, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Amount as a secondary pill, not a dominant serif figure —
              // the sentence above carries the primary "story", the amount
              // is supporting detail.
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
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isOutgoing ? zt.textSecondary : ZendColors.positive,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pool thread tile (Req 14) ───────────────────────────────────────────────
//
// Renders the aggregate progress bar + de-duplicated contributor list.
// Fetches contributor detail lazily via ActivityDataService.getPoolContributors
// only when tapped, matching the on-demand nature of that endpoint.

class _PoolThreadTile extends StatelessWidget {
  const _PoolThreadTile({required this.thread, required this.onTap});

  final CounterpartyThread thread;
  final VoidCallback onTap;

  void _openContributorSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PoolContributorSheet(poolId: thread.counterparty.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final counterparty = thread.counterparty;
    final label = counterparty.poolName ?? 'Pool';
    final mostRecent = thread.mostRecentEdge;

    return Material(
      color: zt.bgSecondary,
      borderRadius: BorderRadius.circular(ZendRadii.xl),
      child: InkWell(
        onTap: () => _openContributorSheet(context),
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: zt.accent.withValues(alpha: 0.15),
                child: Icon(SolarIconsBold.usersGroupRounded, color: zt.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 14.5, color: zt.textPrimary),
                        children: [
                          const TextSpan(text: 'You chipped into '),
                          TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      mostRecent.note?.isNotEmpty == true ? mostRecent.note! : 'A group pool',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 13,
                        color: mostRecent.note?.isNotEmpty == true ? zt.textPrimary.withValues(alpha: 0.85) : zt.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: zt.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(ZendRadii.pill),
                          ),
                          child: Text(
                            thread.countIsExact
                                ? '${thread.edges.length} contribution${thread.edges.length == 1 ? '' : 's'}'
                                : '${thread.edges.length}+ contributions',
                            style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5, color: zt.accent, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'tap for progress',
                          style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5, color: zt.textSecondary.withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: zt.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
                child: Text(
                  '\$${thread.runningTotal.toStringAsFixed(2)}',
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 12.5, fontWeight: FontWeight.w700, color: zt.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PoolContributorSheet extends StatefulWidget {
  const _PoolContributorSheet({required this.poolId});
  final String poolId;

  @override
  State<_PoolContributorSheet> createState() => _PoolContributorSheetState();
}

class _PoolContributorSheetState extends State<_PoolContributorSheet> {
  PoolContributorsResponse? _response;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final model = ZendScope.of(context);
      final response = await model.activityDataService.getPoolContributors(widget.poolId);
      if (mounted) setState(() => _response = response);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xxl),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: zt.border,
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: ZendLoader(size: 24)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  'Could not load contributors',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'DMSans', color: zt.textSecondary),
                ),
              )
            else if (_response != null)
              Flexible(child: _buildContent(zt, _response!)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ZendTheme zt, PoolContributorsResponse response) {
    final gathered = double.tryParse(response.gatheredAmountUsdc) ?? 0.0;
    final target = double.tryParse(response.targetAmountUsdc) ?? 1.0;
    final progress = target > 0 ? (gathered / target).clamp(0.0, 1.0) : 0.0;
    final deduped = dedupePoolContributors(response.contributors);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '\$${gathered.toStringAsFixed(2)} of \$${target.toStringAsFixed(2)}',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 28,
              fontStyle: FontStyle.italic,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(ZendRadii.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: zt.border,
              color: zt.accent,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Contributors',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: zt.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final contributor in deduped)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      switch (contributor.entry) {
                        PoolContributorUser(zendtag: final tag) =>
                          tag != null && tag.isNotEmpty ? '@$tag' : 'A contributor',
                        PoolContributorExternalAnonymized(aggregateCount: final count) =>
                          '$count external contributor${count == 1 ? '' : 's'}',
                      },
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    switch (contributor.entry) {
                      PoolContributorUser(amountHidden: true) => 'Hidden',
                      _ => '\$${contributor.totalUsdc.toStringAsFixed(2)}',
                    },
                    style: TextStyle(fontFamily: 'DMMono', fontSize: 13, color: zt.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
