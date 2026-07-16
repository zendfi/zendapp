import 'package:flutter/material.dart';
import '../../design/zend_tokens.dart';

class DropScannerStage extends StatefulWidget {
  const DropScannerStage({super.key, required this.amount});
  final double amount;

  @override
  State<DropScannerStage> createState() => _DropScannerStageState();
}

class _DropScannerStageState extends State<DropScannerStage>
    with TickerProviderStateMixin {
  // Three staggered wave controllers — each offset by 1/3 cycle so rings
  // feel like continuous water ripples, not synchronized pulses.
  late final AnimationController _wave1;
  late final AnimationController _wave2;
  late final AnimationController _wave3;

  @override
  void initState() {
    super.initState();
    const duration = Duration(milliseconds: 2800);
    _wave1 = AnimationController(vsync: this, duration: duration)..repeat();
    _wave2 = AnimationController(vsync: this, duration: duration)
      ..forward(from: 0.33)
      ..addStatusListener((s) { if (s == AnimationStatus.completed) _wave2.repeat(); });
    _wave3 = AnimationController(vsync: this, duration: duration)
      ..forward(from: 0.66)
      ..addStatusListener((s) { if (s == AnimationStatus.completed) _wave3.repeat(); });
  }

  @override
  void dispose() {
    _wave1.dispose();
    _wave2.dispose();
    _wave3.dispose();
    super.dispose();
  }

  String get _amountFormatted {
    if (widget.amount == widget.amount.roundToDouble()) {
      return '\$${widget.amount.toStringAsFixed(0)}';
    }
    return '\$${widget.amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Column(
      children: [
        const Spacer(flex: 2),
        // Amount — large, centred
        Text(
          _amountFormatted,
          style: TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 56,
            fontStyle: FontStyle.italic,
            color: zt.textPrimary,
          ),
        ),
        const SizedBox(height: 52),
        // Fluid ripple canvas — fills available width, fixed aspect
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: AspectRatio(
            aspectRatio: 1,
            child: AnimatedBuilder(
              animation: Listenable.merge([_wave1, _wave2, _wave3]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _FluidRipplePainter(
                    wave1: _wave1.value,
                    wave2: _wave2.value,
                    wave3: _wave3.value,
                    accentColor: zt.accent,
                    accentBrightColor: zt.accentBright,
                    isDark: zt.isDark,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 36),
        Text(
          'Scanning for nearby Zend users\u2026',
          style: TextStyle(
            fontFamily: 'DMMono',
            fontSize: 13,
            color: zt.textSecondary,
          ),
        ),
        const Spacer(flex: 3),
      ],
    );
  }
}

/// Paints three concentric expanding rings (water ripple / sonar style) and
/// a small solid centre dot. Each ring uses an eased opacity curve so it
/// fades in as it expands and fades out before disappearing — giving a
/// continuous, fluid feel rather than discrete concentric flashes.
///
/// The three waves are staggered in phase so there's always a ring in motion.
class _FluidRipplePainter extends CustomPainter {
  _FluidRipplePainter({
    required this.wave1,
    required this.wave2,
    required this.wave3,
    required this.accentColor,
    required this.accentBrightColor,
    required this.isDark,
  });

  final double wave1;
  final double wave2;
  final double wave3;
  final Color accentColor;
  final Color accentBrightColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxRadius = size.shortestSide / 2;

    // Draw three expanding rings
    _drawRing(canvas, cx, cy, maxRadius, wave1);
    _drawRing(canvas, cx, cy, maxRadius, wave2);
    _drawRing(canvas, cx, cy, maxRadius, wave3);

    // Centre dot
    final centrePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 5, centrePaint);

    // Inner static ring
    final staticRingPaint = Paint()
      ..color = accentColor.withValues(alpha: isDark ? 0.15 : 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), maxRadius * 0.18, staticRingPaint);
  }

  void _drawRing(Canvas canvas, double cx, double cy, double maxRadius, double t) {
    // Use a smooth ease-in-out curve so the ring accelerates gently from
    // centre and decelerates as it reaches the edge — more water-like.
    final easedT = _easeInOutCubic(t);
    final radius = easedT * maxRadius;

    // Opacity: fade in quickly (0→0.3 of progress), hold, then fade out
    double opacity;
    if (t < 0.15) {
      opacity = t / 0.15;
    } else if (t < 0.65) {
      opacity = 1.0;
    } else {
      opacity = 1.0 - ((t - 0.65) / 0.35);
    }
    opacity = (opacity * (isDark ? 0.55 : 0.40)).clamp(0.0, 1.0);

    // Stroke width tapers from thick at centre to thin at edge
    final strokeWidth = (2.5 * (1.0 - easedT * 0.7)).clamp(0.5, 2.5);

    final ringPaint = Paint()
      ..color = accentColor.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(Offset(cx, cy), radius.clamp(1.0, maxRadius), ringPaint);
  }

  double _easeInOutCubic(double t) {
    if (t < 0.5) return 4 * t * t * t;
    final f = 2 * t - 2;
    return 0.5 * f * f * f + 1;
  }

  @override
  bool shouldRepaint(_FluidRipplePainter old) =>
      old.wave1 != wave1 || old.wave2 != wave2 || old.wave3 != wave3;
}
