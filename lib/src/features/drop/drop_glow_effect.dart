import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Which side of the Drop is being shown.
enum DropGlowDirection {
  /// Sender: text → glow → dissolve into drifting embers.
  dissolve,
  /// Receiver: drifting embers → glow builds → text materialises.
  reform,
}

/// A self-contained widget that renders Zend's Drop payment animation.
///
/// Sender path  (direction = dissolve, controller runs 0 → 1 once):
///   0.00–0.25  text solid, glow bloom builds outward
///   0.25–0.55  text fades, glow peaks then dims
///   0.45–1.00  sparse ember particles drift upward and fade
///
/// Receiver path (direction = reform, controller runs 0 → 1 once):
///   0.00–0.40  sparse ember particles drift, central glow begins building
///   0.40–0.75  glow intensifies
///   0.60–1.00  text materialises out of glow; glow settles to a soft breath
///
/// No pixel sampling, no off-screen render — pure widget compositing.
class DropGlowEffect extends StatefulWidget {
  const DropGlowEffect({
    super.key,
    required this.text,
    required this.style,
    required this.direction,
    required this.controller,
    this.width = double.infinity,
    this.height = 160,
    this.particleColor = Colors.white,
    this.glowColor = Colors.white,
  });

  final String text;
  final TextStyle style;
  final DropGlowDirection direction;
  final AnimationController controller;
  final double width;
  final double height;
  final Color particleColor;
  final Color glowColor;

  @override
  State<DropGlowEffect> createState() => _DropGlowEffectState();
}

class _DropGlowEffectState extends State<DropGlowEffect> {
  late final List<_Ember> _embers;

  @override
  void initState() {
    super.initState();
    _embers = _Ember.generate(60, Random(42));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final t = widget.controller.value;
          final dir = widget.direction;

          // ── Timeline fractions ──────────────────────────────────────────
          // Dissolve: glow 0–0.55, text fade 0.2–0.55, embers 0.45–1.0
          // Reform:   embers 0–0.65, glow 0.3–0.85, text 0.6–1.0
          final double glowT, textT, emberT;
          if (dir == DropGlowDirection.dissolve) {
            glowT = _remap(t, 0.00, 0.55); // 0→1 then sustained
            textT = 1.0 - _remap(t, 0.20, 0.55); // 1→0 (fade out)
            emberT = _remap(t, 0.45, 1.00); // 0→1 (embers appear & drift)
          } else {
            glowT = _remap(t, 0.30, 0.85);
            textT = _remap(t, 0.60, 1.00); // 0→1 (materialise)
            emberT = 1.0 - _remap(t, 0.45, 0.90); // embers fade as text arrives
          }

          // Glow pulse — peaks at 1.0 then settles to 0.35 (breathing)
          final glowIntensity = dir == DropGlowDirection.dissolve
              ? _dissolveGlowCurve(glowT)
              : _reformGlowCurve(glowT);

          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // ── Ember particles ─────────────────────────────────────────
              Positioned.fill(
                child: CustomPaint(
                  painter: _EmberPainter(
                    embers: _embers,
                    t: emberT,
                    color: widget.particleColor,
                    canvasHeight: widget.height,
                    direction: dir,
                  ),
                ),
              ),

              // ── Glow layer — blurred text underneath ────────────────────
              if (glowIntensity > 0.01)
                Opacity(
                  opacity: glowIntensity.clamp(0.0, 1.0),
                  child: _BlurredText(
                    text: widget.text,
                    style: widget.style,
                    blurRadius: _lerp(12.0, 28.0, (1.0 - glowIntensity).clamp(0.0, 1.0)),
                    color: widget.glowColor,
                  ),
                ),

              // ── Crisp text layer ────────────────────────────────────────
              Opacity(
                opacity: textT.clamp(0.0, 1.0),
                child: Text(
                  widget.text,
                  style: widget.style,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Sender glow curve: ramps up fast, peaks, then dips to a sustained low.
  double _dissolveGlowCurve(double t) {
    if (t < 0.5) return Curves.easeOut.transform(t * 2.0); // 0→1
    return _lerp(1.0, 0.0, Curves.easeIn.transform((t - 0.5) * 2.0)); // 1→0
  }

  /// Receiver glow curve: builds slowly, peaks, then settles to a soft breath.
  double _reformGlowCurve(double t) {
    if (t < 0.6) return Curves.easeInOut.transform(t / 0.6); // 0→1
    // Settle: gentle pulse — cosine oscillation from 1.0 down to ~0.35
    final settle = (t - 0.6) / 0.4;
    return _lerp(1.0, 0.35, Curves.easeOut.transform(settle));
  }
}

// ── Blurred text glow ─────────────────────────────────────────────────────────

class _BlurredText extends StatelessWidget {
  const _BlurredText({
    required this.text,
    required this.style,
    required this.blurRadius,
    required this.color,
  });

  final String text;
  final TextStyle style;
  final double blurRadius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: style.copyWith(
        foreground: Paint()
          ..color = color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius),
      ),
    );
  }
}

