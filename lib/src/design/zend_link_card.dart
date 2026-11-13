import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'zend_tint.dart';
import 'zend_tokens.dart';

/// The Link silhouette: a rounded ticket with a half-round notch in each
/// side and the top-right corner cut on the same diagonal as the Zend mark.
///
/// It's the one shape that means "a Link" anywhere it appears, so it has to
/// read without colour: in grayscale, at thumbnail size, in a share preview.
/// Change the proportions here, not per screen.
class ZendTicketBorder extends OutlinedBorder {
  const ZendTicketBorder({
    super.side,
    this.radius = 18,
    this.notchRadius = 8,
    this.notchAt = 0.5,
    this.cut = 18,
  });

  /// Corner radius of the three rounded corners.
  final double radius;

  /// Radius of the side notches.
  final double notchRadius;

  /// Vertical position of the notches as a fraction of the height.
  final double notchAt;

  /// Length of the diagonal cut's legs at the top-right corner.
  final double cut;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _path(Rect rect) {
    final l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    final h = rect.height;
    final rad = math.min(radius, h / 3);
    final n = math.min(notchRadius, h / 4);
    final c = math.min(cut, h / 3);
    final ny = t + h * notchAt;
    return Path()
      ..moveTo(l + rad, t)
      ..lineTo(r - c, t)
      // Cut corner: the Zend diagonal.
      ..lineTo(r, t + c)
      ..lineTo(r, ny - n)
      // Right notch, curving inward.
      ..arcToPoint(Offset(r, ny + n), radius: Radius.circular(n), clockwise: false)
      ..lineTo(r, b - rad)
      ..arcToPoint(Offset(r - rad, b), radius: Radius.circular(rad))
      ..lineTo(l + rad, b)
      ..arcToPoint(Offset(l, b - rad), radius: Radius.circular(rad))
      ..lineTo(l, ny + n)
      // Left notch.
      ..arcToPoint(Offset(l, ny - n), radius: Radius.circular(n), clockwise: false)
      ..lineTo(l, t + rad)
      ..arcToPoint(Offset(l + rad, t), radius: Radius.circular(rad))
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      _path(rect.deflate(side.width / 2)),
      side.toPaint()..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  ZendTicketBorder copyWith({BorderSide? side}) => ZendTicketBorder(
    side: side ?? this.side,
    radius: radius,
    notchRadius: notchRadius,
    notchAt: notchAt,
    cut: cut,
  );

  @override
  ShapeBorder scale(double t) => ZendTicketBorder(
    side: side.scale(t),
    radius: radius * t,
    notchRadius: notchRadius * t,
    notchAt: notchAt,
    cut: cut * t,
  );
}

/// A Link drawn in its silhouette, filled with the tint of whoever it
/// belongs to (the sender, or the ZApp that made it).
///
/// [waiting] marks a Link nobody has collected yet with the one signal dot,
/// tucked against the cut corner.
class ZendLinkCard extends StatelessWidget {
  const ZendLinkCard({
    super.key,
    required this.seed,
    required this.child,
    this.waiting = false,
    this.muted = false,
    this.padding = const EdgeInsets.fromLTRB(18, 14, 14, 14),
    this.onTap,
  });

  /// Stable identity the tint comes from: a user id, @tag, or app id.
  final String seed;
  final Widget child;

  /// Not collected yet: shows the signal dot.
  final bool waiting;

  /// Finished (collected, taken back, expired): drawn neutral, outline only.
  final bool muted;

  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final tint = ZendTint.of(seed, isDark: zt.isDark);
    final shape = ZendTicketBorder(
      side: BorderSide(color: muted ? zt.border : tint.edge),
    );
    final card = Material(
      color: muted ? zt.bgPrimary : tint.wash,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (!waiting) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: 4,
          right: 4,
          child: Semantics(
            label: 'Not collected yet',
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: zt.signal,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
