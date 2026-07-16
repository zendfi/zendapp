import 'package:flutter/material.dart';
import 'zend_tokens.dart';
import 'package:solar_icons/solar_icons.dart';

class ZendScrollPage extends StatelessWidget {
  const ZendScrollPage({super.key, required this.child, this.controller});

  final Widget child;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: controller,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor = ZendColors.textOnDeep,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color foregroundColor;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? zt.accent,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ZendRadii.lg)),
        ),
        child: isLoading
            ? ZendLoader(size: 20, strokeWidth: 2, color: foregroundColor)
            : Text(
                label,
                style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

class OutlineActionButton extends StatelessWidget {
  const OutlineActionButton(
      {super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: zt.textPrimary,
          side: BorderSide(color: zt.border),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ZendRadii.pill)),
        ),
        child: Text(
          label,
          style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class ZendSheetHandle extends StatelessWidget {
  const ZendSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: SizedBox(
        width: 32,
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: zt.border,
            borderRadius:
                const BorderRadius.all(Radius.circular(ZendRadii.pill)),
          ),
        ),
      ),
    );
  }
}

/// Zend's house loading indicator — a smoothly rotating arc with a faint
/// full-circle track underneath, rather than Flutter's default
/// [CircularProgressIndicator] (whose head/tail lengths pulse as it spins,
/// giving it a slightly frantic "chasing itself" look). This is the single
/// spinner primitive used everywhere in the app — inline in buttons,
/// full-screen loading states, pull-to-refresh, etc — instead of scattering
/// raw [CircularProgressIndicator] calls with inconsistent sizing/color.
///
/// Same constructor API as before (`size`/`strokeWidth`/`color`) so no call
/// site needs to change — only the rendering underneath is new.
class ZendLoader extends StatefulWidget {
  const ZendLoader(
      {super.key,
      this.size = 22,
      this.strokeWidth = 2,
      this.color = ZendColors.accentPop});  // accentPop = #95D5B2 — works on both themes

  final double size;
  final double strokeWidth;
  final Color color;

  @override
  State<ZendLoader> createState() => _ZendLoaderState();
}

class _ZendLoaderState extends State<ZendLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ZendLoaderPainter(
              progress: _controller.value,
              color: widget.color,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

class _ZendLoaderPainter extends CustomPainter {
  _ZendLoaderPainter({required this.progress, required this.color, required this.strokeWidth});

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;

    // Faint full track — gives the arc a resting context instead of
    // floating on nothing, and reads as more "designed" than a bare arc.
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // A fixed-length arc that simply rotates a full turn — no head/tail
    // easing, which is what makes Material's default spinner feel jittery.
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    const sweep = 1.7 * 3.14159265358979; // ~270°, matches Material's arc length
    final startAngle = progress * 2 * 3.14159265358979 - (3.14159265358979 / 2);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ZendLoaderPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// A clean backspace icon for keypads — uses the rounded backspace shape
/// (left-pointing pentagon) that users universally recognize.
class ZendBackspaceIcon extends StatelessWidget {
  const ZendBackspaceIcon({
    super.key,
    this.color = ZendColors.textOnDeep,
    this.size = 22,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      SolarIconsBold.backspace,
      color: color,
      size: size,
    );
  }
}
