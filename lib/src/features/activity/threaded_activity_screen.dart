import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import '../../models/api_models.dart';
import '../../models/email_intent.dart';
import '../../models/payment_request_item.dart';
import '../../models/qr_payment_intent.dart';
import '../send/qr_payment_sheet.dart';
import 'activity_grouping.dart';
import 'legacy_activity_list_view.dart';
import 'search_screen.dart';
import 'transaction_receipt_sheet.dart';
import '../../navigation/zend_routes.dart';

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
  // Every ActivityEdge now carries its own sender/recipient identity and
  // transaction detail fields (added alongside the zendtag/avatar fix —
  // see activity_data_service.rs), so the receipt is built directly from
  // the edge itself rather than cross-referencing a second, separately
  // fetched/paginated list (recentTransactions) that may not contain every
  // edge this viewer is authorized to see via Shared_Network visibility.
  // That cross-reference was the root cause of the "Loading details…"
  // fallback firing for edges that were perfectly renderable.
  void _openEdge(ActivityEdge edge) {
    if (edge.edgeKind == ActivityEdgeKind.zendTransfer || edge.edgeKind == ActivityEdgeKind.poolContribution) {
      final entry = _entryFromEdge(edge);
      if (entry != null) {
        showTransactionReceipt(
          context,
          tx: ZendTransaction(
            name: edge.counterparty.displayLabel,
            note: edge.note ?? '',
            amount: edge.amountHidden
                ? 'Hidden'
                : '${edge.isOutgoing ? '-' : '+'}\$${edge.amountUsdc ?? '0'}',
            time: '',
            avatarLabel: edge.counterparty.initialLetter,
            avatarUrl: edge.counterparty.avatarUrl,
            entry: entry,
            createdAt: edge.createdAt,
          ),
        );
        return;
      }
    }

    if (edge.edgeKind == ActivityEdgeKind.requestFulfillment) {
      final model = ZendScope.of(context);
      final outboundMatch = model.outboundPaymentRequests.where((r) => r.id == edge.edgeId);
      if (outboundMatch.isNotEmpty) {
        showOutboundRequestDetail(context, outboundMatch.first);
        return;
      }
    }

    // Genuinely missing detail (e.g. a still-hidden amount with no
    // reconstructable receipt) — this should now be rare.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Details for this activity are not available', style: TextStyle(fontFamily: 'DMSans')),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Reconstructs the [TransferHistoryEntry] the receipt sheet needs
  /// directly from an [ActivityEdge]'s own carried fields. Returns null
  /// only if the edge is missing the minimum fields required to render a
  /// receipt (e.g. a very old cached response predating this fix).
  TransferHistoryEntry? _entryFromEdge(ActivityEdge edge) {
    final model = ZendScope.of(context);
    final isSender = edge.isOutgoing;
    final senderZendtag = isSender ? model.currentZendtag : edge.counterparty.zendtag;
    final recipientZendtag = isSender ? edge.counterparty.zendtag : model.currentZendtag;
    if (edge.transactionSignature == null || senderZendtag == null || recipientZendtag == null) {
      return null;
    }

    return TransferHistoryEntry(
      id: edge.edgeId,
      senderZendtag: senderZendtag,
      recipientZendtag: recipientZendtag,
      amountUsdc: edge.amountUsdc ?? '0',
      transactionSignature: edge.transactionSignature!,
      note: edge.note,
      status: edge.status ?? 'confirmed',
      createdAt: edge.createdAt,
      senderAvatarUrl: isSender ? model.currentAvatarUrl : edge.counterparty.avatarUrl,
      recipientAvatarUrl: isSender ? edge.counterparty.avatarUrl : model.currentAvatarUrl,
      senderDisplayName: isSender ? model.currentDisplayName : edge.counterparty.displayName,
      recipientDisplayName: isSender ? edge.counterparty.displayName : model.currentDisplayName,
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

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

    final threads = groupByCounterparty(model.threadedActivityEdges);

    final pendingIntents = model.pendingEmailIntents
        .where((i) => i.isPending && _intentIsRenderable(i))
        .toList();
    final pendingInbound = model.inboundPaymentRequests.where((r) => r.isPending).toList();
    final pendingOutbound = model.outboundPaymentRequests.where((r) => r.amountUsdc > 0).toList();
    final hasPendingSection =
        pendingIntents.isNotEmpty || pendingInbound.isNotEmpty || pendingOutbound.isNotEmpty;

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
                  _ViewToggleButton(onTap: widget.onToggleView),
                  if (widget.onOpenGraphView != null)
                    IconButton(
                      onPressed: widget.onOpenGraphView,
                      icon: Icon(Icons.hub_outlined, color: zt.textSecondary),
                      tooltip: 'View relationship graph',
                    ),
                  IconButton(
                    onPressed: () => pushZendSlide(context, const SearchScreen()),
                    icon: Icon(Icons.search, color: zt.textSecondary),
                    tooltip: 'Search',
                  ),
                  IconButton(
                    onPressed: _toggleNotificationMute,
                    icon: Icon(
                      _notificationsMuted
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_none,
                      color: _notificationsMuted
                          ? zt.textSecondary.withValues(alpha: 0.5)
                          : zt.textSecondary,
                    ),
                    tooltip: _notificationsMuted ? 'Unmute notifications' : 'Mute notifications',
                  ),
                ],
              ),
            ),

            // ── Content ──
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => model.fetchThreadedActivity(),
                child: isLoading
                    ? const Center(child: ZendLoader(size: 24))
                    : (!hasPendingSection && threads.isEmpty)
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 200,
                                child: Center(
                                  child: Text(
                                    'No activity yet',
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
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              if (hasPendingSection) ...[
                                _SectionLabel(label: 'Pending', zt: zt),
                                const SizedBox(height: 8),
                                ..._buildPendingTiles(
                                  zt,
                                  pendingIntents,
                                  pendingInbound,
                                  pendingOutbound,
                                ),
                                const SizedBox(height: 20),
                              ],
                              if (threads.isNotEmpty) _SectionLabel(label: 'Threads', zt: zt),
                              const SizedBox(height: 8),
                              for (final thread in threads)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: thread.counterparty.isPool
                                      ? _PoolThreadTile(
                                          thread: thread,
                                          onTap: () => _openEdge(thread.mostRecentEdge),
                                        )
                                      : _UserThreadTile(
                                          thread: thread,
                                          onTap: () => _openEdge(thread.mostRecentEdge),
                                        ),
                                ),
                            ],
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

  List<Widget> _buildPendingTiles(
    ZendTheme zt,
    List<EmailIntent> intents,
    List<PaymentRequestItem> inbound,
    List<PaymentRequestItem> outbound,
  ) {
    final tiles = <Widget>[
      for (final intent in intents)
        _PendingRowTile(
          zt: zt,
          avatarLabel: intent.recipientHint.isNotEmpty ? intent.recipientHint[0].toUpperCase() : '?',
          title: intent.recipientHint,
          subtitle: 'pending claim',
          amount: '-${intent.amountFormatted}',
          onTap: () => _openPendingIntent(intent),
        ),
      for (final request in inbound)
        _PendingRowTile(
          zt: zt,
          avatarLabel: request.avatarInitial,
          title: request.counterpartyLabel,
          subtitle: 'Requesting payment',
          amount: '-${request.formattedAmount}',
          onTap: () => _openInboundRequest(request),
        ),
      for (final request in outbound)
        _PendingRowTile(
          zt: zt,
          avatarLabel: request.avatarInitial,
          title: request.counterpartyLabel,
          subtitle: request.isPending ? 'Pending' : request.status,
          amount: '+${request.formattedAmount}',
          onTap: () => _openOutboundRequest(request),
        ),
    ];
    return tiles;
  }
}

