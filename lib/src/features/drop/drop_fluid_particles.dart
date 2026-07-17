import 'dart:math';
import 'package:flutter/material.dart';

/// Direction of particle flow.
enum FluidParticleDirection { up, down }

/// A single fluid particle with independent physics state.
class _FluidParticle {
  _FluidParticle({
    required this.x,           // normalised 0→1 across canvas width
    required this.startPhase,  // 0→1, when in the loop this particle "spawns"
    required this.lifetime,    // fraction of the full animation cycle 0→1
    required this.speed,       // vertical travel as fraction of canvas height
    required this.sinePhase,   // unique horizontal oscillation phase
    required this.sineAmp,     // horizontal oscillation amplitude (px)
    required this.sineFreq,    // oscillation frequency multiplier
    required this.size,        // radius in logical px
    required this.brightness,  // 0.7–1.0 for gold shade variation
  });

  final double x;
  final double startPhase;
  final double lifetime;
  final double speed;
  final double sinePhase;
  final double sineAmp;
  final double sineFreq;
  final double size;
  final double brightness;

  /// Computes [x, y, opacity] for this particle at global animation time [t].
  /// Returns null if the particle is not yet alive.
  ({double px, double py, double opacity})? evaluate(
    double t,
    double canvasW,
    double canvasH,
    double originY, // the Y to emerge from / fall toward (in canvas coords)
    FluidParticleDirection dir,
  ) {
    // Determine where this particle is in its lifetime.
    // t loops 0→1 continuously (controller repeats).
    final adjustedT = (t - startPhase + 1.0) % 1.0;
    if (adjustedT > lifetime) return null; // not alive yet this cycle

    final localT = adjustedT / lifetime; // 0→1 within this particle's life

    // Vertical travel: from originY, moving up (sender) or down (receiver).
    final travel = speed * canvasH * localT;
    final py = dir == FluidParticleDirection.up
        ? originY - travel
        : originY + travel;

    // Skip if out of canvas bounds
    if (py < -4 || py > canvasH + 4) return null;

    // Horizontal sinusoidal drift — fluid, organic feel
    final drift = sineAmp * sin(localT * sineFreq * pi * 2 + sinePhase);
    final px = x * canvasW + drift;

    // Opacity: ease in (first 15%), hold (15–70%), ease out (70–100%)
    double opacity;
    if (localT < 0.15) {
      opacity = localT / 0.15;
    } else if (localT < 0.70) {
      opacity = 1.0;
    } else {
      opacity = (1.0 - localT) / 0.30;
    }

    return (px: px, py: py, opacity: opacity.clamp(0.0, 1.0));
  }
}

/// Physics-based fluid particle painter.
///
/// Renders a continuous upward or downward stream of hundreds of tiny gold
/// particles emanating from [originFraction] (0=top, 1=bottom) of the canvas.
/// Each particle has independent speed, oscillation, size and lifetime for
/// a fluid, organic, bioluminescent feel.
class DropFluidParticlePainter extends CustomPainter {
  DropFluidParticlePainter({
    required this.animation,
    required this.direction,
    required this.originFraction, // 0→1: fraction from top where particles spawn
    int count = 120,
    this.particleColor = const Color(0xFFFFD166),
    this.intensityMultiplier = 1.0,
  })  : _particles = _buildParticles(count),
        super(repaint: animation);

  final Animation<double> animation;
  final FluidParticleDirection direction;
  final double originFraction;
  final Color particleColor;
  final double intensityMultiplier; // 0→1, fades the whole stream
  final List<_FluidParticle> _particles;

  static List<_FluidParticle> _buildParticles(int count) {
    final rng = Random(314159); // deterministic — same particles every build
    return List.generate(count, (i) {
      return _FluidParticle(
        x: rng.nextDouble(),                          // spawn across full width
        startPhase: rng.nextDouble(),                  // staggered start
        lifetime: 0.25 + rng.nextDouble() * 0.35,    // 25–60% of cycle
        speed: 0.15 + rng.nextDouble() * 0.35,       // 15–50% of canvas height
        sinePhase: rng.nextDouble() * 2 * pi,
        sineAmp: 6 + rng.nextDouble() * 18,          // 6–24px horizontal wobble
        sineFreq: 1.0 + rng.nextDouble() * 2.0,      // 1–3 full oscillations
        size: 1.2 + rng.nextDouble() * 2.8,          // 1.2–4px radius
        brightness: 0.75 + rng.nextDouble() * 0.25,  // gold shade variation
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final originY = originFraction * size.height;

    for (final p in _particles) {
      final result = p.evaluate(t, size.width, size.height, originY, direction);
      if (result == null) continue;

      final effectiveOpacity = result.opacity * intensityMultiplier;
      if (effectiveOpacity <= 0.01) continue;

      // Gold with brightness variation
      final r = (particleColor.r * p.brightness).clamp(0.0, 1.0);
      final g = (particleColor.g * p.brightness).clamp(0.0, 1.0);
      final b = (particleColor.b * p.brightness).clamp(0.0, 1.0);
      final color = Color.from(
        alpha: effectiveOpacity,
        red: r,
        green: g,
        blue: b,
      );

      canvas.drawCircle(
        Offset(result.px, result.py),
        p.size,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(DropFluidParticlePainter old) =>
      old.animation.value != animation.value ||
      old.intensityMultiplier != intensityMultiplier;
}
