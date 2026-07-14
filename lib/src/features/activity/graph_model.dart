/// Pure, widget-free model for the Phase 3 Graph_View: graph construction
/// (Req 16), visual weight scoring (Req 17), and top-N/Others clustering
/// (Req 18). Kept free of Flutter imports so each stage is directly
/// unit-testable, matching the pattern established by `activity_grouping.dart`
/// in Phase 2.
///
/// Deliberately split into three independent pure functions mirroring the
/// three implementation tasks/correctness properties:
///  - `buildRawGraph`      → Property 18 (faithful structural transform)
///  - `computePairWeights` → Property 20 (scoring bounds/monotonicity)
///  - `partitionTopN`      → Property 21 (lossless top-N/Others partition)
library;

import 'dart:math' as math;

import '../../models/activity_edge.dart';

// ── Graph structure (Req 16) ────────────────────────────────────────────────

enum GraphNodeKind { user, pool, others }

class GraphNode {
  final String id;
  final GraphNodeKind kind;
  final String label;
  final String? avatarUrl;
  final double visualWeight;

  /// Populated only for a `GraphNodeKind.others` node — the counterparty ids
  /// folded into this cluster, for the Req 18.2 drill-down.
  final List<String> clusteredIds;

  const GraphNode({
    required this.id,
    required this.kind,
    required this.label,
    this.avatarUrl,
    this.visualWeight = 0.0,
    this.clusteredIds = const [],
  });

  /// First letter suitable for an avatar-initial fallback — strips a
  /// leading '@' from [label] (since labels are often `@zendtag`) so the
  /// avatar never shows a bare "@" as its initial.
  String get initialLetter {
    final stripped = label.startsWith('@') ? label.substring(1) : label;
    return stripped.isNotEmpty ? stripped[0].toUpperCase() : '?';
  }

  GraphNode copyWith({double? visualWeight}) {
    return GraphNode(
      id: id,
      kind: kind,
      label: label,
      avatarUrl: avatarUrl,
      visualWeight: visualWeight ?? this.visualWeight,
      clusteredIds: clusteredIds,
    );
  }
}

class GraphEdge {
  final String id;
  final String sourceId;
  final String targetId;

  /// Raw underlying data used for weight computation. Zero/null for
  /// synthetic edges (Pool spokes, the "Others" cluster edge) that don't
  /// correspond to a single dated/valued Activity_Edge.
  final double amountUsdc;
  final DateTime? createdAt;

  /// True for a Pool→participant spoke edge (Req 16.3), as opposed to a
  /// direct Activity_Edge or a self→Others cluster edge.
  final bool isSpoke;

  final double visualWeight;

  const GraphEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    this.amountUsdc = 0.0,
    this.createdAt,
    this.isSpoke = false,
    this.visualWeight = 0.0,
  });

  GraphEdge copyWith({double? visualWeight}) {
    return GraphEdge(
      id: id,
      sourceId: sourceId,
      targetId: targetId,
      amountUsdc: amountUsdc,
      createdAt: createdAt,
      isSpoke: isSpoke,
      visualWeight: visualWeight ?? this.visualWeight,
    );
  }
}

class GraphModel {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  /// Present only after `partitionTopN`/clustering — the full set of nodes
  /// folded into the "Others" cluster, for the Req 18.2 drill-down view.
  final List<GraphNode> othersDrillDown;

  const GraphModel({
    required this.nodes,
    required this.edges,
    this.othersDrillDown = const [],
  });
}

/// Describes a Pool participant supplied alongside a Pool's Activity_Edges
/// (e.g. from `getPoolContributors`), used only to add the Req 16.3 spoke
/// edges — this is not itself an Activity_Edge.
class GraphParticipant {
  final String id;
  final String label;
  final String? avatarUrl;

  const GraphParticipant({required this.id, required this.label, this.avatarUrl});
}

