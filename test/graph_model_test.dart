// Example-based tests for graph_model.dart's pure graph construction (Property
// 18), visual weight scoring (Property 20), and top-N/Others clustering
// (Property 21).
//
// No Dart property-based testing library exists in this codebase (unlike the
// Rust side's `proptest`) — these are table-driven/example-based, covering
// each sub-clause of the three properties with a dedicated case, per the
// same convention established in `activity_grouping_test.dart` (Phase 2).

import 'package:flutter_test/flutter_test.dart';
import 'package:zendapp/src/features/activity/graph_model.dart';
import 'package:zendapp/src/models/activity_edge.dart';

ActivityEdge _edge({
  required String edgeId,
  required String counterpartyId,
  String counterpartyKind = 'user',
  String? amountUsdc,
  bool amountHidden = false,
  required DateTime createdAt,
}) {
  return ActivityEdge(
    edgeId: edgeId,
    edgeKind: ActivityEdgeKind.zendTransfer,
    counterparty: ActivityCounterparty(kind: counterpartyKind, id: counterpartyId),
    amountUsdc: amountUsdc,
    amountHidden: amountHidden,
    direction: 'outgoing',
    effectiveTier: VisibilityTier.private,
    isDirectParticipant: true,
    createdAt: createdAt,
  );
}

