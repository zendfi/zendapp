import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'zend_tint.dart';
import 'zend_tokens.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'zend_verified_badge.dart';

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
    this.verified = false,
  });

  /// Stable identity (user id or handle) the generated colour is derived from,
  /// so two people who share an initial still look different. Falls back to
  /// [initials] when omitted.
  final String? seed;

  /// Generated-avatar colour for [seed]; stable per person. See [ZendTint].
  static Color colorFor(String seed) => ZendTint.of(seed).solid;

  final double radius;
  final String? photoUrl;
  final String? initials;
  final Color? backgroundColor;

  /// Presence indicator: true = online (green dot), false = offline (grey dot),
  /// null = no dot shown.
  final bool? isOnline;

  /// Draws the human badge in the top-right corner. For large avatars only (profile); everywhere
  /// else the badge sits beside the name.
  final bool verified;

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

    // ── Human badge corner ────────────────────────────────────────────────
    final Widget withBadge = verified && radius >= 24
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              Positioned(
                right: -radius * 0.08,
                top: -radius * 0.08,
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  child: VerifiedBadge(size: (radius * 0.5).clamp(14.0, 26.0)),
                ),
              ),
            ],
          )
        : avatar;

    // ── No presence dot → return avatar directly ──────────────────────────
    if (isOnline == null) return withBadge;

    // ── Presence dot overlay ──────────────────────────────────────────────
    final dotSize = (radius * 0.50).clamp(7.0, 14.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        withBadge,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline! ? zt.positive : const Color(0x66888888),
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
    // A person's own colour, the same everywhere they appear. Only generated
    // avatars carry it; an explicit [backgroundColor] or a missing identity
    // stays neutral.
    final tint = backgroundColor == null && hasInitials
        ? ZendTint.of(seed ?? initials!, isDark: zt.isDark)
        : null;
    final bgColor = backgroundColor ?? tint?.solid ?? zt.bgSecondary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        gradient: tint?.gradient,
      ),
      alignment: Alignment.center,
      child: hasInitials
          ? Text(
              initials![0].toUpperCase(),
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: radius * 0.72,
                fontWeight: FontWeight.w600,
                color: tint?.onSolid ?? _contrastColor(bgColor),
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

  /// White or dark text depending on background luminance.
  static Color _contrastColor(Color bg) {
    return bg.computeLuminance() > 0.35 ? Colors.black87 : Colors.white;
  }
}
