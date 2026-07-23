import 'package:flutter/material.dart';

/// Zend navigation route — spring-physics slide transition.
///
/// Incoming screen: slides in from right with a spring-like overshoot.
/// Background screen: scales down slightly and dims, like iOS/Spring animations.
/// This gives the "breathing" feel — screens feel alive, not mechanical.
PageRoute<T> zendRoute<T>({required Widget page}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    // 280ms feels instant but still gives visual context — 420ms was too slow.
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Incoming: clean easeOut slide — no overshoot (spring overshoot
      // adds extra frames that feel laggy on mid-range devices).
      final slideIn = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ));

      // Background: subtle scale + dim — keep it light so compositing is fast.
      final bgScale = Tween<double>(begin: 1.0, end: 0.97)
          .animate(CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic));
      final bgFade = Tween<double>(begin: 1.0, end: 0.75)
          .animate(CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic));

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
