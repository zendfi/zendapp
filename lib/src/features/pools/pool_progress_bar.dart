import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';

/// A horizontal progress bar showing the filled ratio of a pool.
///
/// [progress] is clamped to 0.0–1.0. The filled portion uses
/// [ZendColors.accentBright] and the unfilled portion uses
/// [ZendColors.bgSecondary]. Both ends are rounded with [ZendRadii.pill].
class PoolProgressBar extends StatelessWidget {
  const PoolProgressBar({
    super.key,
    required this.progress,
    this.height = 8,
  });

  /// A value between 0.0 and 1.0 representing the fill ratio.
  final double progress;

  /// The height of the bar in logical pixels. Defaults to 8.
  final double height;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(ZendRadii.pill),
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          color: ZendColors.bgSecondary,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: constraints.maxWidth * clamped,
                height: height,
                decoration: BoxDecoration(
                  color: ZendColors.accentBright,
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
