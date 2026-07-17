import 'dart:math';
import 'package:flutter/material.dart';

/// Direction of particle stream.
enum FluidParticleDirection { up, down }

/// A single particle in the focused beam stream.
///
/// Physics model:
/// - Each particle has an independent start phase so the stream is continuous.
/// - Angle from the beam axis follows a Gaussian distribution — dense centre,
///   sparse edges — matching the Apple Cash / AirDrop visual language.
/// - A secondary sine-wave lateral oscillation gives each particle an organic
///   shimmer as it travels (turbulence), not just a straight diverging path.
/// - Particles accelerate slightly as they travel away from the focal point
///   (ease-in speed curve) for a more energetic, fluid feel.
class _StreamParticle {
  _StreamParticle({
    required this.startPhase,
    required this.lifetime,
    required this.angle,
    required this.speed,
    required this.baseSize,
    required this.turbulenceAmp,   // lateral oscillation amplitude (px)
    required this.turbulenceFreq,  // oscillation cycles per lifetime
    required this.turbulencePhase, // unique phase offset so they don't sync
    required this.brightness,      // 0.6–1.0 luminosity variation
  });

  final double startPhase;
  final double lifetime;
  final double angle;
  final double speed;
  final double baseSize;
  final double turbulenceAmp;
  final double turbulenceFreq;
  final double turbulencePhase;
  final double brightness;

  ({double px, double py, double opacity, double radius, double brightness})? evaluate(
    double t,
    double canvasW,
    double canvasH,
    double focalX,
    double focalY,
    FluidParticleDirection dir,
  ) {
    final adjustedT = (t - startPhase + 1.0) % 1.0;
    if (adjustedT > lifetime) return null;
    final localT = adjustedT / lifetime;

    // Ease-in speed: particles accelerate as they leave the focal point.
    // This makes the stream look more energetic near the source.
    final easedT = localT * localT * (3 - 2 * localT); // smoothstep
    final distance = speed * canvasH * easedT;

    // Primary beam divergence via the gaussian angle.
    final primaryDx = sin(angle) * distance;

    // Turbulence: sinusoidal lateral shiver along the travel axis.
    // Creates the fluid "shimmer" that makes particles look alive.
    final turbulence = turbulenceAmp *
        sin(localT * turbulenceFreq * 2 * pi + turbulencePhase);

    // The turbulence is perpendicular to the beam direction — rotate it.
    // For a vertical beam: turbulence is purely horizontal.
    final totalDx = primaryDx + turbulence;
    final dy = dir == FluidParticleDirection.up ? -distance : distance;

    final px = focalX + totalDx;
    final py = focalY + dy;

    if (px < -12 || px > canvasW + 12 || py < -12 || py > canvasH + 12) {
      return null;
    }

    // Opacity envelope: instant rise (4%), long hold, soft fade-out (20%).
    double opacity;
    if (localT < 0.04) {
      opacity = localT / 0.04;
    } else if (localT < 0.80) {
      opacity = 1.0;
    } else {
      opacity = (1.0 - localT) / 0.20;
    }

    // Particle grows slightly with travel for depth-of-field feel.
    // Eased so growth is faster at first, then levels off.
    final radiusGrowth = 1.0 + localT * localT * 1.2;
    final radius = baseSize * radiusGrowth;

    return (
      px: px,
      py: py,
      opacity: opacity.clamp(0.0, 1.0),
      radius: radius,
      brightness: brightness,
    );
  }
}

