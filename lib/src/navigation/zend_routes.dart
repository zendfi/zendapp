import 'package:flutter/material.dart';

/// Zend navigation route — fast slide-in transition.
///
/// Incoming screen slides in from the right. The child is wrapped in a
/// RepaintBoundary so the incoming screen gets its own compositing layer —
/// this prevents ZendAppModel state changes (SSE events etc.) from triggering
/// repaints of BOTH the incoming and outgoing screens during the animation.
PageRoute<T> zendRoute<T>({required Widget page}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slideIn = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ));

      return SlideTransition(
        position: slideIn,
        child: RepaintBoundary(child: child),
      );
    },
    // opaque = false means Flutter still composites both screens, which is
    // needed for the slide. But with RepaintBoundary on each, repaint
    // invalidations don't cross the boundary.
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