// ── View toggle control (Req 12.2) ──────────────────────────────────────────

class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return IconButton(
      onPressed: onTap,
      icon: Icon(Icons.list_alt_outlined, color: zt.textSecondary),
      tooltip: 'Switch to flat list view',
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.zt});
  final String label;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: zt.textSecondary,
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

    // Venmo-style feed sentence: "You paid @omooba" / "@omooba paid you" —
    // the relationship/action reads as a sentence, with the amount
    // demoted to a secondary pill rather than dominating the row.
    final actionSpan = isOutgoing ? 'You paid ' : '';
    final subjectSpan = counterparty.displayLabel;
    final trailingSpan = isOutgoing ? '' : ' paid you';

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
                    const SizedBox(height: 3),
                    Text(
                      mostRecent.note?.isNotEmpty == true ? '"${mostRecent.note}"' : 'No note added',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 13,
                        fontStyle: mostRecent.note?.isNotEmpty == true ? FontStyle.italic : FontStyle.normal,
                        color: zt.textSecondary,
                      ),
                    ),
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
                              '${thread.edges.length}x together',
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
                child: Icon(Icons.groups_outlined, color: zt.accent, size: 20),
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
                      mostRecent.note?.isNotEmpty == true ? '"${mostRecent.note}"' : 'A group pool',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 13,
                        fontStyle: mostRecent.note?.isNotEmpty == true ? FontStyle.italic : FontStyle.normal,
                        color: zt.textSecondary,
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
                            '${thread.edges.length} contribution${thread.edges.length == 1 ? '' : 's'}',
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