/// Renders a focused, turbulent particle beam streaming from a focal point.
///
/// Physics improvements over v1:
/// - Wider beam (beamHalfAngle ≈ 0.30 rad instead of 0.18) for more breadth.
/// - Per-particle lateral turbulence (sine oscillation) for fluid shimmer.
/// - Ease-in speed curve so particles accelerate away from the source.
/// - Brightness variation per particle (0.6–1.0) for depth.
/// - Heavier Gaussian falloff at edges for a dense-core look.
/// - Optional comet-tail mode: draws an elongated oval in travel direction.
class DropFluidParticlePainter extends CustomPainter {
  DropFluidParticlePainter({
    required this.animation,
    required this.direction,
    required this.focalXFraction,
    required this.focalYFraction,
    int count = 300,
    this.particleColor = Colors.white,
    this.intensityMultiplier = 1.0,
    double beamHalfAngle = 0.30,
    this.gaussianFalloff = 0.5,
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
    final rng = Random(271828);
    return List.generate(count, (i) {
      // Box-Muller Gaussian for beam angle distribution.
      final u1 = max(rng.nextDouble(), 1e-10);
      final u2 = rng.nextDouble();
      final gaussian = sqrt(-2 * log(u1)) * cos(2 * pi * u2);
      final angle = (gaussian * halfAngle / 2.2).clamp(-halfAngle * 2.2, halfAngle * 2.2);

      // Turbulence parameters — vary per particle for organic feel.
      final turbAmp = 4.0 + rng.nextDouble() * 16.0;   // 4–20px amplitude
      final turbFreq = 1.0 + rng.nextDouble() * 2.5;    // 1–3.5 cycles
      final turbPhase = rng.nextDouble() * 2 * pi;

      return _StreamParticle(
        startPhase: rng.nextDouble(),
        lifetime: 0.28 + rng.nextDouble() * 0.40,      // 28–68% of cycle
        angle: angle,
        speed: 0.18 + rng.nextDouble() * 0.32,         // 18–50% of canvas height
        baseSize: 0.9 + rng.nextDouble() * 2.1,        // 0.9–3.0px
        turbulenceAmp: turbAmp,
        turbulenceFreq: turbFreq,
        turbulencePhase: turbPhase,
        brightness: 0.60 + rng.nextDouble() * 0.40,    // 60–100%
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

      // Gaussian weight — heavily down-weights particles far from beam axis
      // to give a dense centre with soft edges.
      final angleFraction = (p.angle / (0.30 * 2.2)).abs().clamp(0.0, 1.0);
      final gaussianWeight = exp(-gaussianFalloff * angleFraction * angleFraction * 6);

      final effectiveOpacity =
          result.opacity * intensityMultiplier * gaussianWeight * result.brightness;
      if (effectiveOpacity <= 0.01) continue;

      final r = particleColor.r;
      final g = particleColor.g;
      final b = particleColor.b;

      // Core particle
      final paint = Paint()
        ..color = Color.from(
          alpha: effectiveOpacity.clamp(0.0, 0.95),
          red: r,
          green: g,
          blue: b,
        );
      canvas.drawCircle(Offset(result.px, result.py), result.radius, paint);

      // Soft glow halo around each particle — makes the stream look luminous.
      // Only drawn for the brighter particles (brightness > 0.75) to avoid
      // over-saturating the background.
      if (result.brightness > 0.75 && effectiveOpacity > 0.3) {
        final glowPaint = Paint()
          ..color = Color.from(
            alpha: (effectiveOpacity * 0.15).clamp(0.0, 0.15),
            red: r,
            green: g,
            blue: b,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
        canvas.drawCircle(Offset(result.px, result.py), result.radius * 2.5, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(DropFluidParticlePainter old) =>
      old.animation.value != animation.value ||
      old.intensityMultiplier != intensityMultiplier;
}

/// Paints a glowing text effect: a blurred soft version layered under the crisp text.
/// Used on the receiver screen to make the amount numeral appear to radiate light.
class DropGlowTextPainter extends CustomPainter {
  DropGlowTextPainter({
    required this.text,
    required this.style,
    required this.glowOpacity,
    required this.glowRadius,
  });

  final String text;
  final TextStyle style;
  final double glowOpacity;
  final double glowRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (glowOpacity <= 0.01) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(
        foreground: Paint()
          ..color = Colors.white.withValues(alpha: glowOpacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius),
      )),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: size.width);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(DropGlowTextPainter old) =>
      old.text != text || old.glowOpacity != glowOpacity;
}
