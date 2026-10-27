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
    this.seed,
  });

  /// Stable identity (user id or handle) the generated colour is derived from,
  /// so two people who share an initial still look different. Falls back to
  /// [initials] when omitted.
  final String? seed;

  /// Generated-avatar colour for [seed]; stable per person.
  static Color colorFor(String seed) => _FallbackCircle.colorFor(seed);

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
            seed: seed,
            initials: initials,
            backgroundColor: backgroundColor,
            zt: zt,
          ),
          errorWidget: (context, url, error) => _FallbackCircle(
            radius: radius,
            seed: seed,
            initials: initials,
            backgroundColor: backgroundColor,
            zt: zt,
          ),
        ),
      );
    } else {
      avatar = _FallbackCircle(
        radius: radius,
        seed: seed,
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
    this.seed,
  });

  final double radius;
  final String? initials;
  final Color? backgroundColor;
  final String? seed;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final hasInitials = initials != null && initials!.isNotEmpty;
    final bgColor =
        backgroundColor ??
        (hasInitials ? colorFor(seed ?? initials!) : zt.bgSecondary);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        // Generated avatars get a soft two-stop gradient so they read as a
        // person's mark rather than a flat placeholder disc.
        gradient: backgroundColor == null && hasInitials
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(bgColor, Colors.white, 0.18)!, bgColor],
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasInitials
          ? Text(
              initials![0].toUpperCase(),
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: radius * 0.72,
                fontWeight: FontWeight.w600,
                color: _contrastColor(bgColor),
                height: 1.0,
              ),
            )
          : Icon(
              PhosphorIconsRegular.userCircle,
              size: radius * 1.1,
              color: zt.textSecondary,
            ),
    );
  }

  /// Deterministic color from initials — same user always gets the same hue.
  /// Deterministic colour from a stable seed (FNV-1a hash), picked from
  /// hues spaced far apart so neighbours in a list never look alike.
  static Color colorFor(String seed) {
    const palette = [
      Color(0xFF1F8A55), // green
      Color(0xFF2563EB), // blue
      Color(0xFF7C3AED), // violet
      Color(0xFFDB2777), // pink
      Color(0xFF0891B2), // cyan
      Color(0xFFEA580C), // orange
      Color(0xFFCA8A04), // amber
      Color(0xFFDC2626), // red
      Color(0xFF4F46E5), // indigo
      Color(0xFF0D9488), // teal
    ];
    var h = 0x811c9dc5;
    for (final c in seed.toLowerCase().codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return palette[h % palette.length];
  }

  /// White or dark text depending on background luminance.
  static Color _contrastColor(Color bg) {
    return bg.computeLuminance() > 0.35 ? Colors.black87 : Colors.white;
  }
}
