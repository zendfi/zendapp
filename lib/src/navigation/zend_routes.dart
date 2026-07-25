import 'package:flutter/material.dart';

/// Zend navigation route — fast slide-in transition.
///
/// Incoming screen slides in from the right. No background scale/fade —
/// compositing a Transform.scale + FadeTransition on the outgoing screen
/// every frame is expensive, especially with BackdropFilter surfaces present.
/// A clean slide is faster on all devices and still reads as directional.
PageRoute<T> zendRoute<T>({required Widget page}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slideIn = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ));

      return SlideTransition(position: slideIn, child: child);
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
