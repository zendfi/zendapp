import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'zend_tokens.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Universal avatar widget.
///
/// Priority: [photoUrl] → [initials] circle → person icon.
///
/// - Network photos are loaded and cached via [CachedNetworkImage].
/// - The initials background color is deterministically derived from the
///   initials string so the same user always gets the same color.
/// - Fully dark-mode aware — uses [ZendTheme] for fallback colors.
/// - Pass [isOnline] to show a presence dot: true = green, false = grey,
///   null = no dot. The dot scales with [radius] and has a border that
///   matches the scaffold background so it reads cleanly on any surface.
class ZendAvatar extends StatelessWidget {
  const ZendAvatar({
    super.key,
    required this.radius,
    this.photoUrl,
    this.initials,
    this.backgroundColor,
    this.isOnline,
  });

  final double radius;
  final String? photoUrl;
  final String? initials;
  final Color? backgroundColor;
  /// Presence indicator: true = online (green dot), false = offline (grey dot),
  /// null = no dot shown.
  final bool? isOnline;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final size = radius * 2;

    // ── Build the avatar circle ────────────────────────────────────────────
    final Widget avatar;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      avatar = ClipOval(
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
    } else {
      avatar = _FallbackCircle(
        radius: radius,
        initials: initials,
        backgroundColor: backgroundColor,
        zt: zt,
      );
    }

    // ── No presence dot → return avatar directly ──────────────────────────
    if (isOnline == null) return avatar;

    // ── Presence dot overlay ──────────────────────────────────────────────
    final dotSize = (radius * 0.50).clamp(7.0, 14.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline! ? ZendColors.positive : const Color(0x66888888),
              border: Border.all(
                // Use scaffold background colour so the ring adapts to any surface
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
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
                fontFamily: 'CircularStd',
                fontSize: radius * 0.72,
                fontWeight: FontWeight.w600,
                color: _contrastColor(bgColor),
                height: 1.0,
              ),
            )
          : Icon(
              PhosphorIconsBold.userCircle,
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