// ── Ember particle model ──────────────────────────────────────────────────────

class _Ember {
  final double startX; // 0→1, normalised horizontal position
  final double startY; // 0→1, normalised vertical position (centred around text)
  final double driftX; // horizontal drift amplitude
  final double driftSpeed; // vertical drift speed (upward)
  final double size; // point radius
  final double phase; // animation phase offset 0→1
  final double lifetime; // fraction of emberT this particle lives 0.3→1.0
  final double opacity; // max opacity

  const _Ember({
    required this.startX,
    required this.startY,
    required this.driftX,
    required this.driftSpeed,
    required this.size,
    required this.phase,
    required this.lifetime,
    required this.opacity,
  });

  static List<_Ember> generate(int count, Random rng) {
    return List.generate(count, (_) {
      return _Ember(
        // Cluster around centre with a wide spread
        startX: 0.5 + (rng.nextDouble() - 0.5) * 0.7,
        startY: 0.5 + (rng.nextDouble() - 0.5) * 0.4,
        driftX: (rng.nextDouble() - 0.5) * 0.12, // gentle sideways drift
        driftSpeed: 0.15 + rng.nextDouble() * 0.25, // upward drift rate
        size: 1.0 + rng.nextDouble() * 3.0,
        phase: rng.nextDouble(),
        lifetime: 0.35 + rng.nextDouble() * 0.65,
        opacity: 0.3 + rng.nextDouble() * 0.65,
      );
    });
  }
}

// ── Ember painter ─────────────────────────────────────────────────────────────

class _EmberPainter extends CustomPainter {
  const _EmberPainter({
    required this.embers,
    required this.t,
    required this.color,
    required this.canvasHeight,
    required this.direction,
  });

  final List<_Ember> embers;
  final double t; // 0→1, overall ember progress
  final Color color;
  final double canvasHeight;
  final DropGlowDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;

    for (final e in embers) {
      // Each particle has its own phase-offset timeline.
      final localT = ((t - e.phase + 1.0) % 1.0 / e.lifetime).clamp(0.0, 1.0);
      if (localT <= 0) continue;

      // Fade in quickly, hold, fade out near end.
      final fadeIn = (localT * 4.0).clamp(0.0, 1.0);
      final fadeOut = (1.0 - (localT - 0.7) * 3.3).clamp(0.0, 1.0);
      final alpha = (fadeIn * fadeOut * e.opacity).clamp(0.0, 1.0);
      if (alpha < 0.01) continue;

      // Position: start near text centre, drift upward + sideways wobble.
      final xWobble = sin(localT * pi * 2.5 + e.phase * pi) * e.driftX;
      final px = (e.startX + xWobble) * size.width;
      final drift = e.driftSpeed * localT;
      final rawY = direction == DropGlowDirection.dissolve
          ? e.startY - drift // sender: drift upward
          : e.startY + drift * 0.5 - drift; // receiver: converge downward
      final py = rawY.clamp(-0.5, 1.5) * size.height;

      final paint = ui.Paint()
        ..color = Color.from(alpha: alpha, red: color.r, green: color.g, blue: color.b)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, e.size * 0.8);

      canvas.drawCircle(Offset(px, py), e.size, paint);
    }
  }

  @override
  bool shouldRepaint(_EmberPainter old) => old.t != t;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Remaps [v] from [inMin..inMax] to [0..1], clamped.
double _remap(double v, double inMin, double inMax) =>
    ((v - inMin) / (inMax - inMin)).clamp(0.0, 1.0);

double _lerp(double a, double b, double t) => a + (b - a) * t;
