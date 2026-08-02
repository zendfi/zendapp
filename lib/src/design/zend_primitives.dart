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
                    fontFamily: 'Satoshi',
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
              fontFamily: 'Satoshi',
              fontSize: 15,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Slim progress bar spanning the entire onboarding journey (not to be
/// confused with the 2-dot create/confirm indicator inside PinSetupScreen,
/// which tracks a *sub*-step within a single screen). Placed at the very
/// top of each onboarding screen, above the scrollable content, so someone
/// on "What's your name?" can see at a glance how far through signup they
/// are instead of navigating blind.
class OnboardingProgressBar extends StatelessWidget {
  const OnboardingProgressBar({
    super.key,
    required this.step,
    required this.totalSteps,
    this.trackColor,
    this.fillColor,
  });

  /// 1-based index of the current step (e.g. 1 for the first screen).
  final int step;
  final int totalSteps;

  /// Optional overrides — onboarding screens with a permanently-dark
  /// background (SuccessScreen, PinSetupScreen) pass explicit light-on-dark
  /// colors here instead of relying on [ZendTheme], since those screens
  /// stay dark regardless of the app's light/dark theme setting.
  final Color? trackColor;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final progress = totalSteps <= 0 ? 0.0 : (step / totalSteps).clamp(0.0, 1.0);
    final track = trackColor ?? zt.border;
    final fill = fillColor ?? zt.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ZendRadii.pill),
        child: Container(
          height: 4,
          width: double.infinity,
          color: track,
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            builder: (context, value, _) => FractionallySizedBox(
              widthFactor: value,
              child: Container(height: 4, color: fill),
            ),
          ),
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

/// Shared error state for a failed data load, with an optional retry action.
///
/// Mirrors the icon/title/subtitle column shape already used ad hoc for
/// empty states across the app (e.g. `dm_list_screen.dart`'s `_EmptyState`),
/// but for the "the fetch actually failed" case rather than "there's
/// genuinely nothing here yet" — these look different (title/subtitle
/// wording, destructive-tinted icon, retry button) so users don't mistake
/// a network blip for their inbox being empty.
class ZendErrorState extends StatelessWidget {
  const ZendErrorState({
    super.key,
    this.title = "Couldn't load this",
    this.subtitle = 'Check your connection and try again',
    this.onRetry,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(SolarIconsBold.dangerTriangle, size: 40, color: zt.destructive.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w600, color: zt.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Satoshi', fontSize: 13, color: zt.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlineActionButton(label: 'Retry', onPressed: onRetry!),
            ],
          ],
        ),
      ),
    );
  }
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
