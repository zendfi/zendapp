import 'dart:math';
import 'package:flutter/material.dart';

/// Direction of particle stream.
enum FluidParticleDirection { up, down }

/// A single particle in the focused beam stream.
class _StreamParticle {
  _StreamParticle({
    required this.startPhase,  // 0→1: when in the loop this particle spawns
    required this.lifetime,    // fraction of the animation cycle it lives
    required this.angle,       // radians from the beam axis — small for focused stream
    required this.speed,       // travel distance as fraction of canvas height
    required this.size,        // base radius in logical px (grows with distance)
  });

  final double startPhase;
  final double lifetime;
  final double angle;
  final double speed;
  final double size;

  /// Computes position and opacity at global time [t].
  /// [focalX], [focalY]: beam origin in canvas coordinates.
  /// Returns null if not alive this cycle.
  ({double px, double py, double opacity, double radius})? evaluate(
    double t,
    double canvasW,
    double canvasH,
    double focalX,
    double focalY,
    FluidParticleDirection dir,
  ) {
    final adjustedT = (t - startPhase + 1.0) % 1.0;
    if (adjustedT > lifetime) return null;
    final localT = adjustedT / lifetime; // 0→1 within particle life

    // Distance traveled along the beam axis.
    final distance = speed * canvasH * localT;

    // X diverges from focal point with the beam angle.
    // sin(angle) gives the transverse displacement per unit distance.
    final dx = sin(angle) * distance;
    final dy = dir == FluidParticleDirection.up ? -distance : distance;

    final px = focalX + dx;
    final py = focalY + dy;

    if (px < -8 || px > canvasW + 8 || py < -8 || py > canvasH + 8) {
      return null;
    }

    // Opacity: fast fade-in, hold, soft fade-out.
    double opacity;
    if (localT < 0.08) {
      opacity = localT / 0.08;
    } else if (localT < 0.75) {
      opacity = 1.0;
    } else {
      opacity = (1.0 - localT) / 0.25;
    }

    // Radius grows with travel distance — particles appear larger as they
    // move away from the focal point (depth-of-field feel).
    final radius = size * (0.4 + localT * 0.8);

    return (
      px: px,
      py: py,
      opacity: opacity.clamp(0.0, 1.0),
      radius: radius,
    );
  }
}

/// Renders a focused comet-trail / particle beam streaming from a focal point.
///
/// The beam is narrow at the focal origin and fans out gently as particles
/// travel — matching the Apple Cash / AirDrop visual language in the reference
/// image. Particles are white/silver, densest near the focal point.
///
/// [direction] controls whether the stream flows up (sender) or down (receiver).
/// [focalXFraction]: 0→1 horizontal position of the beam origin (0.5 = centre).
/// [focalYFraction]: 0→1 vertical position of the beam origin in the canvas.
class DropFluidParticlePainter extends CustomPainter {
  DropFluidParticlePainter({
    required this.animation,
    required this.direction,
    required this.focalXFraction,
    required this.focalYFraction,
    int count = 200,
    this.particleColor = Colors.white,
    this.intensityMultiplier = 1.0,
    // Half-angle of the beam in radians — smaller = tighter stream.
    // 0.18 rad ≈ 10° gives the focused comet-trail look in the reference.
    double beamHalfAngle = 0.18,
    // Maximum spread near the beam edges (Gaussian taper).
    this.gaussianFalloff = 0.6,
  })  : _particles = _buildParticles(count, beamHalfAngle),
        super(repaint: animation);

  final Animation<double> animation;
  final FluidParticleDirection direction;
  final double focalXFraction;
  final double focalYFraction;
  final Color particleColor;
  final double intensityMultiplier;
  final double gaussianFalloff;
  final List<_StreamParticle> _particles;

  static List<_StreamParticle> _buildParticles(int count, double halfAngle) {
    final rng = Random(271828); // deterministic seed
    return List.generate(count, (i) {
      // Gaussian angle distribution — most particles near beam axis (angle ≈ 0).
      // Use Box-Muller to get a Gaussian sample.
      final u1 = rng.nextDouble();
      final u2 = rng.nextDouble();
      final gaussian = sqrt(-2 * log(max(u1, 1e-10))) * cos(2 * pi * u2);
      // Scale to half-angle range, with ~68% within ±halfAngle.
      final angle = (gaussian * halfAngle / 2.0).clamp(-halfAngle * 2, halfAngle * 2);

      return _StreamParticle(
        startPhase: rng.nextDouble(),
        lifetime: 0.30 + rng.nextDouble() * 0.35,   // 30–65% of cycle
        angle: angle,
        speed: 0.20 + rng.nextDouble() * 0.30,      // 20–50% of canvas height
        size: 0.8 + rng.nextDouble() * 1.8,         // tiny → small
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (intensityMultiplier <= 0.01) return;
    final t = animation.value;
    final focalX = focalXFraction * size.width;
    final focalY = focalYFraction * size.height;

    for (final p in _particles) {
      final result = p.evaluate(t, size.width, size.height, focalX, focalY, direction);
      if (result == null) continue;

      // Gaussian lateral falloff — particles near the beam axis are brighter.
      // angle is in [-2*halfAngle, 2*halfAngle], normalize to [-1, 1].
      final angleFraction = (p.angle / (0.18 * 2)).abs().clamp(0.0, 1.0);
      final gaussianWeight = exp(-gaussianFalloff * angleFraction * angleFraction * 8);

      final effectiveOpacity =
          result.opacity * intensityMultiplier * gaussianWeight;
      if (effectiveOpacity <= 0.01) continue;

      // White-silver with slight size/opacity variation by distance.
      final r = particleColor.r;
      final g = particleColor.g;
      final b = particleColor.b;
      final paint = Paint()
        ..color = Color.from(
          alpha: effectiveOpacity.clamp(0.0, 0.95),
          red: r,
          green: g,
          blue: b,
        );

      canvas.drawCircle(Offset(result.px, result.py), result.radius, paint);
    }
  }

  @override
  bool shouldRepaint(DropFluidParticlePainter old) =>
      old.animation.value != animation.value ||
      old.intensityMultiplier != intensityMultiplier;
}
