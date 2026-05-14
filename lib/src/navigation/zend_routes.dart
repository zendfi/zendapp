import 'package:flutter/material.dart';

/// Fast horizontal slide transition — 200ms, no platform overhead.
/// Replaces MaterialPageRoute's slow platform-default animation.
PageRoute<T> zendRoute<T>({required Widget page}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Incoming: slide in from right
      // Outgoing: slight slide left (secondary animation)
      final slideIn = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ));

      final slideOut = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.25, 0.0),
      ).animate(CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
      ));

      return SlideTransition(
        position: slideOut,
        child: SlideTransition(
          position: slideIn,
          child: child,
        ),
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
