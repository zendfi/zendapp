import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'zend_tokens.dart';

/// Universal avatar widget.
///
/// Priority: [photoUrl] → [initials] circle → person icon.
///
/// - Network photos are loaded and cached via [CachedNetworkImage].
/// - The initials background color is deterministically derived from the
///   initials string so the same user always gets the same color.
/// - Fully dark-mode aware — uses [ZendTheme] for fallback colors.
class ZendAvatar extends StatelessWidget {
  const ZendAvatar({
    super.key,
    required this.radius,
    this.photoUrl,
    this.initials,
    this.backgroundColor,
  });

  final double radius;

  /// CDN URL of the user's profile photo. If null or empty, falls back to
  /// [initials] or the person icon.
  final String? photoUrl;

  /// Single uppercase letter (or short string) shown when no photo is set.
  final String? initials;

  /// Override the background color for the initials/icon fallback.
  /// If null, a color is derived from [initials].
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final size = radius * 2;

    // ── Network photo ──────────────────────────────────────────────────────
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => _FallbackCircle(
            radius: radius,
            initials: initials,
            backgroundColor: backgroundColor,
            zt: zt,
          ),
          errorWidget: (context, url, error) => _FallbackCircle(
            radius: radius,
            initials: initials,
            backgroundColor: backgroundColor,
            zt: zt,
          ),
        ),
      );
    }

    // ── Initials / icon fallback ───────────────────────────────────────────
    return _FallbackCircle(
      radius: radius,
      initials: initials,
      backgroundColor: backgroundColor,
      zt: zt,
    );
  }
}

class _FallbackCircle extends StatelessWidget {
  const _FallbackCircle({
    required this.radius,
    required this.zt,
    this.initials,
    this.backgroundColor,
  });

  final double radius;
  final String? initials;
  final Color? backgroundColor;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final hasInitials = initials != null && initials!.isNotEmpty;
    final bgColor = backgroundColor ??
        (hasInitials ? _colorFromInitials(initials!) : zt.bgSecondary);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: hasInitials
          ? Text(
              initials![0].toUpperCase(),
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: radius * 0.72,
                fontWeight: FontWeight.w600,
                color: _contrastColor(bgColor),
                height: 1.0,
              ),
            )
          : Icon(
              Icons.person,
              size: radius * 1.1,
              color: zt.textSecondary,
            ),
    );
  }

  /// Deterministic color from initials — same user always gets the same hue.
  static Color _colorFromInitials(String initials) {
    const palette = [
      Color(0xFF2D6A4F), // forest green
      Color(0xFF1565C0), // blue
      Color(0xFF6A1B9A), // purple
      Color(0xFFC62828), // red
      Color(0xFF00695C), // teal
      Color(0xFFE65100), // orange
      Color(0xFF37474F), // slate
      Color(0xFF558B2F), // olive
    ];
    final code = initials.codeUnitAt(0);
    return palette[code % palette.length];
  }

  /// White or dark text depending on background luminance.
  static Color _contrastColor(Color bg) {
    return bg.computeLuminance() > 0.35 ? Colors.black87 : Colors.white;
  }
}
