import 'dart:math';
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
  // Primary wave pulse — drives the expanding grid ripple
  late final AnimationController _waveCtrl;
  // Secondary stagger — offsets each cell's pulse for a wave-like feel
  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _staggerCtrl.dispose();
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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        // Amount
        Text(
          _amountFormatted,
          style: TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 48,
            fontStyle: FontStyle.italic,
            color: zt.textPrimary,
          ),
        ),
        const SizedBox(height: 32),
        // Grid pulse animation
        SizedBox(
          width: 140,
          height: 140,
          child: AnimatedBuilder(
            animation: _waveCtrl,
            builder: (context, _) {
              return CustomPaint(
                painter: _GridPulsePainter(
                  progress: _waveCtrl.value,
                  accentColor: zt.accentBright,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Scanning for nearby Zend users\u2026',
          style: TextStyle(
            fontFamily: 'DMMono',
            fontSize: 13,
            color: zt.textSecondary,
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

/// Paints a 5×5 grid of dots that pulse outward from the center in a
/// concentric-ring wave pattern — like a sonar ping on a grid.
class _GridPulsePainter extends CustomPainter {
  _GridPulsePainter({required this.progress, required this.accentColor});

  final double progress;
  final Color accentColor;

  static const int _cols = 5;
  static const int _rows = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / _cols;
    final cellH = size.height / _rows;
    final centerX = (_cols - 1) / 2.0;
    final centerY = (_rows - 1) / 2.0;
    // Max distance from center to corner (Manhattan-ish, clamped for smooth spread)
    const maxDist = 2.83; // sqrt(2^2 + 2^2) = corner distance

    final paint = Paint()..style = PaintingStyle.fill;

    for (int row = 0; row < _rows; row++) {
      for (int col = 0; col < _cols; col++) {
        final dx = (col - centerX).abs();
        final dy = (row - centerY).abs();
        final dist = sqrt(dx * dx + dy * dy);

        // Phase: wave front passes through each cell based on its distance
        // from center. Cells closer to center lead; corners trail.
        final phase = (dist / maxDist).clamp(0.0, 1.0);

        // The wave front position in [0,1] — wraps with progress
        // Each cell pulses when the wave front reaches it.
        // Use a smooth sine-based brightness at that phase.
        const waveWidth = 0.35; // how wide the wave front is
        double t = (progress - phase * (1.0 - waveWidth)).remainder(1.0);
        if (t < 0) t += 1.0;

        // Smooth pulse curve: bright flash then fade
        double brightness;
        if (t < waveWidth) {
          final localT = t / waveWidth;
          // Attack fast, decay slowly
          brightness = localT < 0.2
              ? localT / 0.2
              : 1.0 - ((localT - 0.2) / 0.8) * 0.85;
        } else {
          brightness = 0.15; // dim baseline
        }

        final opacity = (brightness * 0.9).clamp(0.0, 1.0);
        final radius = (2.5 + brightness * 2.5).clamp(1.0, 5.0);

        final cx = (col + 0.5) * cellW;
        final cy = (row + 0.5) * cellH;

        paint.color = accentColor.withValues(alpha: opacity);
        canvas.drawCircle(Offset(cx, cy), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPulsePainter old) => old.progress != progress;
}
