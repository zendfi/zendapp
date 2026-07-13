// Example-based test for Property 23: Threaded and Graph views are
// consistent over the same authorized snapshot (Req 19.3).
//
// Both `ThreadedActivityScreen` (via `groupByCounterparty`) and
// `GraphViewScreen` (via `buildRawGraph`) derive their rendering data from
// the exact same `List<ActivityEdge>` — `ZendAppModel.threadedActivityEdges`
// — with no separate fetch or authorization path (Req 19.1, 19.2). This
// test verifies that derivation is consistent: the total edge count and
// total (non-hidden) transacted amount computed by each view's own
// transform agree for the same input snapshot.

import 'package:flutter_test/flutter_test.dart';
import 'package:zendapp/src/features/activity/activity_grouping.dart';
import 'package:zendapp/src/features/activity/graph_model.dart';
import 'package:zendapp/src/models/activity_edge.dart';

ActivityEdge _edge({
  required String edgeId,
  required String counterpartyId,
  String? amountUsdc,
  bool amountHidden = false,
  required DateTime createdAt,
}) {
  return ActivityEdge(
    edgeId: edgeId,
    edgeKind: ActivityEdgeKind.zendTransfer,
    counterparty: ActivityCounterparty(kind: 'user', id: counterpartyId),
    amountUsdc: amountUsdc,
    amountHidden: amountHidden,
    direction: 'outgoing',
    effectiveTier: VisibilityTier.private,
    isDirectParticipant: true,
    createdAt: createdAt,
  );
}

void main() {
  test('total edge count matches between Threaded grouping and Graph construction', () {
    final edges = [
      _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '10', createdAt: DateTime(2024, 1, 1)),
      _edge(edgeId: 'e2', counterpartyId: 'u1', amountUsdc: '5', createdAt: DateTime(2024, 1, 2)),
      _edge(edgeId: 'e3', counterpartyId: 'u2', amountUsdc: '20', createdAt: DateTime(2024, 1, 3)),
      _edge(edgeId: 'e4', counterpartyId: 'u3', amountUsdc: null, amountHidden: true, createdAt: DateTime(2024, 1, 4)),
    ];

    final threads = groupByCounterparty(edges);
    final threadedEdgeCount = threads.fold<int>(0, (s, t) => s + t.edges.length);

    final graph = buildRawGraph(edges: edges, selfId: 'self', selfLabel: 'Me');
    final graphEdgeCount = graph.edges.where((e) => !e.isSpoke).length;

    expect(threadedEdgeCount, edges.length);
    expect(graphEdgeCount, edges.length);
    expect(threadedEdgeCount, graphEdgeCount);
  });

  test('total non-hidden transacted amount matches between the two views\' derivations', () {
    final edges = [
      _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '10.50', createdAt: DateTime(2024, 1, 1)),
      _edge(edgeId: 'e2', counterpartyId: 'u2', amountUsdc: '5.25', createdAt: DateTime(2024, 1, 2)),
      // Hidden amount must not contribute to either view's total.
      _edge(edgeId: 'e3', counterpartyId: 'u3', amountUsdc: null, amountHidden: true, createdAt: DateTime(2024, 1, 3)),
    ];

    final threads = groupByCounterparty(edges);
    final threadedTotal = threads.fold<double>(0.0, (s, t) => s + t.runningTotal);

    final graph = buildRawGraph(edges: edges, selfId: 'self', selfLabel: 'Me');
    final graphTotal = graph.edges.where((e) => !e.isSpoke).fold<double>(0.0, (s, e) => s + e.amountUsdc);

    expect(threadedTotal, closeTo(15.75, 1e-9));
    expect(graphTotal, closeTo(15.75, 1e-9));
    expect(threadedTotal, closeTo(graphTotal, 1e-9));
  });

  test('an empty snapshot produces zero edges and zero total in both views', () {
    final threads = groupByCounterparty(const []);
    final graph = buildRawGraph(edges: const [], selfId: 'self', selfLabel: 'Me');

    expect(threads, isEmpty);
    expect(graph.edges, isEmpty);
  });

  test('changing the input snapshot changes both views\' derived totals identically', () {
    final snapshotA = [
      _edge(edgeId: 'e1', counterpartyId: 'u1', amountUsdc: '10', createdAt: DateTime(2024, 1, 1)),
    ];
    final snapshotB = [
      ...snapshotA,
      _edge(edgeId: 'e2', counterpartyId: 'u2', amountUsdc: '20', createdAt: DateTime(2024, 1, 2)),
    ];

    double threadedTotal(List<ActivityEdge> e) =>
        groupByCounterparty(e).fold<double>(0.0, (s, t) => s + t.runningTotal);
    double graphTotal(List<ActivityEdge> e) => buildRawGraph(edges: e, selfId: 'self', selfLabel: 'Me')
        .edges
        .where((edge) => !edge.isSpoke)
        .fold<double>(0.0, (s, edge) => s + edge.amountUsdc);

    expect(threadedTotal(snapshotB) - threadedTotal(snapshotA), closeTo(20.0, 1e-9));
    expect(graphTotal(snapshotB) - graphTotal(snapshotA), closeTo(20.0, 1e-9));
  });
}
