import 'package:flutter/material.dart';

/// Zend navigation route — fast slide-in transition.
///
/// Incoming screen slides in from the right. The child is wrapped in a
/// RepaintBoundary so the incoming screen gets its own compositing layer —
/// this prevents ZendAppModel state changes (SSE events etc.) from triggering
/// repaints of BOTH the incoming and outgoing screens during the animation.
PageRoute<T> zendRoute<T>({required Widget page}) {
  return PageRouteBuilder<T>(
    opaque:
        true, // incoming screen is fully opaque — no compositing of both layers
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slideIn = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

      return SlideTransition(
        position: slideIn,
        child: child, // RepaintBoundary not needed when opaque=true
      );
    },
  );
}

Future<T?> pushZendSlide<T>(
  BuildContext context,
  Widget page, {
  bool rootNavigator = false,
}) {
  // Desktop web: screens opened from the shell's list pane open in the
  // detail pane beside it instead of covering the list.
  if (!rootNavigator) {
    final detail = ZendDetailPaneScope.navigatorOf(context);
    if (detail != null) return detail.push(zendRoute<T>(page: page));
  }
  return Navigator.of(
    context,
    rootNavigator: rootNavigator,
  ).push(zendRoute<T>(page: page));
}

/// Marks a subtree whose [pushZendSlide] calls should land in a separate
/// "detail" navigator — the right-hand pane of the desktop web layout.
class ZendDetailPaneScope extends InheritedWidget {
  const ZendDetailPaneScope({
    super.key,
    required this.navigatorKey,
    required super.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  static NavigatorState? navigatorOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<ZendDetailPaneScope>()
      ?.navigatorKey
      .currentState;

  @override
  bool updateShouldNotify(ZendDetailPaneScope old) =>
      old.navigatorKey != navigatorKey;
}

Future<T?> pushReplacementZendSlide<T>(BuildContext context, Widget page) {
  return Navigator.of(context).pushReplacement(zendRoute<T>(page: page));
}

Future<T?> pushAndRemoveUntilZendSlide<T>(
  BuildContext context,
  Widget page, {
  bool rootNavigator = false,
}) {
  return Navigator.of(
    context,
    rootNavigator: rootNavigator,
  ).pushAndRemoveUntil(zendRoute<T>(page: page), (route) => false);
}
