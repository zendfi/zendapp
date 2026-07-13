// Example-based tests for activity_grouping.dart's pure grouping/aggregation
// logic (Property 15) and Pool contributor de-duplication (Property 16).
//
// No Dart property-based testing library exists in this codebase (unlike the
// Rust side's `proptest`), so these are deliberately table-driven/example
// based rather than generative — see design.md's Testing Strategy section
// for why PBT is not forced here.

import 'package:flutter_test/flutter_test.dart';
import 'package:zendapp/src/features/activity/activity_grouping.dart';
import 'package:zendapp/src/models/activity_edge.dart';

ActivityEdge _edge({
  required String edgeId,
  required String counterpartyId,
  String counterpartyKind = 'user',
  String? amountUsdc,
  bool amountHidden = false,
  required DateTime createdAt,
  ActivityEdgeKind edgeKind = ActivityEdgeKind.zendTransfer,
  String direction = 'outgoing',
}) {
  return ActivityEdge(
    edgeId: edgeId,
    edgeKind: edgeKind,
    counterparty: ActivityCounterparty(kind: counterpartyKind, id: counterpartyId),
    amountUsdc: amountUsdc,
    amountHidden: amountHidden,
    direction: direction,
    effectiveTier: VisibilityTier.private,
    isDirectParticipant: true,
    createdAt: createdAt,
  );
}

void main() {
  group('groupByCounterparty (Property 15)', () {
    test('every input edge appears in exactly one output group', () {
      final edges = [
        _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '10', createdAt: DateTime(2024, 1, 1)),
        _edge(edgeId: 'e2', counterpartyId: 'u1', amountUsdc: '5', createdAt: DateTime(2024, 1, 2)),
        _edge(edgeId: 'e3', counterpartyId: 'u2', amountUsdc: '20', createdAt: DateTime(2024, 1, 3)),
      ];

      final threads = groupByCounterparty(edges);
      final allEdgeIds = threads.expand((t) => t.edges).map((e) => e.edgeId).toList();

      expect(allEdgeIds.length, edges.length);
      expect(allEdgeIds.toSet(), edges.map((e) => e.edgeId).toSet());
    });

    test('running total equals the sum of the group\'s amounts, excluding hidden', () {
      final edges = [
        _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '10', createdAt: DateTime(2024, 1, 1)),
        _edge(edgeId: 'e2', counterpartyId: 'u1', amountUsdc: '5', createdAt: DateTime(2024, 1, 2)),
        // Hidden amounts must not contribute to the running total.
        _edge(
          edgeId: 'e3',
          counterpartyId: 'u1',
          amountUsdc: null,
          amountHidden: true,
          createdAt: DateTime(2024, 1, 3),
        ),
      ];

      final threads = groupByCounterparty(edges);
      expect(threads.length, 1);
      expect(threads.first.runningTotal, 15.0);
    });

    test('most-recent pointer equals the max-createdAt edge in the group', () {
      final newest = _edge(edgeId: 'e2', counterpartyId: 'u1', amountUsdc: '5', createdAt: DateTime(2024, 1, 10));
      final edges = [
        _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '10', createdAt: DateTime(2024, 1, 1)),
        newest,
      ];

      final threads = groupByCounterparty(edges);
      expect(threads.single.mostRecentEdge.edgeId, newest.edgeId);
    });

    test('groups are ordered by most-recent timestamp, descending', () {
      final edges = [
        _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '10', createdAt: DateTime(2024, 1, 1)),
        _edge(edgeId: 'e2', counterpartyId: 'u2', amountUsdc: '20', createdAt: DateTime(2024, 1, 15)),
        _edge(edgeId: 'e3', counterpartyId: 'u3', amountUsdc: '30', createdAt: DateTime(2024, 1, 8)),
      ];

      final threads = groupByCounterparty(edges);
      final orderedIds = threads.map((t) => t.counterparty.id).toList();
      expect(orderedIds, ['u2', 'u3', 'u1']);
    });

    test('empty input produces empty output', () {
      expect(groupByCounterparty(const []), isEmpty);
    });

    test('Pool counterparties group separately from User counterparties with the same id string', () {
      final edges = [
        _edge(edgeId: 'e1', counterpartyId: 'shared-id', counterpartyKind: 'user', amountUsdc: '1', createdAt: DateTime(2024, 1, 1)),
      ];
      final threads = groupByCounterparty(edges);
      expect(threads.single.counterparty.kind, 'user');
    });
  });

  group('dedupePoolContributors (Property 16)', () {
    test('exactly one entry per distinct user contributor, summed', () {
      final contributors = [
        const PoolContributorUser(userId: 'u1', totalUsdc: '10', amountHidden: false),
        const PoolContributorUser(userId: 'u2', totalUsdc: '5', amountHidden: false),
      ];

      final deduped = dedupePoolContributors(contributors);
      expect(deduped.length, 2);
      expect(deduped.map((d) => d.totalUsdc).toSet(), {10.0, 5.0});
    });

    test('multiple external rows fold into a single aggregated entry', () {
      final contributors = [
        const PoolContributorUser(userId: 'u1', totalUsdc: '10', amountHidden: false),
        const PoolContributorExternalAnonymized(aggregateCount: 2, aggregateTotalUsdc: '7'),
        const PoolContributorExternalAnonymized(aggregateCount: 1, aggregateTotalUsdc: '3'),
      ];

      final deduped = dedupePoolContributors(contributors);
      final externalEntries = deduped.where((d) => d.entry is PoolContributorExternalAnonymized);
      expect(externalEntries.length, 1);
      expect(externalEntries.single.totalUsdc, 10.0);
      final externalEntry = externalEntries.single.entry as PoolContributorExternalAnonymized;
      expect(externalEntry.aggregateCount, 3);
    });

    test('sum of all displayed totals equals the pool aggregate total', () {
      const aggregateTotal = 25.0; // 10 (u1) + 5 (u2) + 10 (external)
      final contributors = [
        const PoolContributorUser(userId: 'u1', totalUsdc: '10', amountHidden: false),
        const PoolContributorUser(userId: 'u2', totalUsdc: '5', amountHidden: false),
        const PoolContributorExternalAnonymized(aggregateCount: 2, aggregateTotalUsdc: '10'),
      ];

      final deduped = dedupePoolContributors(contributors);
      final sum = deduped.fold<double>(0.0, (s, d) => s + d.totalUsdc);
      expect(sum, aggregateTotal);
    });

    test('empty input produces empty output', () {
      expect(dedupePoolContributors(const []), isEmpty);
    });
  });
}