/// Req 16.1-16.3: the pure structural transform from a requesting User's
/// authorized Activity_Edges (+ optional Pool participant lists) into a
/// node/edge graph model, with no weighting or clustering applied yet.
///
/// Property 18 guarantees: the node set exactly equals the distinct
/// Users/Pools referenced by the input (self + every edge's counterparty +
/// every participant of a Pool present in the data); the edge set contains
/// exactly one entry per input Activity_Edge (no edges added or dropped) —
/// plus exactly one additional spoke edge per Pool participant supplied for
/// a Pool that is present in the data.
GraphModel buildRawGraph({
  required List<ActivityEdge> edges,
  required String selfId,
  required String selfLabel,
  Map<String, List<GraphParticipant>> poolParticipants = const {},
}) {
  final nodesById = <String, GraphNode>{
    selfId: GraphNode(id: selfId, kind: GraphNodeKind.user, label: selfLabel),
  };
  final graphEdges = <GraphEdge>[];

  for (final edge in edges) {
    final counterparty = edge.counterparty;
    nodesById.putIfAbsent(
      counterparty.id,
      () => GraphNode(
        id: counterparty.id,
        kind: counterparty.isPool ? GraphNodeKind.pool : GraphNodeKind.user,
        label: counterparty.isPool ? (counterparty.poolName ?? 'Pool') : counterparty.displayLabel,
        avatarUrl: counterparty.avatarUrl,
      ),
    );
    graphEdges.add(GraphEdge(
      id: edge.edgeId,
      sourceId: selfId,
      targetId: counterparty.id,
      amountUsdc: edge.amountHidden ? 0.0 : (double.tryParse(edge.amountUsdc ?? '') ?? 0.0),
      createdAt: edge.createdAt,
    ));
  }

  // Req 16.3: exactly one spoke edge per Pool participant "present in the
  // data" — only for Pools already referenced above via an Activity_Edge.
  for (final entry in poolParticipants.entries) {
    final poolId = entry.key;
    if (!nodesById.containsKey(poolId)) continue;
    for (final participant in entry.value) {
      nodesById.putIfAbsent(
        participant.id,
        () => GraphNode(
          id: participant.id,
          kind: GraphNodeKind.user,
          label: participant.label,
          avatarUrl: participant.avatarUrl,
        ),
      );
      graphEdges.add(GraphEdge(
        id: 'spoke_${poolId}_${participant.id}',
        sourceId: poolId,
        targetId: participant.id,
        isSpoke: true,
      ));
    }
  }

  return GraphModel(nodes: nodesById.values.toList(), edges: graphEdges);
}

// ── Visual weight scoring (Req 17) ──────────────────────────────────────────

/// v1 scoring coefficients and constants, per design.md's "Scoring function
/// v1 coefficients" section. Modeled as configuration (not hardcoded call
/// sites) so a future server-driven `graph_scoring_config` can be plumbed in
/// without changing any call site's shape — see design.md Req 17.6.
class GraphScoringConfig {
  final double frequencyWeight;
  final double recencyWeight;
  final double amountWeight;
  final double recencyHalfLifeDays;
  final int displayThreshold;

  const GraphScoringConfig({
    this.frequencyWeight = 0.4,
    this.recencyWeight = 0.3,
    this.amountWeight = 0.3,
    this.recencyHalfLifeDays = 14,
    this.displayThreshold = 30,
  });
}

const defaultGraphScoringConfig = GraphScoringConfig();

/// Req 17.2/17.4: min-max normalization to `[0, 1]`. A `max` of zero (no
/// relationships have any weight on this axis) normalizes everything to 0
/// rather than dividing by zero.
double normalizedScore(double value, double max) {
  if (max <= 0) return 0.0;
  return (value / max).clamp(0.0, 1.0);
}

/// Req 17.3: exponential decay, monotonically non-increasing as
/// `daysSince` grows. `daysSince <= 0` (an activity "now" or in the future,
/// from a clock-skew edge case) scores the maximum `1.0`.
double recencyScoreForDays(double daysSince, double halfLifeDays) {
  if (daysSince <= 0) return 1.0;
  return math.pow(2, -daysSince / halfLifeDays).toDouble();
}

