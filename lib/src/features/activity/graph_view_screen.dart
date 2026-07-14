import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'graph_model.dart';

/// Phase 3 Graph_View — an opt-in node/edge visualization of the same
/// visibility-authorized `ActivityEdge` data the Threaded_Activity_View
/// renders as grouped threads (Req 16, Req 19). Reachable only via an
/// explicit toggle from the Activity screen; never the default view
/// (Req 16.4, 16.5).
///
/// Retrieves its data exclusively from `ZendAppModel.threadedActivityEdges`
/// (the same `Activity_Data_Service`-backed state Phase 2 populates) — no
/// separate fetch or authorization path is introduced here (Req 19.1, 19.2).
class GraphViewScreen extends StatefulWidget {
  const GraphViewScreen({super.key, required this.onToggleView});

  /// Invoked when the user taps the toggle to switch back to the
  /// Threaded_Activity_View.
  final VoidCallback onToggleView;

  @override
  State<GraphViewScreen> createState() => _GraphViewScreenState();
}

class _GraphViewScreenState extends State<GraphViewScreen> {
  GraphModel? _model;
  _ForceDirectedLayout? _layout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildModel());
  }

  void _rebuildModel() {
    final zendModel = ZendScope.of(context);
    final selfId = zendModel.currentUserId ?? 'self';
    final selfLabel = zendModel.currentZendtag ?? 'You';

    final graph = buildGraphModel(
      edges: zendModel.threadedActivityEdges,
      selfId: selfId,
      selfLabel: selfLabel,
    );

    if (mounted) {
      setState(() {
        _model = graph;
        _layout = _ForceDirectedLayout(graph);
      });
    }
  }

  void _openOthersDrillDown(GraphModel model) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OthersDrillDownSheet(nodes: model.othersDrillDown),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final zendModel = ZendScope.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Relationship Graph',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onToggleView,
                    icon: Icon(Icons.list_alt_outlined, color: zt.textSecondary),
                    tooltip: 'Switch to threaded view',
                  ),
                ],
              ),
            ),
            Expanded(
              child: (zendModel.threadedActivityLoading && _model == null)
                  ? const Center(child: ZendLoader(size: 24))
                  : (_model == null || _model!.nodes.length <= 1)
                      ? Center(
                          child: Text(
                            'No relationships to visualize yet',
                            style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final layout = _layout!;
                            layout.ensureSized(constraints.biggest);
                            final positions = layout.settle();
                            return _GraphCanvas(
                              model: _model!,
                              positions: positions,
                              size: constraints.biggest,
                              onTapOthers: () => _openOthersDrillDown(_model!),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Force-directed layout (Req 18.3's "lightweight in-Dart physics") ──────
//
// A basic spring/repulsion simulation: every node pair repels, every edge's
// two endpoints attract. Capped iteration count (rather than open-ended
// animation) keeps this cheap and deterministic for the ≤31-node cap Req 18
// guarantees, per design.md's "computationally cheap enough to run entirely
// on-device" rendering-approach decision.
class _ForceDirectedLayout {
  _ForceDirectedLayout(this.model);

  final GraphModel model;
  final Map<String, Offset> _positions = {};
  Size? _size;
  bool _settled = false;

  static const _maxIterations = 120;
  static const _repulsion = 3200.0;
  static const _springLength = 110.0;
  static const _springStrength = 0.02;
  static const _damping = 0.85;

  void ensureSized(Size size) {
    if (_size == size) return;
    _size = size;
    _settled = false;
    _positions.clear();
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 40;
    final rand = math.Random(42); // deterministic layout across rebuilds
    for (var i = 0; i < model.nodes.length; i++) {
      final node = model.nodes[i];
      if (node.id == _selfId) {
        _positions[node.id] = center;
        continue;
      }
      final angle = (i / math.max(1, model.nodes.length - 1)) * 2 * math.pi;
      final jitter = (rand.nextDouble() - 0.5) * 20;
      _positions[node.id] = center +
          Offset(math.cos(angle) * (radius * 0.8 + jitter), math.sin(angle) * (radius * 0.8 + jitter));
    }
  }

  String get _selfId {
    // The self node is whichever node has no incoming edge pointing at it
    // as a target from another non-spoke edge's source equal to itself —
    // simpler: the self node is the source of every direct (non-spoke) edge.
    for (final e in model.edges) {
      if (!e.isSpoke) return e.sourceId;
    }
    return model.nodes.isNotEmpty ? model.nodes.first.id : '';
  }

  Map<String, Offset> settle() {
    if (_settled || _size == null) return _positions;

    final velocities = <String, Offset>{for (final n in model.nodes) n.id: Offset.zero};
    final size = _size!;

    for (var iter = 0; iter < _maxIterations; iter++) {
      final forces = <String, Offset>{for (final n in model.nodes) n.id: Offset.zero};

      // Repulsion between every pair.
      for (var i = 0; i < model.nodes.length; i++) {
        for (var j = i + 1; j < model.nodes.length; j++) {
          final a = model.nodes[i].id;
          final b = model.nodes[j].id;
          final pa = _positions[a]!;
          final pb = _positions[b]!;
          var delta = pa - pb;
          var distance = delta.distance;
          if (distance < 1) {
            distance = 1;
            delta = const Offset(1, 0);
          }
          final force = delta / distance * (_repulsion / (distance * distance));
          forces[a] = forces[a]! + force;
          forces[b] = forces[b]! - force;
        }
      }

      // Spring attraction along edges toward a resting length.
      for (final e in model.edges) {
        final pa = _positions[e.sourceId];
        final pb = _positions[e.targetId];
        if (pa == null || pb == null) continue;
        var delta = pb - pa;
        var distance = delta.distance;
        if (distance < 1) {
          distance = 1;
          delta = const Offset(1, 0);
        }
        final displacement = distance - _springLength;
        final force = delta / distance * (_springStrength * displacement);
        forces[e.sourceId] = forces[e.sourceId]! + force;
        forces[e.targetId] = forces[e.targetId]! - force;
      }

      var totalMovement = 0.0;
      for (final node in model.nodes) {
        if (node.id == _selfId) continue; // keep self anchored at center
        final v = (velocities[node.id]! + forces[node.id]!) * _damping;
        velocities[node.id] = v;
        final newPos = _positions[node.id]! + v;
        // Clamp within the canvas with margin.
        final clamped = Offset(
          newPos.dx.clamp(30.0, math.max(30.0, size.width - 30.0)),
          newPos.dy.clamp(30.0, math.max(30.0, size.height - 30.0)),
        );
        totalMovement += (clamped - _positions[node.id]!).distance;
        _positions[node.id] = clamped;
      }

      if (totalMovement < 0.5) break; // converged early
    }

    _settled = true;
    return _positions;
  }
}

// ── Rendering ────────────────────────────────────────────────────────────────

class _GraphCanvas extends StatelessWidget {
  const _GraphCanvas({
    required this.model,
    required this.positions,
    required this.size,
    required this.onTapOthers,
  });

  final GraphModel model;
  final Map<String, Offset> positions;
  final Size size;
  final VoidCallback onTapOthers;

  double _nodeRadius(GraphNode node) {
    final base = node.kind == GraphNodeKind.others ? 22.0 : 24.0;
    final boost = math.min(20.0, node.visualWeight * 16.0);
    return base + boost;
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          CustomPaint(
            size: size,
            painter: _GraphEdgePainter(model: model, positions: positions, color: zt.border),
          ),
          for (final node in model.nodes)
            if (positions[node.id] != null)
              Positioned(
                left: positions[node.id]!.dx - _nodeRadius(node),
                top: positions[node.id]!.dy - _nodeRadius(node),
                child: GestureDetector(
                  onTap: node.kind == GraphNodeKind.others ? onTapOthers : null,
                  child: _GraphNodeWidget(node: node, radius: _nodeRadius(node)),
                ),
              ),
        ],
      ),
    );
  }
}

class _GraphEdgePainter extends CustomPainter {
  _GraphEdgePainter({required this.model, required this.positions, required this.color});

  final GraphModel model;
  final Map<String, Offset> positions;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in model.edges) {
      final from = positions[edge.sourceId];
      final to = positions[edge.targetId];
      if (from == null || to == null) continue;

      final strokeWidth = edge.isSpoke ? 1.5 : 1.0 + edge.visualWeight * 3.0;
      final paint = Paint()
        ..color = edge.isSpoke ? color.withValues(alpha: 0.5) : color.withValues(alpha: 0.9)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;

      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphEdgePainter oldDelegate) {
    return oldDelegate.model != model || oldDelegate.positions != positions;
  }
}

class _GraphNodeWidget extends StatelessWidget {
  const _GraphNodeWidget({required this.node, required this.radius});

  final GraphNode node;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    switch (node.kind) {
      case GraphNodeKind.pool:
        return _LabeledNode(
          label: node.label,
          zt: zt,
          child: CircleAvatar(
            radius: radius,
            backgroundColor: zt.accent.withValues(alpha: 0.18),
            child: Icon(Icons.groups_outlined, color: zt.accent, size: radius * 0.9),
          ),
        );
      case GraphNodeKind.others:
        return _LabeledNode(
          label: node.label,
          zt: zt,
          child: CircleAvatar(
            radius: radius,
            backgroundColor: zt.border,
            child: Icon(Icons.more_horiz, color: zt.textSecondary, size: radius * 0.9),
          ),
        );
      case GraphNodeKind.user:
        return _LabeledNode(
          label: node.label,
          zt: zt,
          child: ZendAvatar(
            radius: radius,
            photoUrl: node.avatarUrl,
            initials: node.initialLetter,
          ),
        );
    }
  }
}

