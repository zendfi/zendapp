// Regression test for feedVerbFor's word-variation logic — the same edge
// must always render the same verb (deterministic, no flicker on rebuild),
// while outgoing vs incoming edges draw from distinct verb pools.

import 'package:flutter_test/flutter_test.dart';
import 'package:zendapp/src/features/activity/activity_grouping.dart';
import 'package:zendapp/src/models/activity_edge.dart';

ActivityEdge _edge({required String edgeId, required String direction}) {
  return ActivityEdge(
    edgeId: edgeId,
    edgeKind: ActivityEdgeKind.zendTransfer,
    counterparty: const ActivityCounterparty(kind: 'user', id: 'u1', zendtag: 'friend'),
    amountUsdc: '10',
    amountHidden: false,
    direction: direction,
    effectiveTier: VisibilityTier.private,
    isDirectParticipant: true,
    createdAt: DateTime(2024, 1, 1),
  );
}

void main() {
  test('feedVerbFor is deterministic for the same edge id', () {
    final edge = _edge(edgeId: 'e1', direction: 'outgoing');
    final v1 = feedVerbFor(edge);
    final v2 = feedVerbFor(edge);
    expect(v1, v2);
  });

  test('outgoing edges never draw from the incoming verb pool and vice versa', () {
    for (var i = 0; i < 20; i++) {
      final outgoing = feedVerbFor(_edge(edgeId: 'out$i', direction: 'outgoing'));
      final incoming = feedVerbFor(_edge(edgeId: 'in$i', direction: 'incoming'));
      expect(outgoing.contains('you'), isFalse, reason: 'outgoing verb "$outgoing" should not read as incoming');
      expect(incoming.contains('you'), isTrue, reason: 'incoming verb "$incoming" should read as directed at the viewer');
    }
  });

  test('different edge ids can produce different verbs (variety exists)', () {
    final verbs = {for (var i = 0; i < 20; i++) feedVerbFor(_edge(edgeId: 'e$i', direction: 'outgoing'))};
    expect(verbs.length, greaterThan(1));
  });
}