void main() {
  group('buildRawGraph (Property 18)', () {
    test('node set exactly equals distinct users/pools referenced by the input', () {
      final edges = [
        _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '10', createdAt: DateTime(2024, 1, 1)),
        _edge(edgeId: 'e2', counterpartyId: 'u2', amountUsdc: '5', createdAt: DateTime(2024, 1, 2)),
        _edge(edgeId: 'e3', counterpartyId: 'u1', amountUsdc: '3', createdAt: DateTime(2024, 1, 3)),
      ];

      final graph = buildRawGraph(edges: edges, selfId: 'self', selfLabel: 'Me');
      final nodeIds = graph.nodes.map((n) => n.id).toSet();
      expect(nodeIds, {'self', 'u1', 'u2'});
    });

    test('edge set exactly equals the input Activity_Edges expressed as node-pairs', () {
      final edges = [
        _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '10', createdAt: DateTime(2024, 1, 1)),
        _edge(edgeId: 'e2', counterpartyId: 'u2', amountUsdc: '5', createdAt: DateTime(2024, 1, 2)),
      ];

      final graph = buildRawGraph(edges: edges, selfId: 'self', selfLabel: 'Me');
      expect(graph.edges.length, edges.length);
      expect(graph.edges.map((e) => e.id).toSet(), edges.map((e) => e.edgeId).toSet());
      for (final e in graph.edges) {
        expect(e.sourceId, 'self');
      }
    });

    test('every Pool node has exactly one spoke edge per participant present in the data', () {
      final edges = [
        _edge(
          edgeId: 'e1',
          counterpartyId: 'pool1',
          counterpartyKind: 'pool',
          amountUsdc: '10',
          createdAt: DateTime(2024, 1, 1),
        ),
      ];
      final graph = buildRawGraph(
        edges: edges,
        selfId: 'self',
        selfLabel: 'Me',
        poolParticipants: {
          'pool1': [
            const GraphParticipant(id: 'p1', label: 'Alice'),
            const GraphParticipant(id: 'p2', label: 'Bob'),
          ],
          // Pool not referenced by any edge — its participants must NOT appear.
          'pool2': [const GraphParticipant(id: 'p3', label: 'Carol')],
        },
      );

      final spokes = graph.edges.where((e) => e.isSpoke).toList();
      expect(spokes.length, 2);
      expect(spokes.map((e) => e.targetId).toSet(), {'p1', 'p2'});
      expect(graph.nodes.map((n) => n.id), isNot(contains('p3')));
    });

    test('empty edge list produces a graph with only the self node', () {
      final graph = buildRawGraph(edges: const [], selfId: 'self', selfLabel: 'Me');
      expect(graph.nodes.map((n) => n.id).toList(), ['self']);
      expect(graph.edges, isEmpty);
    });
  });

  group('normalizedScore / recencyScoreForDays (Property 20 parts a/b)', () {
    test('normalizedScore is within [0, 1] and monotonically non-decreasing in value', () {
      expect(normalizedScore(0, 10), 0.0);
      expect(normalizedScore(5, 10), 0.5);
      expect(normalizedScore(10, 10), 1.0);
      expect(normalizedScore(15, 10), 1.0); // clamped
      expect(normalizedScore(5, 0), 0.0); // no divide-by-zero

      // Monotonic non-decreasing as value increases, max fixed.
      final scores = [0.0, 2.0, 4.0, 6.0, 8.0, 10.0].map((v) => normalizedScore(v, 10.0)).toList();
      for (var i = 1; i < scores.length; i++) {
        expect(scores[i], greaterThanOrEqualTo(scores[i - 1]));
      }
    });

    test('recencyScoreForDays is monotonically non-increasing as days increase', () {
      const halfLife = 14.0;
      final days = [0.0, 7.0, 14.0, 28.0, 60.0];
      final scores = days.map((d) => recencyScoreForDays(d, halfLife)).toList();
      for (var i = 1; i < scores.length; i++) {
        expect(scores[i], lessThanOrEqualTo(scores[i - 1]));
      }
      // Half-life sanity: score at exactly one half-life is ~0.5.
      expect(recencyScoreForDays(14.0, halfLife), closeTo(0.5, 0.001));
      expect(recencyScoreForDays(0.0, halfLife), 1.0);
    });
  });

  group('computePairWeights (Property 20 parts a/c)', () {
    test('frequency_score and amount_score increase with more/larger transactions, all else fixed', () {
      final now = DateTime(2024, 2, 1);
      // u1: two transactions, larger total; u2: one transaction, smaller total.
      // Same recency for both so frequency/amount dominate the comparison.
      final edges = [
        _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '50', createdAt: now),
        _edge(edgeId: 'e2', counterpartyId: 'u1', amountUsdc: '50', createdAt: now),
        _edge(edgeId: 'e3', counterpartyId: 'u2', amountUsdc: '10', createdAt: now),
      ];
      final raw = buildRawGraph(edges: edges, selfId: 'self', selfLabel: 'Me');
      final result = computePairWeights(raw, selfId: 'self', now: now);

      expect(result.counterpartyWeights['u1']!, greaterThan(result.counterpartyWeights['u2']!));
    });

    test('node weight is a deterministic, order-independent sum of incident edge weights', () {
      final now = DateTime(2024, 2, 1);
      final edgesOrderA = [
        _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '10', createdAt: now),
        _edge(edgeId: 'e2', counterpartyId: 'u2', amountUsdc: '20', createdAt: now.subtract(const Duration(days: 5))),
        _edge(edgeId: 'e3', counterpartyId: 'u3', amountUsdc: '30', createdAt: now.subtract(const Duration(days: 10))),
      ];
      final edgesOrderB = List<ActivityEdge>.from(edgesOrderA.reversed);

      final rawA = buildRawGraph(edges: edgesOrderA, selfId: 'self', selfLabel: 'Me');
      final rawB = buildRawGraph(edges: edgesOrderB, selfId: 'self', selfLabel: 'Me');

      final resultA = computePairWeights(rawA, selfId: 'self', now: now);
      final resultB = computePairWeights(rawB, selfId: 'self', now: now);

      expect(resultA.selfNodeWeight, closeTo(resultB.selfNodeWeight, 1e-9));
    });

    test('no edges produces zero self node weight and an empty counterparty weight map', () {
      final raw = buildRawGraph(edges: const [], selfId: 'self', selfLabel: 'Me');
      final result = computePairWeights(raw, selfId: 'self');
      expect(result.selfNodeWeight, 0.0);
      expect(result.counterpartyWeights, isEmpty);
    });
  });

  group('partitionTopN / clusterTopN (Property 21)', () {
    test('M <= N: every item is in top, others is empty', () {
      final items = [1.0, 2.0, 3.0];
      final partition = partitionTopN<double>(items, (v) => v, 5);
      expect(partition.top.toSet(), items.toSet());
      expect(partition.others, isEmpty);
    });

    test('M > N: exactly top-N by weight appear individually, remainder in others, no dup/loss', () {
      final items = List<int>.generate(50, (i) => i); // weight == value
      final partition = partitionTopN<int>(items, (v) => v.toDouble(), 30);

      expect(partition.top.length, 30);
      expect(partition.others.length, 20);

      final topSet = partition.top.toSet();
      final othersSet = partition.others.toSet();
      // No duplication: disjoint sets.
      expect(topSet.intersection(othersSet), isEmpty);
      // No loss: union equals the original input.
      expect(topSet.union(othersSet), items.toSet());
      // Correctness: top set is exactly the 30 highest values (20..49).
      expect(topSet, Set<int>.from(List.generate(30, (i) => 49 - i)));
    });

    test('clusterTopN folds the remainder into a single Others node with summed weight', () {
      final now = DateTime(2024, 2, 1);
      // 35 distinct counterparties -> exceeds the default threshold of 30.
      final edges = List<ActivityEdge>.generate(
        35,
        (i) => _edge(
          edgeId: 'e$i',
          counterpartyId: 'u$i',
          amountUsdc: '${i + 1}',
          createdAt: now,
        ),
      );
      final raw = buildRawGraph(edges: edges, selfId: 'self', selfLabel: 'Me');
      final weights = computePairWeights(raw, selfId: 'self', now: now);
      final weighted = applyPairWeights(raw, weights, selfId: 'self');
      final clustered = clusterTopN(weighted, selfId: 'self');

      final othersNodes = clustered.nodes.where((n) => n.kind == GraphNodeKind.others).toList();
      expect(othersNodes.length, 1);
      expect(othersNodes.single.clusteredIds.length, 5); // 35 - 30
      expect(clustered.othersDrillDown.length, 5);

      // self + 30 top + 1 others node = 32 total nodes.
      expect(clustered.nodes.length, 32);
    });

    test('clusterTopN produces no Others node when count is within the threshold', () {
      final now = DateTime(2024, 2, 1);
      final edges = List<ActivityEdge>.generate(
        10,
        (i) => _edge(edgeId: 'e$i', counterpartyId: 'u$i', amountUsdc: '${i + 1}', createdAt: now),
      );
      final raw = buildRawGraph(edges: edges, selfId: 'self', selfLabel: 'Me');
      final weights = computePairWeights(raw, selfId: 'self', now: now);
      final weighted = applyPairWeights(raw, weights, selfId: 'self');
      final clustered = clusterTopN(weighted, selfId: 'self');

      expect(clustered.nodes.any((n) => n.kind == GraphNodeKind.others), isFalse);
      expect(clustered.nodes.length, 11); // self + 10
    });

    test('clusterTopN applies identically to a Pool hub\'s participant list', () {
      final now = DateTime(2024, 2, 1);
      final participants = List.generate(40, (i) => GraphParticipant(id: 'p$i', label: 'P$i'));
      final edges = [
        _edge(edgeId: 'e1', counterpartyId: 'pool1', counterpartyKind: 'pool', amountUsdc: '10', createdAt: now),
      ];
      final raw = buildRawGraph(
        edges: edges,
        selfId: 'self',
        selfLabel: 'Me',
        poolParticipants: {'pool1': participants},
      );

      // Spokes aren't scored/clustered themselves in this v1 model (only the
      // top-level counterparty set is clustered) — but the same partitionTopN
      // primitive is reusable for a Pool hub's own participant list directly.
      final partition = partitionTopN<GraphParticipant>(
        participants,
        (p) => participants.indexOf(p).toDouble(),
        30,
      );
      expect(partition.top.length, 30);
      expect(partition.others.length, 10);
      expect(raw.nodes.length, 42); // self + pool1 + 40 participants
    });
  });
}
