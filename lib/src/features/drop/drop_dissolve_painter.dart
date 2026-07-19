import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'drop_text_sampler.dart';

/// Per-tier rendering configuration.
class _TierConfig {
  const _TierConfig({
    required this.pointSize,
    required this.blurSigma,
    required this.baseOpacity,
    required this.glowCount, // if > 0, also render a glow halo pass
  });
  final double pointSize;
  final double blurSigma;
  final double baseOpacity;
  final int glowCount;
}

/// Tier configs indexed by [_DepthTier] ordinal (near, mid, far, halo).
const _kTierConfigs = [
  // near — sharp, bright, large
  _TierConfig(pointSize: 2.8, blurSigma: 0.5,  baseOpacity: 0.92, glowCount: 0),
  // mid — slightly blurred
  _TierConfig(pointSize: 2.0, blurSigma: 1.5,  baseOpacity: 0.75, glowCount: 0),
  // far — soft, small, dim
  _TierConfig(pointSize: 1.3, blurSigma: 3.0,  baseOpacity: 0.50, glowCount: 0),
  // halo — very blurred atmospheric bloom
  _TierConfig(pointSize: 8.0, blurSigma: 8.0,  baseOpacity: 0.04, glowCount: 0),
];

/// The direction of the dissolve animation.
enum DissolveDirection {
  /// Particles emerge from text letterforms and stream upward/toward target.
  dissolve,
  /// Particles descend from target and converge into text letterforms.
  reform,
}

/// Per-particle runtime state — computed once and cached per frame for the
/// portions that don't change (speed, phase, angle jitter).
class ParticleState {
  ParticleState({
    required this.particle,
    required this.speed,       // 0.15–0.55 canvas-height per full animation
    required this.phase,       // start phase 0→1 in the repeat cycle
    required this.lateralJitter, // extra x-wobble amplitude (px)
    required this.jitterFreq,
    required this.jitterPhase,
  });

  final SampledParticle particle;
  final double speed;
  final double phase;
  final double lateralJitter;
  final double jitterFreq;
  final double jitterPhase;
}

/// Builds a [ParticleState] list from sampled particles.
List<ParticleState> buildParticleStates(TextSampleResult result, Random rng) {
  final all = [...result.near, ...result.mid, ...result.far, ...result.halo];
  return all.map((p) => ParticleState(
    particle: p,
    speed: 0.15 + rng.nextDouble() * 0.40,
    phase: rng.nextDouble(),
    lateralJitter: 4.0 + rng.nextDouble() * 14.0,
    jitterFreq: 1.0 + rng.nextDouble() * 2.5,
    jitterPhase: rng.nextDouble() * 2 * pi,
  )).toList();
}

/// Renders the text-dissolve/reform particle effect using depth-bucketed
/// `Canvas.drawPoints` calls with `MaskFilter.blur` per tier.
///
/// Each tier gets its own `Paint` and its own `drawPoints` call — this is
/// intentional so per-tier blur and opacity are preserved and not averaged.
class DropDissolvePainter extends CustomPainter {
  DropDissolvePainter({
    required this.animation,
    required this.direction,
    required this.states,
    required this.result,
    /// Fraction of canvas height where the focal point is.
    required this.focalYFraction,
    required this.focalXFraction,
    /// Fraction of canvas height where the text is centred (default 0.54).
    this.textYFraction = 0.54,
    this.particleColor = Colors.white,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final DissolveDirection direction;
  final List<ParticleState> states;
  final TextSampleResult result;
  final double focalXFraction;
  final double focalYFraction;
  final double textYFraction;
  final Color particleColor;

  // Pre-allocated point buffers — keyed by tier index.
  // Populated each frame, no GC allocation.
  final _tierPoints = [<ui.Offset>[], <ui.Offset>[], <ui.Offset>[], <ui.Offset>[]];

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value; // 0→1 repeating
    final fX = focalXFraction * size.width;
    final fY = focalYFraction * size.height;

    // Clear tier point lists without allocating new lists.
    for (final list in _tierPoints) {
      list.clear();
    }

    for (final state in states) {
      final p = state.particle;
      final tierIdx = p.tier.index;

      // Compute local time within this particle's lifetime.
      final adj = (t - state.phase + 1.0) % 1.0;
      const lifetime = 0.55; // fraction of cycle each particle lives
      if (adj > lifetime) continue;
      final localT = adj / lifetime; // 0→1 within this particle's life

      // Ease-in acceleration away from focal/text position.
      final easedT = localT * localT * (3 - 2 * localT); // smoothstep

      // Text origin in canvas space.
      final textX = fX + (p.position.dx - 0.5) * result.textSize.width;
      final textY = (size.height * textYFraction) + (p.position.dy - 0.5) * result.textSize.height;

      // Target: a point within a cone toward the focal Y position.
      // Normal direction gives initial peel direction.
      final coneAngle = atan2(textY - fY, textX - fX);
      // Add glyph edge normal influence for first 30% of travel.
      final normalInfluence = (1 - localT * 3.3).clamp(0.0, 1.0);
      final normalAngle = atan2(p.edgeNormal.dy, p.edgeNormal.dx);
      final finalAngle = coneAngle * (1 - normalInfluence) + normalAngle * normalInfluence;

      final dist = state.speed * size.height * easedT;
      final lateral = state.lateralJitter *
          sin(localT * state.jitterFreq * 2 * pi + state.jitterPhase);

      double px, py;
      if (direction == DissolveDirection.dissolve) {
        // Sender: particles move FROM text position TOWARD focal point.
        px = textX - cos(finalAngle) * dist + lateral;
        py = textY - sin(finalAngle) * dist;
      } else {
        // Receiver: particles move FROM focal point TOWARD text position.
        // Reversed: start at focal, arrive at text.
        final revT = 1.0 - localT;
        final revEased = revT * revT * (3 - 2 * revT);
        final revDist = state.speed * size.height * revEased;
        px = textX - cos(coneAngle) * revDist + lateral * (1 - localT);
        py = textY - sin(coneAngle) * revDist;
      }

      if (px < -40 || px > size.width + 40 || py < -size.height * 3 || py > size.height + 40) {
        continue;
      }

      _tierPoints[tierIdx].add(ui.Offset(px, py));
    }

    // ── Render each tier with its own Paint + blur ──────────────────────────
    // Draw halo first (bottom layer), then far, mid, near (top).
    final renderOrder = [3, 2, 1, 0]; // halo → far → mid → near

    for (final tierIdx in renderOrder) {
      final points = _tierPoints[tierIdx];
      if (points.isEmpty) continue;

      final cfg = _kTierConfigs[tierIdx];

      final paint = ui.Paint()
        ..color = Color.from(
          alpha: cfg.baseOpacity,
          red: particleColor.r,
          green: particleColor.g,
          blue: particleColor.b,
        )
        ..strokeWidth = cfg.pointSize
        ..strokeCap = ui.StrokeCap.round
        ..style = ui.PaintingStyle.stroke;

      if (cfg.blurSigma > 0.1) {
        paint.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, cfg.blurSigma);
      }

      canvas.drawPoints(ui.PointMode.points, points, paint);
    }
  }

  @override
  bool shouldRepaint(DropDissolvePainter old) =>
      old.animation.value != animation.value ||
      old.textYFraction != textYFraction ||
      old.focalYFraction != focalYFraction;
}
