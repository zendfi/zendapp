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
import 'src/features/onboarding/pin_migration_screen.dart';
import 'src/models/qr_payment_intent.dart';
import 'src/services/pending_deep_link_service.dart';
import 'src/features/send/qr_payment_sheet.dart';
import 'src/services/qr_scanner_state.dart';
import 'src/services/push_notification_service.dart';

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
    // Default to system theme — follows device dark/light mode automatically.
    // The profile toggle overrides this to explicit dark or light.
    _themeMode = widget.model.hasExplicitTheme
        ? (widget.model.isDarkMode ? ThemeMode.dark : ThemeMode.light)
        : ThemeMode.system;
    widget.model.addListener(_onModelChanged);
    // Listen for app-lock state changes so we can consume a pending deep link
    // the moment the user unlocks the app.
    widget.model.appLockService.addListener(_onLockStateChanged);
    WidgetsBinding.instance.addObserver(this);

    _deepLinkSub = DeepLinkHandler.stream.listen(_handleDeepLink);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = DeepLinkHandler.initialLink;
      if (initial != null) _handleDeepLink(initial);

      final pending = PushNotificationService.consumePendingPaymentRequest();
      if (pending != null) {
        _handlePaymentRequestNotification(pending);
      }

      // Only consume the pending deep link here if we can actually act on it
      // right now (authenticated + unlocked). Otherwise leave it stored so
      // ZendShell.initState() or _onLockStateChanged() can pick it up later.
      if (PendingDeepLinkService.hasPending) {
        final ctx = _navigatorKey.currentContext;
        if (ctx != null && widget.model.isAuthenticated && !widget.model.appLockService.isLocked) {
          final pendingIntent = PendingDeepLinkService.consume();
          if (pendingIntent != null) {
            showQrPaymentSheet(ctx, intent: pendingIntent);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    widget.model.removeListener(_onModelChanged);
    widget.model.appLockService.removeListener(_onLockStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Fires whenever the app-lock state changes (locked ↔ unlocked).
  /// Consumes any pending deep link intent the moment the app is unlocked.
  void _onLockStateChanged() {
    if (widget.model.appLockService.isLocked) return; // just locked — nothing to do
    if (!widget.model.isAuthenticated) return;

    final pendingIntent = PendingDeepLinkService.consume();
    if (pendingIntent == null) return;

    // Small delay to let the lock overlay finish its fade-out animation
    // before presenting the payment sheet on top.
    // Use NavigatorState (not BuildContext) to avoid use_build_context_synchronously.
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      showQrPaymentSheetFromNavigator(navigator, intent: pendingIntent);
    });
  }

  void _handlePaymentRequestNotification(dynamic notification) {
    if (!widget.model.isAuthenticated) return;
    if (widget.model.appLockService.isLocked) return;

    final context = _navigatorKey.currentContext;
    if (context == null) return;

    final zendtag = (notification as dynamic).requesterZendtag as String?;
    final amount = (notification as dynamic).amountUsdc as double? ?? 0.0;
    final description = (notification as dynamic).description as String?;

    if (zendtag != null && amount > 0) {
      final intent = QrPaymentIntent(
        zendtag: zendtag,
        amountUsdc: amount,
        note: description,
      );
      showQrPaymentSheet(context, intent: intent);
    }
  }

  void _handleDeepLink(DeepLinkPayload payload) {
    final intent = QrPaymentIntent(
      zendtag: payload.zendtag,
      amountUsdc: payload.amountUsdc,
      note: payload.note,
      requestLinkId: payload.requestId,
    );

    if (!widget.model.isAuthenticated || widget.model.appLockService.isLocked) {
      PendingDeepLinkService.store(intent);
      return;
    }

    final context = _navigatorKey.currentContext;
    if (context == null) {
      PendingDeepLinkService.store(intent);
      return;
    }
    if (QrScannerState.isActive) return;
    showQrPaymentSheet(context, intent: intent);
  }

  void _onModelChanged() {
    final newMode = widget.model.hasExplicitTheme
        ? (widget.model.isDarkMode ? ThemeMode.dark : ThemeMode.light)
        : ThemeMode.system;
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

      // Consume any pending payment request notification that arrived while
      // the app was in the background. The notification tap sets the static
      // field synchronously; we read it here on every resume so it's never
      // missed regardless of whether initState already ran.
      final pending = PushNotificationService.consumePendingPaymentRequest();
      if (pending != null) {
        // Small delay to let the resuming animation settle before presenting
        // the sheet on top.
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          if (!model.isAuthenticated || model.appLockService.isLocked) {
            // App is locked — convert to a pending deep link so the
            // lock-state listener can present it after unlock.
            final intent = QrPaymentIntent(
              zendtag: pending.requesterZendtag,
              amountUsdc: pending.amountUsdc,
              note: pending.description,
            );
            PendingDeepLinkService.store(intent);
            return;
          }
          _handlePaymentRequestNotification(pending);
        });
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
            widget.model.setLocale(locale);
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
      // PIN is available — arm the lock service before showing unlock screen
      widget.model.appLockService.pinIsAvailable = true;

      // Check if 4→6 digit PIN migration is needed
      final needsMigration = await widget.model.walletService.needsMigration();
      if (!mounted) return;
      if (needsMigration) {
        pushReplacementZendSlide(context, const PinMigrationScreen());
      } else {
        pushReplacementZendSlide(context, const DeviceUnlockScreen());
      }
    } else if (hasLocalKeypair) {
      // Keypair generated but PIN not yet set — do NOT arm lock
      widget.model.appLockService.pinIsAvailable = false;
      pushReplacementZendSlide(context, const PinSetupScreen());
    } else {
      // No keypair at all — do NOT arm lock
      widget.model.appLockService.pinIsAvailable = false;
      pushReplacementZendSlide(context, const PinRestoreScreen());
    }
  }
  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
