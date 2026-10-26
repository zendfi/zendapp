import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'zend_tokens.dart';

/// The Zend Z as a system shape: a rounded tile whose corners are cut on the
/// Z's diagonal, carrying the brand icon. Used on Welcome, empty states and
/// loading. [animate] adds a slow sweep of light along the diagonal (the
/// "Z sweeps across" motion), disabled under Reduce Motion.
class ZendMark extends StatefulWidget {
  const ZendMark({super.key, this.size = 96, this.animate = false});

  final double size;
  final bool animate;

  @override
  State<ZendMark> createState() => _ZendMarkState();
}

class _ZendMarkState extends State<ZendMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && !ZendMotion.reduced(context)) {
      _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final s = widget.size;
    return Semantics(
      label: 'Zend',
      image: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => ClipPath(
          clipper: _ZCutClipper(),
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ZendColors.bgDeep,
                  Color.lerp(ZendColors.bgDeep, zt.moneyIn, 0.35)!,
                ],
              ),
            ),
            child: Stack(
              children: [
                if (_c.isAnimating)
                  Positioned.fill(
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      child: FractionalTranslation(
                        translation: Offset(_c.value * 3 - 1.5, 0),
                        child: Container(
                          width: s * 0.25,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.18),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                child!,
              ],
            ),
          ),
        ),
        child: Center(
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(zt.moneyIn, BlendMode.srcIn),
            child: Image.asset(
              'assets/icons/zend-icon-navbar.png',
              width: s * 0.46,
              height: s * 0.46,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded square with the top-right and bottom-left corners cut on a
/// diagonal, echoing the Z's stroke.
class _ZCutClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height, r = w * 0.22, cut = w * 0.2;
    return Path()
      ..moveTo(r, 0)
      ..lineTo(w - cut, 0)
      ..lineTo(w, cut)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(cut, h)
      ..lineTo(0, h - cut)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();
  }

  @override
  bool shouldReclip(_ZCutClipper old) => false;
}