double _recencyScoreForDate(DateTime lastActivity, DateTime now, double halfLifeDays) {
  final daysSince = now.difference(lastActivity).inMinutes / (60.0 * 24.0);
  return recencyScoreForDays(daysSince, halfLifeDays);
}

/// Per-counterparty edge weight + the self node's aggregate node weight,
/// computed over a raw (unclustered) [GraphModel] per `buildRawGraph`.
class PairWeightResult {
  final Map<String, double> counterpartyWeights;
  final double selfNodeWeight;

  const PairWeightResult({
    required this.counterpartyWeights,
    required this.selfNodeWeight,
  });
}

/// Req 17.1-17.5: computes `edge_weight(self, counterparty)` for every
/// distinct counterparty referenced by `raw`'s direct (non-spoke) edges, and
/// `node_weight(self) = sum(edge_weight(self, c) for c in counterparties)`.
///
/// Property 20 guarantees: frequency_score/amount_score are normalized to
/// `[0, 1]` and monotonically non-decreasing in their raw inputs; recency_score
/// is monotonically non-increasing in time-since-last-activity; the resulting
/// node weight is a deterministic, order-independent (summation-based)
/// function of its incident edge weights.
PairWeightResult computePairWeights(
  GraphModel raw, {
  required String selfId,
  GraphScoringConfig config = defaultGraphScoringConfig,
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();

  final byCounterparty = <String, List<GraphEdge>>{};
  for (final e in raw.edges) {
    if (e.isSpoke || e.sourceId != selfId) continue;
    byCounterparty.putIfAbsent(e.targetId, () => []).add(e);
  }

  if (byCounterparty.isEmpty) {
    return const PairWeightResult(counterpartyWeights: {}, selfNodeWeight: 0.0);
  }

  final maxFrequency =
      byCounterparty.values.map((l) => l.length).fold<int>(0, math.max).toDouble();
  final maxAmount = byCounterparty.values
      .map((l) => l.fold<double>(0.0, (s, e) => s + e.amountUsdc))
      .fold<double>(0.0, math.max);

  final weights = <String, double>{};
  for (final entry in byCounterparty.entries) {
    final pairEdges = entry.value;
    final frequency = pairEdges.length.toDouble();
    final amount = pairEdges.fold<double>(0.0, (s, e) => s + e.amountUsdc);
    final mostRecent = pairEdges
        .map((e) => e.createdAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (latest, dt) => (latest == null || dt.isAfter(latest)) ? dt : latest);

    final frequencyScore = normalizedScore(frequency, maxFrequency);
    final amountScore = normalizedScore(amount, maxAmount);
    final recencyScore =
        mostRecent != null ? _recencyScoreForDate(mostRecent, effectiveNow, config.recencyHalfLifeDays) : 0.0;

    weights[entry.key] = config.frequencyWeight * frequencyScore +
        config.recencyWeight * recencyScore +
        config.amountWeight * amountScore;
  }

  final selfNodeWeight = weights.values.fold<double>(0.0, (s, w) => s + w);
  return PairWeightResult(counterpartyWeights: weights, selfNodeWeight: selfNodeWeight);
}

/// Applies a [PairWeightResult] onto `raw`, producing a new [GraphModel]
/// with each node/edge's `visualWeight` populated. Pool spoke edges/nodes
/// keep weight `0.0` — only the self↔counterparty relationship carries a
/// scored weight per design.md (spokes are structural, not scored).
GraphModel applyPairWeights(GraphModel raw, PairWeightResult result, {required String selfId}) {
  final nodes = raw.nodes.map((n) {
    if (n.id == selfId) return n.copyWith(visualWeight: result.selfNodeWeight);
    final w = result.counterpartyWeights[n.id];
    return w != null ? n.copyWith(visualWeight: w) : n;
  }).toList();

  final edges = raw.edges.map((e) {
    if (e.isSpoke) return e;
    final w = result.counterpartyWeights[e.targetId];
    return w != null ? e.copyWith(visualWeight: w) : e;
  }).toList();

  return GraphModel(nodes: nodes, edges: edges, othersDrillDown: raw.othersDrillDown);
}

// ── Top-N / Others clustering (Req 18) ──────────────────────────────────────

class WeightedPartition<T> {
  final List<T> top;
  final List<T> others;

  const WeightedPartition({required this.top, required this.others});
}

/// Req 18.1-18.3: generic top-N-by-weight partition, usable identically for
/// a User's counterparties or a Pool hub's participant list (design.md's
/// "the same top-N-with-drill-down strategy" applied to both).
///
/// Property 21 guarantees: if `items.length <= n`, every item is in `top`
/// and `others` is empty; otherwise `top` contains exactly the highest-`n`
/// items by weight, `others` contains exactly the rest, and no item appears
/// in both or in neither (lossless, non-duplicating partition).
WeightedPartition<T> partitionTopN<T>(
  List<T> items,
  double Function(T) weightOf,
  int n,
) {
  if (items.length <= n) {
    return WeightedPartition(top: List<T>.of(items), others: const []);
  }
  final sorted = List<T>.of(items)..sort((a, b) => weightOf(b).compareTo(weightOf(a)));
  return WeightedPartition(top: sorted.sublist(0, n), others: sorted.sublist(n));
}

/// Req 18.1: applies [partitionTopN] to a weighted (post-`computePairWeights`)
/// [GraphModel]'s counterparty nodes, folding the remainder into a single
/// "Others" node (Req 18.1) whose weight is the sum of the folded nodes'
/// weights, and whose `clusteredIds` supports the Req 18.2 drill-down.
GraphModel clusterTopN(
  GraphModel weighted, {
  required String selfId,
  GraphScoringConfig config = defaultGraphScoringConfig,
}) {
  final nodesById = {for (final n in weighted.nodes) n.id: n};
  final selfNode = nodesById[selfId]!;

  final counterpartyNodes = weighted.nodes.where((n) => n.id != selfId && n.kind != GraphNodeKind.others).toList();

  final partition = partitionTopN<GraphNode>(counterpartyNodes, (n) => n.visualWeight, config.displayThreshold);

  final resultNodes = <GraphNode>[selfNode, ...partition.top];
  final resultEdges = <GraphEdge>[];

  final topIds = partition.top.map((n) => n.id).toSet();
  for (final e in weighted.edges) {
    if (e.isSpoke) {
      // Keep spokes only for Pool nodes that made the cut.
      if (topIds.contains(e.sourceId)) resultEdges.add(e);
      continue;
    }
    if (e.sourceId == selfId && topIds.contains(e.targetId)) {
      resultEdges.add(e);
    }
  }

  if (partition.others.isNotEmpty) {
    final othersWeight = partition.others.fold<double>(0.0, (s, n) => s + n.visualWeight);
    resultNodes.add(GraphNode(
      id: '__others__',
      kind: GraphNodeKind.others,
      label: '${partition.others.length} others',
      visualWeight: othersWeight,
      clusteredIds: partition.others.map((n) => n.id).toList(),
    ));
    resultEdges.add(GraphEdge(
      id: '${selfId}___others__',
      sourceId: selfId,
      targetId: '__others__',
      visualWeight: othersWeight,
    ));
  }

  return GraphModel(nodes: resultNodes, edges: resultEdges, othersDrillDown: partition.others);
}

/// Convenience end-to-end pipeline: raw construction → weighting →
/// clustering, for callers (the Graph_View widget) that just want the final
/// renderable model. Each stage remains independently callable/testable
/// above.
GraphModel buildGraphModel({
  required List<ActivityEdge> edges,
  required String selfId,
  required String selfLabel,
  Map<String, List<GraphParticipant>> poolParticipants = const {},
  GraphScoringConfig config = defaultGraphScoringConfig,
  DateTime? now,
}) {
  final raw = buildRawGraph(
    edges: edges,
    selfId: selfId,
    selfLabel: selfLabel,
    poolParticipants: poolParticipants,
  );
  final weights = computePairWeights(raw, selfId: selfId, config: config, now: now);
  final weighted = applyPairWeights(raw, weights, selfId: selfId);
  return clusterTopN(weighted, selfId: selfId, config: config);
}
