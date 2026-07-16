import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';

enum PoolProgressBarStyle {
  /// Thin horizontal line — used in compact contexts like the pool list card.
  line,
  /// Large circular arc with a percentage label — used on the pool detail
  /// screen and contribute sheet where there's space to breathe.
  circle,
}

/// A progress indicator showing the filled ratio of a pool.
///
/// [progress] is clamped to 0.0–1.0.
/// [style] selects between a compact horizontal bar and a large circular arc.
class PoolProgressBar extends StatelessWidget {
  const PoolProgressBar({
    super.key,
    required this.progress,
    this.style = PoolProgressBarStyle.line,
    this.height = 8,
    this.circleSize = 110,
    this.strokeWidth = 9,
  });

  final double progress;
  final PoolProgressBarStyle style;

  /// Height of the horizontal bar (line style only). Defaults to 8.
  final double height;

  /// Diameter of the circle (circle style only). Defaults to 110.
  final double circleSize;

  /// Stroke width of the circular arc (circle style only). Defaults to 9.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return style == PoolProgressBarStyle.circle
        ? _CircleBar(progress: progress, size: circleSize, strokeWidth: strokeWidth)
        : _LineBar(progress: progress, height: height);
  }
}

// ── Line bar ─────────────────────────────────────────────────────────────────

class _LineBar extends StatelessWidget {
  const _LineBar({required this.progress, required this.height});
  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final zt = ZendTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(ZendRadii.pill),
      child: Container(
        height: height,
        color: zt.bgSecondary,
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: constraints.maxWidth * clamped,
              height: height,
              decoration: BoxDecoration(
                color: zt.accentBright,
                borderRadius: BorderRadius.circular(ZendRadii.pill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Circle bar ────────────────────────────────────────────────────────────────

class _CircleBar extends StatelessWidget {
  const _CircleBar({required this.progress, required this.size, required this.strokeWidth});
  final double progress;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final zt = ZendTheme.of(context);
    final pct = (clamped * 100).round();

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Track (background ring)
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: 1.0,
                strokeWidth: strokeWidth,
                valueColor: AlwaysStoppedAnimation<Color>(
                  zt.isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E2DA),
                ),
                strokeCap: StrokeCap.round,
              ),
            ),
            // Fill arc — green when complete, accent otherwise
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: clamped,
                strokeWidth: strokeWidth,
                valueColor: AlwaysStoppedAnimation<Color>(
                  clamped >= 1.0 ? zt.positive : zt.accent,
                ),
                strokeCap: StrokeCap.round,
              ),
            ),
            // Centre label: percentage + optional "done" tag
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: size * 0.21,
                    fontWeight: FontWeight.w700,
                    color: zt.textPrimary,
                    height: 1.0,
                  ),
                ),
                if (clamped >= 1.0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'done!',
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: size * 0.10,
                      color: zt.positive,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
