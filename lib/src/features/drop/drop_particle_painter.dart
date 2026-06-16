import 'dart:math';
import 'package:flutter/material.dart';

/// A single particle for the Drop animation.
class _Particle {
  _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
  });

  final double angle;   // radians
  final double speed;   // px per unit (0→1) of animation
  final double size;    // radius in logical px
  final Color color;

  Offset position(double t) {
    // Decelerate with ease-out cubic
    final eased = 1 - pow(1 - t, 3).toDouble();
    return Offset(
      cos(angle) * speed * eased,
      sin(angle) * speed * eased,
    );
  }

  double opacity(double t) {
    // Fade in quickly, hold, then fade out in the last 40%
    if (t < 0.15) return t / 0.15;
    if (t < 0.6) return 1.0;
    return 1.0 - ((t - 0.6) / 0.4);
  }
}

/// Generates a burst of gold particles that radiate outward from [origin].
///
/// Used by the sender side when the countdown completes.
class DropParticleBurstPainter extends CustomPainter {
  DropParticleBurstPainter({
    required this.animation,
    required this.origin,
    int count = 18,
    double maxRadius = 110,
    this.particleColor = const Color(0xFFFFD166),
  }) : _particles = _buildParticles(count, maxRadius, particleColor),
       super(repaint: animation);

  final Animation<double> animation;
  final Offset origin;
  final Color particleColor;
  final List<_Particle> _particles;

  static List<_Particle> _buildParticles(int count, double maxRadius, Color color) {
    final rng = Random(42); // fixed seed for reproducibility
    return List.generate(count, (i) {
      final angle = (i / count) * 2 * pi + rng.nextDouble() * 0.4 - 0.2;
      final speed = maxRadius * (0.6 + rng.nextDouble() * 0.4);
      final size = 2.5 + rng.nextDouble() * 2.5;
      // Slight variation in gold shades
      final lightness = 0.85 + rng.nextDouble() * 0.1;
      final c = Color.fromARGB(
        255,
        ((color.r * 255.0) * lightness).round().clamp(0, 255),
        ((color.g * 255.0) * lightness).round().clamp(0, 255),
        ((color.b * 255.0) * lightness).round().clamp(0, 255),
      );
      return _Particle(angle: angle, speed: speed, size: size, color: c);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    for (final p in _particles) {
      final pos = origin + p.position(t);
      final opacity = p.opacity(t);
      if (opacity <= 0) continue;
      canvas.drawCircle(
        pos,
        p.size,
        Paint()..color = p.color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(DropParticleBurstPainter old) =>
      old.animation.value != animation.value;
}

/// A gentle shower of gold particles falling from the top of the screen.
///
/// Used by the receiver side when money arrives.
class DropParticleShowerPainter extends CustomPainter {
  DropParticleShowerPainter({
    required this.animation,
    required this.screenSize,
    int count = 24,
    this.particleColor = const Color(0xFFFFD166),
  }) : _particles = _buildParticles(count, screenSize, particleColor),
       super(repaint: animation);

  final Animation<double> animation;
  final Size screenSize;
  final Color particleColor;
  final List<_ShowerParticle> _particles;

  static List<_ShowerParticle> _buildParticles(int count, Size size, Color color) {
    final rng = Random(17);
    return List.generate(count, (i) {
      final x = rng.nextDouble() * size.width;
      final startT = rng.nextDouble() * 0.4; // staggered start
      final speed = size.height * (0.4 + rng.nextDouble() * 0.4);
      final pSize = 2.0 + rng.nextDouble() * 3.0;
      final drift = (rng.nextDouble() - 0.5) * 40;
      return _ShowerParticle(
        x: x, startT: startT, speed: speed, size: pSize,
        drift: drift, color: color,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    for (final p in _particles) {
      if (t < p.startT) continue;
      final localT = ((t - p.startT) / (1.0 - p.startT)).clamp(0.0, 1.0);
      final y = localT * p.speed;
      final x = p.x + p.drift * localT;
      final opacity = localT < 0.1
          ? localT / 0.1
          : (localT > 0.7 ? 1.0 - ((localT - 0.7) / 0.3) : 1.0);
      canvas.drawCircle(
        Offset(x, y),
        p.size,
        Paint()..color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(DropParticleShowerPainter old) =>
      old.animation.value != animation.value;
}

class _ShowerParticle {
  const _ShowerParticle({
    required this.x,
    required this.startT,
    required this.speed,
    required this.size,
    required this.drift,
    required this.color,
  });
  final double x;
  final double startT;
  final double speed;
  final double size;
  final double drift;
  final Color color;
}
