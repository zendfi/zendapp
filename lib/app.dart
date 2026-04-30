import 'dart:async';

import 'package:flutter/material.dart';

import 'src/core/zend_state.dart';
import 'src/design/zend_theme.dart';
import 'src/features/loading/loading_overlay.dart';
import 'src/features/onboarding/splash_screen.dart';
import 'src/features/onboarding/welcome_screen.dart';
import 'src/features/shell/zend_shell.dart';
import 'src/navigation/zend_routes.dart';

class ZendApp extends StatelessWidget {
  const ZendApp({super.key, required this.model});

  final ZendAppModel model;

  @override
  Widget build(BuildContext context) {
    final theme = buildZendTheme();

    return ZendScope(
      notifier: model,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Zend! App',
        theme: theme,
        home: _SplashWithSessionRestore(model: model),
        localeResolutionCallback: (locale, _) {
          if (locale != null) {
            scheduleMicrotask(() => model.setLocale(locale));
          }
          return locale;
        },
        builder: (context, child) {
          return LoadingOverlay(
            child: child ?? const SizedBox(),
          );
        },
      ),
    );
  }
}

/// Wraps the SplashScreen and performs session restoration during the splash
/// timer. Navigates to ZendShell if authenticated, WelcomeScreen otherwise.
class _SplashWithSessionRestore extends StatefulWidget {
  const _SplashWithSessionRestore({required this.model});

  final ZendAppModel model;

  @override
  State<_SplashWithSessionRestore> createState() =>
      _SplashWithSessionRestoreState();
}

class _SplashWithSessionRestoreState
    extends State<_SplashWithSessionRestore> {
  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    bool authenticated = false;
    try {
      authenticated = await widget.model.authService.tryRestoreSession();
    } catch (_) {
      authenticated = false;
    }

    if (!mounted) return;

    if (authenticated) {
      pushReplacementZendSlide(context, const ZendShell());
    } else {
      pushReplacementZendSlide(context, const WelcomeScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Render the existing SplashScreen visuals while session restores
    return const SplashScreen();
  }
}