class _LabeledNode extends StatelessWidget {
  const _LabeledNode({required this.child, required this.label, required this.zt});

  final Widget child;
  final String label;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 64),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'DMSans', fontSize: 10, color: zt.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ── Others cluster drill-down (Req 18.2) ────────────────────────────────────

class _OthersDrillDownSheet extends StatefulWidget {
  const _OthersDrillDownSheet({required this.nodes});

  final List<GraphNode> nodes;

  @override
  State<_OthersDrillDownSheet> createState() => _OthersDrillDownSheetState();
}

class _OthersDrillDownSheetState extends State<_OthersDrillDownSheet> {
  static const _pageSize = 20;
  int _visibleCount = _pageSize;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final visible = widget.nodes.take(_visibleCount).toList();
    final hasMore = _visibleCount < widget.nodes.length;

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
                decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(ZendRadii.pill)),
              ),
            ),
            Text(
              '${widget.nodes.length} more relationships',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: visible.length,
                separatorBuilder: (_, _) => Divider(color: zt.border, height: 1),
                itemBuilder: (context, i) {
                  final node = visible[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ZendAvatar(
                      radius: 18,
                      photoUrl: node.avatarUrl,
                      initials: node.initialLetter,
                    ),
                    title: Text(node.label, style: TextStyle(fontFamily: 'DMSans', color: zt.textPrimary)),
                  );
                },
              ),
            ),
            if (hasMore) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _visibleCount += _pageSize),
                child: Text(
                  'Load more',
                  style: TextStyle(fontFamily: 'DMSans', fontWeight: FontWeight.w600, color: zt.accent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
