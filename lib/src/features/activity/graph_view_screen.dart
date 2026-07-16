import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'graph_model.dart';
import 'person_activity_screen.dart';
import 'package:solar_icons/solar_icons.dart';

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

class _GraphViewScreenState extends State<GraphViewScreen> with SingleTickerProviderStateMixin {
  GraphModel? _model;
  _PhysicsGraphLayout? _layout;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildModel());
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final layout = _layout;
    if (layout == null) return;
    final dtMs = (elapsed - _lastTick).inMilliseconds.clamp(0, 48);
    _lastTick = elapsed;
    if (dtMs <= 0) return;
    final moved = layout.step(dtMs / 1000.0);
    if (moved && mounted) setState(() {});
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
        _layout = _PhysicsGraphLayout(graph, selfId: selfId);
      });
    }
  }

  /// Req 6's "physics reactions on touch" — tapping a node gives it a small
  /// outward impulse that ripples to its neighbors via the live spring/
  /// repulsion simulation already running every frame, then everything
  /// settles back per the same physics. A manual per-node drag was
  /// considered but rejected: nesting a drag recognizer inside the
  /// InteractiveViewer's own pan/zoom recognizer for the same node area is
  /// a well-known Flutter gesture-arena conflict with no clean resolution;
  /// an impulse-on-tap gives a genuine, reliable physics reaction to touch
  /// without fighting the pan/zoom gesture.
  void _kickNode(GraphNode node) {
    _layout?.applyImpulse(node.id);
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

  void _openPersonActivity(GraphNode node) {
    _kickNode(node);
    final selfId = ZendScope.of(context).currentUserId ?? 'self';
    if (node.id == selfId || node.kind != GraphNodeKind.user) return;
    pushZendSlide(context, PersonActivityScreen(userId: node.id, label: node.label, avatarUrl: node.avatarUrl));
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
                      'Your Mutuals',
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
                    icon: Icon(SolarIconsBold.listArrowDown, color: zt.textSecondary),
                    tooltip: 'Switch to threaded view',
                  ),
                ],
              ),
            ),
            Expanded(
              child: (zendModel.threadedActivityLoading && _model == null)
                  ? Center(child: ZendLoader(size: 24))
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
                            return InteractiveViewer(
                              transformationController: _transformController,
                              minScale: 0.5,
                              maxScale: 3.0,
                              boundaryMargin: const EdgeInsets.all(200),
                              child: _GraphCanvas(
                                model: _model!,
                                positions: layout.positions,
                                size: constraints.biggest,
                                onTapOthers: () => _openOthersDrillDown(_model!),
                                onTapNode: _openPersonActivity,
                              ),
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

// ── Physics-driven force-directed layout (Req 18.3's "lightweight in-Dart
// physics", extended for Req 6's pan/zoom/touch-physics request) ──────────
//
// A basic spring/repulsion simulation: every node pair repels, every edge's
// two endpoints attract. Unlike the original one-shot "settle then freeze"
// version, this layout keeps a live velocity per node and is stepped every
// frame by a Ticker, so an external impulse (`applyImpulse`, fired on node
// tap) visibly ripples through the graph and settles back down — a genuine
// physics reaction to touch, not just a static picture. Still cheap enough
// to run at 60fps for the ≤31-node cap Req 18 guarantees.
class _PhysicsGraphLayout {
  _PhysicsGraphLayout(this.model, {required this.selfId});

  final GraphModel model;
  final String selfId;
  final Map<String, Offset> positions = {};
  final Map<String, Offset> _velocities = {};
  Size? _size;

  static const _repulsion = 3200.0;
  static const _springLength = 110.0;
  static const _springStrength = 0.9;
  static const _damping = 6.0; // velocity decay per second (exponential)
  static const _impulseMagnitude = 260.0;
  static const _velocitySleepThreshold = 0.5;

  void ensureSized(Size size) {
    if (_size == size) return;
    _size = size;
    positions.clear();
    _velocities.clear();
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 40;
    final rand = math.Random(42); // deterministic initial layout across rebuilds
    for (var i = 0; i < model.nodes.length; i++) {
      final node = model.nodes[i];
      _velocities[node.id] = Offset.zero;
      if (node.id == selfId) {
        positions[node.id] = center;
        continue;
      }
      final angle = (i / math.max(1, model.nodes.length - 1)) * 2 * math.pi;
      final jitter = (rand.nextDouble() - 0.5) * 20;
      positions[node.id] = center + Offset(math.cos(angle) * (radius * 0.8 + jitter), math.sin(angle) * (radius * 0.8 + jitter));
    }
  }

  /// Gives [nodeId] (and, via the ongoing spring simulation, its
  /// neighbors) a small outward kick — the "physics reaction on touch".
  void applyImpulse(String nodeId) {
    final pos = positions[nodeId];
    final size = _size;
    if (pos == null || size == null) return;
    final center = Offset(size.width / 2, size.height / 2);
    var direction = pos - center;
    if (direction.distance < 1) direction = Offset(math.Random().nextDouble() - 0.5, math.Random().nextDouble() - 0.5);
    final normalized = direction / direction.distance;
    _velocities[nodeId] = (_velocities[nodeId] ?? Offset.zero) + normalized * _impulseMagnitude;
  }

  /// Advances the simulation by [dt] seconds. Returns true if anything
  /// moved enough to warrant a repaint.
  bool step(double dt) {
    final size = _size;
    if (size == null || dt <= 0) return false;

    final forces = <String, Offset>{for (final n in model.nodes) n.id: Offset.zero};

    for (var i = 0; i < model.nodes.length; i++) {
      for (var j = i + 1; j < model.nodes.length; j++) {
        final a = model.nodes[i].id;
        final b = model.nodes[j].id;
        final pa = positions[a];
        final pb = positions[b];
        if (pa == null || pb == null) continue;
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

    for (final e in model.edges) {
      final pa = positions[e.sourceId];
      final pb = positions[e.targetId];
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

    var anyMoving = false;
    final dampingFactor = math.exp(-_damping * dt);

    for (final node in model.nodes) {
      if (node.id == selfId) continue; // keep self anchored at center
      final currentVelocity = _velocities[node.id] ?? Offset.zero;
      final accelerated = currentVelocity + forces[node.id]! * dt;
      final damped = accelerated * dampingFactor;
      _velocities[node.id] = damped;

      final currentPos = positions[node.id];
      if (currentPos == null) continue;
      final newPos = currentPos + damped * dt;
      final clamped = Offset(
        newPos.dx.clamp(30.0, math.max(30.0, size.width - 30.0)),
        newPos.dy.clamp(30.0, math.max(30.0, size.height - 30.0)),
      );
      positions[node.id] = clamped;

      if (damped.distance > _velocitySleepThreshold) anyMoving = true;
    }

    return anyMoving;
  }
}

// ── Rendering ────────────────────────────────────────────────────────────────

class _GraphCanvas extends StatelessWidget {
  const _GraphCanvas({
    required this.model,
    required this.positions,
    required this.size,
    required this.onTapOthers,
    required this.onTapNode,
  });

  final GraphModel model;
  final Map<String, Offset> positions;
  final Size size;
  final VoidCallback onTapOthers;
  final void Function(GraphNode node) onTapNode;

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
                  onTap: node.kind == GraphNodeKind.others
                      ? onTapOthers
                      : node.kind == GraphNodeKind.user
                          ? () => onTapNode(node)
                          : null,
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
            child: Icon(SolarIconsBold.usersGroupRounded, color: zt.accent, size: radius * 0.9),
          ),
        );
      case GraphNodeKind.others:
        return _LabeledNode(
          label: node.label,
          zt: zt,
          child: CircleAvatar(
            radius: radius,
            backgroundColor: zt.border,
            child: Icon(SolarIconsBold.menuDots, color: zt.textSecondary, size: radius * 0.9),
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
