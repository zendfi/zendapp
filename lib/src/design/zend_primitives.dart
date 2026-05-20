import 'package:flutter/material.dart';
import 'zend_tokens.dart';

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
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? zt.accent,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ZendRadii.lg)),
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

class ZendLoader extends StatelessWidget {
  const ZendLoader(
      {super.key,
      this.size = 22,
      this.strokeWidth = 2,
      this.color = ZendColors.accentPop});

  final double size;
  final double strokeWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// A left-pointing chevron backspace icon for keypads.
/// Renders a bold left-arrow-head (‹) shape — cleaner than the system
/// backspace icon and consistent across all keypads.
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
    return CustomPaint(
      size: Size(size, size),
      painter: _BackspacePainter(color: color),
    );
  }
}

class _BackspacePainter extends CustomPainter {
  const _BackspacePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final arm = size.width * 0.28;

    // Left-pointing chevron: two lines meeting at a point on the left
    final path = Path()
      ..moveTo(cx + arm, cy - arm)
      ..lineTo(cx - arm, cy)
      ..lineTo(cx + arm, cy + arm);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BackspacePainter old) => old.color != color;
}
