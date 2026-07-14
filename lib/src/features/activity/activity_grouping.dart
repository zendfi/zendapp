/// Pure grouping/aggregation/de-duplication logic for the Phase 2
/// Threaded_Activity_View. Deliberately kept free of any Flutter widget
/// imports so it can be exercised directly by example-based unit tests
/// (no Dart property-based testing library exists in this codebase, unlike
/// the Rust side's `proptest` — see design.md's Testing Strategy section).
///
/// Implements:
///  - Property 15: Counterparty/Pool grouping, aggregation, and ordering
///  - Property 16: Pool contributor list de-duplicates by contributor
library;

import '../../models/activity_edge.dart';

// ── Feed headline word variations (social feel — Venmo-style sentences) ─────

const _outgoingVerbs = ['paid', 'sent', 'zapped', 'dropped', 'shipped'];
const _incomingVerbs = ['paid you', 'sent you', 'zapped you', 'came through for you'];

/// Deterministically picks a verb variation for [edge] so the same edge
/// always renders the same phrase across rebuilds (no flicker), while
/// different edges/counterparties get visual variety instead of every
/// thread reading identically as "paid"/"paid you".
String feedVerbFor(ActivityEdge edge) {
  final pool = edge.isOutgoing ? _outgoingVerbs : _incomingVerbs;
  final index = edge.edgeId.hashCode.abs() % pool.length;
  return pool[index];
}

/// One grouped thread of [ActivityEdge]s sharing the same counterparty
/// (a Zend user or a Pool), per design.md's `CounterpartyThread` sketch.
class CounterpartyThread {
  final ActivityCounterparty counterparty;
  final List<ActivityEdge> edges;
  final double runningTotal;
  final ActivityEdge mostRecentEdge;

  const CounterpartyThread({
    required this.counterparty,
    required this.edges,
    required this.runningTotal,
    required this.mostRecentEdge,
  });
}

double _parseAmount(String? amountUsdc) {
  if (amountUsdc == null) return 0.0;
  return double.tryParse(amountUsdc) ?? 0.0;
}

/// Groups [edges] by `counterparty.id`, computing each group's running
/// total (sum of non-hidden amounts) and most-recent-edge pointer, then
/// sorts the groups by their most-recent edge's `createdAt` descending.
///
/// Property 15 guarantees:
///  (a) every input edge appears in exactly one output group
///  (b) each group's running total equals the sum of its edges' amounts
///  (c) each group's most-recent pointer equals the max-createdAt edge
///  (d) groups are ordered by most-recent timestamp, descending
List<CounterpartyThread> groupByCounterparty(List<ActivityEdge> edges) {
  final byCounterpartyId = <String, List<ActivityEdge>>{};
  final counterpartyById = <String, ActivityCounterparty>{};

  for (final edge in edges) {
    final id = edge.counterparty.id;
    counterpartyById.putIfAbsent(id, () => edge.counterparty);
    byCounterpartyId.putIfAbsent(id, () => []).add(edge);
  }

  final threads = byCounterpartyId.entries.map((entry) {
    final groupEdges = entry.value;
    final runningTotal = groupEdges.fold<double>(
      0.0,
      (sum, e) => sum + (e.amountHidden ? 0.0 : _parseAmount(e.amountUsdc)),
    );
    final mostRecent = groupEdges.reduce(
      (a, b) => b.createdAt.isAfter(a.createdAt) ? b : a,
    );
    return CounterpartyThread(
      counterparty: counterpartyById[entry.key]!,
      edges: groupEdges,
      runningTotal: runningTotal,
      mostRecentEdge: mostRecent,
    );
  }).toList();

  threads.sort((a, b) => b.mostRecentEdge.createdAt.compareTo(a.mostRecentEdge.createdAt));
  return threads;
}

/// De-duplicated, display-ready contributor entry for `PoolThreadTile`.
/// Either an identified Zend-user Contributor (summed across all of their
/// contributions) or the single folded row representing every
/// External_Participant combined — mirrors [PoolContributorEntry] but is
/// produced client-side from the raw response for rendering convenience.
class DedupedPoolContributor {
  final PoolContributorEntry entry;
  final double totalUsdc;

  const DedupedPoolContributor({required this.entry, required this.totalUsdc});
}

/// Reduces a Pool's raw contributor list (as returned by
/// `GET /api/zend/activity/pools/:pool_id/contributors`) into the
/// de-duplicated list `PoolThreadTile` renders.
///
/// The server-side response (`build_pool_contributor_rows` in
/// `activity_authz.rs`) already de-duplicates by contributor and folds
/// External_Participants into one aggregate row, so this function is
/// primarily a pass-through/total-summing step — kept as its own pure
/// function (rather than inlined in the widget) so Property 16 can be
/// verified independently of any server response shape changes, and so a
/// future client-side merge of multiple pages behaves identically.
///
/// Property 16 guarantees: exactly one entry per distinct Contributor,
/// each entry's total equals the sum of that Contributor's contributions,
/// and the sum of all displayed totals equals the Pool's aggregate total.
List<DedupedPoolContributor> dedupePoolContributors(
  List<PoolContributorEntry> contributors,
) {
  final byUserId = <String, double>{};
  final userEntryById = <String, PoolContributorUser>{};
  PoolContributorExternalAnonymized? externalEntry;

  for (final c in contributors) {
    switch (c) {
      case PoolContributorUser():
        final existingTotal = byUserId[c.userId] ?? 0.0;
        byUserId[c.userId] = existingTotal + _parseAmount(c.totalUsdc);
        // Keep the first-seen entry's metadata (zendtag/amountHidden) —
        // in practice the server already sends one row per user, so this
        // only matters if a caller merges multiple response pages.
        userEntryById.putIfAbsent(c.userId, () => c);
      case PoolContributorExternalAnonymized():
        if (externalEntry == null) {
          externalEntry = c;
        } else {
          externalEntry = PoolContributorExternalAnonymized(
            aggregateCount: externalEntry.aggregateCount + c.aggregateCount,
            aggregateTotalUsdc: (
              _parseAmount(externalEntry.aggregateTotalUsdc) + _parseAmount(c.aggregateTotalUsdc)
            ).toString(),
          );
        }
    }
  }

  final result = <DedupedPoolContributor>[
    for (final entry in userEntryById.entries)
      DedupedPoolContributor(
        entry: entry.value,
        totalUsdc: byUserId[entry.key]!,
      ),
  ];

  if (externalEntry != null) {
    result.add(DedupedPoolContributor(
      entry: externalEntry,
      totalUsdc: _parseAmount(externalEntry.aggregateTotalUsdc),
    ));
  }

  return result;
}
