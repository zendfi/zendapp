import 'dart:async';

import 'package:flutter/material.dart';

import 'src/core/zend_state.dart';
import 'src/design/zend_theme.dart';
import 'src/features/loading/loading_overlay.dart';
import 'src/features/lock/app_lock_overlay.dart';
import 'src/features/onboarding/splash_screen.dart';
import 'src/features/onboarding/welcome_screen.dart';
import 'src/features/onboarding/device_unlock_screen.dart';
import 'src/features/onboarding/pin_restore_screen.dart';
import 'src/features/onboarding/pin_setup_screen.dart';

import 'src/navigation/zend_routes.dart';

class ZendApp extends StatefulWidget {
  const ZendApp({super.key, required this.model});
  final ZendAppModel model;

  @override
  State<ZendApp> createState() => _ZendAppState();
}

class _ZendAppState extends State<ZendApp> with WidgetsBindingObserver {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.model.isDarkMode ? ThemeMode.dark : ThemeMode.light;
    widget.model.addListener(_onModelChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onModelChanged() {
    final newMode = widget.model.isDarkMode ? ThemeMode.dark : ThemeMode.light;
    if (newMode != _themeMode) {
      setState(() => _themeMode = newMode);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final model = widget.model;

    if (state == AppLifecycleState.resumed) {
      if (model.isAuthenticated) {
        model.startRealTimeUpdates();
        // Immediate refresh on foreground so data is never stale
        unawaited(model.fetchBalance());
        unawaited(model.fetchHistory());
        // Resume the inactivity timer (only if not already locked)
        model.appLockService.startTimer();
      }
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      model.stopRealTimeUpdates();
      // Pause the timer while backgrounded — we lock on resume if too long
      // has passed (handled by startTimer checking elapsed time on next resume).
      // For simplicity we lock immediately on background so the app is always
      // protected when the user returns after any absence.
      if (model.isAuthenticated) {
        model.appLockService.lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ZendScope(
      notifier: widget.model,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Zend! App',
        theme: buildZendTheme(),
        darkTheme: buildZendDarkTheme(),
        themeMode: _themeMode,
        home: _SplashWithSessionRestore(model: widget.model),
        localeResolutionCallback: (locale, _) {
          if (locale != null) {
            scheduleMicrotask(() => widget.model.setLocale(locale));
          }
          return locale;
        },
        builder: (context, child) {
          // Layer order (bottom → top):
          //   1. App content
          //   2. LoadingOverlay (spinner)
          //   3. AppLockOverlay (PIN screen — only visible when locked)
          //
          // Wrap with a Listener so any pointer event resets the inactivity
          // timer. We use HitTestBehavior.translucent so the events still
          // reach the widgets below.
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) =>
                widget.model.appLockService.recordActivity(),
            child: AppLockOverlay(
              lockService: widget.model.appLockService,
              child: LoadingOverlay(child: child ?? const SizedBox()),
            ),
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
