import 'dart:async';

import 'package:flutter/material.dart';

import 'src/core/zend_state.dart';
import 'src/design/zend_theme.dart';
import 'src/features/deeplink/deep_link_handler.dart';
import 'src/features/loading/loading_overlay.dart';
import 'src/features/lock/app_lock_overlay.dart';
import 'src/features/onboarding/splash_screen.dart';
import 'src/features/onboarding/welcome_screen.dart';
import 'src/features/onboarding/device_unlock_screen.dart';
import 'src/features/onboarding/pin_restore_screen.dart';
import 'src/features/onboarding/pin_setup_screen.dart';
import 'src/features/send/send_flow_sheet.dart';

import 'src/navigation/zend_routes.dart';

class ZendApp extends StatefulWidget {
  const ZendApp({super.key, required this.model});
  final ZendAppModel model;

  @override
  State<ZendApp> createState() => _ZendAppState();
}

final _navigatorKey = GlobalKey<NavigatorState>();

class _ZendAppState extends State<ZendApp> with WidgetsBindingObserver {
  late ThemeMode _themeMode;
  StreamSubscription<DeepLinkPayload>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.model.isDarkMode ? ThemeMode.dark : ThemeMode.light;
    widget.model.addListener(_onModelChanged);
    WidgetsBinding.instance.addObserver(this);

    _deepLinkSub = DeepLinkHandler.stream.listen(_handleDeepLink);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = DeepLinkHandler.initialLink;
      if (initial != null) _handleDeepLink(initial);
    });
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    widget.model.removeListener(_onModelChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleDeepLink(DeepLinkPayload payload) {
    if (!widget.model.isAuthenticated) return;
    if (widget.model.appLockService.isLocked) return;

    final context = _navigatorKey.currentContext;
    if (context == null) return;

    final amount = payload.amountUsdc ?? 0.0;
    if (amount > 0) {
      showSendFlowSheet(
        context,
        amount: amount,
        prefilledRecipient: payload.zendtag,
        prefilledNote: payload.note,
      );
    } else {
      showSendFlowSheet(
        context,
        amount: 0,
        prefilledRecipient: payload.zendtag,
        prefilledNote: payload.note,
      );
    }
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
        unawaited(model.fetchBalance());
        unawaited(model.fetchHistory());
        model.appLockService.startTimer();
      }
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      model.stopRealTimeUpdates();
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
        navigatorKey: _navigatorKey,
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
