import 'package:flutter/material.dart';

/// Zend navigation route — spring-physics slide transition.
///
/// Incoming screen: slides in from right with a spring-like overshoot.
/// Background screen: scales down slightly and dims, like iOS/Spring animations.
/// This gives the "breathing" feel — screens feel alive, not mechanical.
PageRoute<T> zendRoute<T>({required Widget page}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Incoming: slight spring overshoot then settle
      final slideIn = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: const _SpringCurve(),
      ));

      // Background: scale down to 96% + dim as new screen comes in
      final bgScale = Tween<double>(begin: 1.0, end: 0.95)
          .animate(CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInOutCubic));
      final bgFade = Tween<double>(begin: 1.0, end: 0.65)
          .animate(CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInOutCubic));

      return AnimatedBuilder(
        animation: secondaryAnimation,
        builder: (ctx, outgoing) => Transform.scale(
          scale: bgScale.value,
          child: FadeTransition(opacity: bgFade, child: outgoing),
        ),
        child: SlideTransition(position: slideIn, child: child),
      );
    },
  );
}

/// Cubic approximation of a spring curve — overshoot ~4% then settle.
/// Avoids the complexity of real spring integration while feeling physical.
class _SpringCurve extends Curve {
  const _SpringCurve();

  @override
  double transformInternal(double t) {
    // Uses a cubic bezier that mimics spring dynamics: fast start,
    // slight overshoot around t=0.75, settle at 1.0
    // Approximated as two chained ease curves
    if (t < 0.75) {
      // Fast approach to ~1.04 (overshoot)
      final t2 = t / 0.75;
      return Curves.easeOut.transform(t2) * 1.04;
    } else {
      // Settle back from 1.04 to 1.0
      final t2 = (t - 0.75) / 0.25;
      return 1.04 - (0.04 * Curves.easeIn.transform(t2));
    }
  }
}

Future<T?> pushZendSlide<T>(
  BuildContext context,
  Widget page, {
  bool rootNavigator = false,
}) {
  return Navigator.of(context, rootNavigator: rootNavigator).push(
    zendRoute<T>(page: page),
  );
}

Future<T?> pushReplacementZendSlide<T>(
  BuildContext context,
  Widget page,
) {
  return Navigator.of(context).pushReplacement(
    zendRoute<T>(page: page),
  );
}

Future<T?> pushAndRemoveUntilZendSlide<T>(
  BuildContext context,
  Widget page, {
  bool rootNavigator = false,
}) {
  return Navigator.of(context, rootNavigator: rootNavigator).pushAndRemoveUntil(
    zendRoute<T>(page: page),
    (route) => false,
  );
}
