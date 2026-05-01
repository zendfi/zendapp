import 'dart:async';

import 'package:flutter/material.dart';

import 'src/core/zend_state.dart';
import 'src/design/zend_theme.dart';
import 'src/features/loading/loading_overlay.dart';
import 'src/features/onboarding/splash_screen.dart';
import 'src/features/onboarding/welcome_screen.dart';
import 'src/features/onboarding/device_unlock_screen.dart';
import 'src/features/onboarding/pin_restore_screen.dart';
import 'src/features/onboarding/pin_setup_screen.dart';

import 'src/navigation/zend_routes.dart';

class ZendApp extends StatelessWidget {
  const ZendApp({super.key, required this.model});

  final ZendAppModel model;

  @override
  Widget build(BuildContext context) {
    return ZendScope(
      notifier: model,
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Zend! App',
            theme: buildZendTheme(),
            darkTheme: buildZendDarkTheme(),
            themeMode: model.isDarkMode ? ThemeMode.dark : ThemeMode.light,
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
          );
        },
      ),
    );
  }
}

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
    final hasToken = await widget.model.authService.isAuthenticated();
    if (!mounted) return;

    if (hasToken) {
      await widget.model.restoreUserIdentity();
      if (!mounted) return;
    }

    if (!hasToken) {
      pushReplacementZendSlide(context, const WelcomeScreen());
      return;
    }

    final hasLocalKeypair = await widget.model.walletService.hasLocalKeypair();
    final hasPinSetup = await widget.model.walletService.hasPinSetup();
    if (!mounted) return;

    if (hasLocalKeypair && hasPinSetup) {
      pushReplacementZendSlide(context, const DeviceUnlockScreen());
    } else if (hasLocalKeypair) {
      pushReplacementZendSlide(context, const PinSetupScreen());
    } else {
      pushReplacementZendSlide(context, const PinRestoreScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
