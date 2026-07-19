import 'dart:async';

import 'package:flutter/material.dart';


import 'src/core/zend_state.dart';
import 'src/design/zend_theme.dart';
import 'src/features/deeplink/deep_link_handler.dart';
import 'src/features/drop/drop_receiver_sheet.dart';
import 'src/features/loading/loading_overlay.dart';
import 'src/features/lock/app_lock_overlay.dart';
import 'src/features/onboarding/splash_screen.dart';
import 'src/features/onboarding/welcome_screen.dart';
import 'src/features/onboarding/device_unlock_screen.dart';
import 'src/features/onboarding/pin_restore_screen.dart';
import 'src/features/onboarding/pin_setup_screen.dart';
import 'src/features/onboarding/pin_migration_screen.dart';
import 'src/models/qr_payment_intent.dart';
import 'src/navigation/notification_navigator.dart';
import 'src/services/pending_deep_link_service.dart';
import 'src/services/pending_notification_service.dart';
import 'src/features/send/qr_payment_sheet.dart';
import 'src/features/send/dev_payment_modal_sheet.dart';
import 'src/features/pairing/pairing_approval_sheet.dart';
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
  StreamSubscription<Map<String, dynamic>>? _dropConfirmedSub;
  // Track when the app went to background so we know if SSE likely died.
  DateTime? _pausedAt;
  // Dedup guard: transfer IDs for which we've already shown the receiver sheet.
  // Prevents the reconciler's second dropConfirmed SSE (~45s later) from
  // showing a duplicate sheet for the same transfer.
  final Set<String> _shownDropTransferIds = {};

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

    // Fire receiver haptics + balance notification when a Drop lands
    _dropConfirmedSub = widget.model.dropConfirmedEvents.listen(_onDropConfirmed);

    // Register authentication hook to dispatch pending notification destinations
    // that were parked before auth completed (covers device OS-lock path).
    widget.model.onAuthenticated = () {
      final pendingDest = PendingNotificationService.consume();
      if (pendingDest == null) return;
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        final ctx = _navigatorKey.currentContext;
        if (ctx == null || widget.model.appLockService.isLocked) {
          PendingNotificationService.store(pendingDest); // still locked at app level
          return;
        }
        NotificationNavigator.dispatch(ctx, pendingDest, widget.model); // ignore: use_build_context_synchronously
      });
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = DeepLinkHandler.initialLink;
      if (initial != null) _handleDeepLink(initial);

      final pending = PushNotificationService.consumePendingPaymentRequest();
      if (pending != null) {
        _handlePaymentRequestNotification(pending);
      }

      // Consume any notification tap that arrived at cold-launch
      // (getInitialMessage was already stored by PushNotificationService.initialize()).
      final pendingDest = PendingNotificationService.consume();
      if (pendingDest != null) {
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          final ctx = _navigatorKey.currentContext;
          if (ctx == null) return;
          if (!widget.model.isAuthenticated || widget.model.appLockService.isLocked) {
            PendingNotificationService.store(pendingDest); // park until unlocked
            return;
          }
          NotificationNavigator.dispatch(ctx, pendingDest, widget.model); // ignore: use_build_context_synchronously
        });
      }

      if (PendingDeepLinkService.hasPending) {
        final ctx = _navigatorKey.currentContext;
        if (ctx != null && widget.model.isAuthenticated && !widget.model.appLockService.isLocked) {
          final pendingIntent = PendingDeepLinkService.consume();
          if (pendingIntent != null) {
            showQrPaymentSheet(ctx, intent: pendingIntent); // ignore: use_build_context_synchronously
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _dropConfirmedSub?.cancel();
    widget.model.removeListener(_onModelChanged);
    widget.model.appLockService.removeListener(_onLockStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Fires whenever a Drop transfer is confirmed — handles the receiver side.
  ///
  /// Sender: already handled by the Drop sheet's _executeTransfer success path.
  /// Receiver: fires haptics + shows a "catch" bottom sheet so they feel the money land.
  void _onDropConfirmed(Map<String, dynamic> data) {
    final role = data['role'] as String?;
    if (role != 'receiver') return;

    // Dedup by transfer_id — the reconciler fires a second dropConfirmed SSE
    // ~45s after the initial one when it confirms the tx on-chain. Without
    // this guard, the receiver sheet appears twice.
    final transferId = data['transfer_id'] as String?;
    if (transferId != null) {
      if (_shownDropTransferIds.contains(transferId)) {
        return;
      }
      _shownDropTransferIds.add(transferId);
      // Keep the set from growing unbounded — cap at 20 entries.
      if (_shownDropTransferIds.length > 20) {
        _shownDropTransferIds.remove(_shownDropTransferIds.first);
      }
    }

    final amountStr = data['amount_usdc'] as String? ?? '0';
    final amount = double.tryParse(amountStr) ?? 0.0;
    final senderTag = data['counterparty_zendtag'] as String? ?? '';
    final note = data['note'] as String?;

    // Defer to next frame in case this fires during a navigation transition.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _navigatorKey.currentContext;
      if (ctx == null) return;

      // Look up the sender's avatar from local contacts/transfer history.
      // Falls back to initials if not found — always works.
      String? senderAvatarUrl;
      try {
        final model = widget.model;
        final matches = model.recentContacts.where(
          (c) => c.tag.toLowerCase() == senderTag.toLowerCase(),
        );
        senderAvatarUrl = matches.isEmpty ? null : matches.first.avatarUrl;
      } catch (_) {}

      showDropReceiverSheet(
        context: ctx,
        amount: amount,
        senderZendtag: senderTag,
        senderAvatarUrl: senderAvatarUrl,
        note: note,
      );
    });
  }

  /// Fires whenever the app-lock state changes (locked ↔ unlocked).
  /// Consumes any pending deep link or notification destination the moment
  /// the app is unlocked.
  void _onLockStateChanged() {
    if (widget.model.appLockService.isLocked) return;
    if (!widget.model.isAuthenticated) return;

    // Deep-link intent (payment request URL)
    final pendingIntent = PendingDeepLinkService.consume();
    if (pendingIntent != null) {
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        final navigator = _navigatorKey.currentState;
        if (navigator == null) return;
        showQrPaymentSheetFromNavigator(navigator, intent: pendingIntent);
      });
    }

    // Notification tap destination (any type)
    final pendingDest = PendingNotificationService.consume();
    if (pendingDest != null) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        final ctx = _navigatorKey.currentContext;
        if (ctx == null) return;
        NotificationNavigator.dispatch(ctx, pendingDest, widget.model); // ignore: use_build_context_synchronously
      });
    }
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
    // "Pay with Zend" CLI device pairing — zdfi.me/cli-auth/{code}. Routed
    // directly to the approval sheet; no QrPaymentIntent involved, and no
    // pending-deep-link storage since pairing approval requires the user
    // to already be authenticated and unlocked (it's a sensitive
    // account-access grant, not a payment).
    if (payload.isCliPairing) {
      if (!widget.model.isAuthenticated || widget.model.appLockService.isLocked) {
        return;
      }
      final context = _navigatorKey.currentContext;
      if (context == null) return;
      showPairingApprovalSheet(context, pairingCode: payload.cliPairingCode!);
      return;
    }

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
    _dispatchPaymentIntent(context, intent);
  }

  /// Dispatches a resolved [QrPaymentIntent] to either the existing
  /// [QrPaymentSheet] (peer-to-peer, `source='app'`) or the new
  /// `DevPaymentModalSheet` (Developer-created, `source='api'` — "Pay with
  /// Zend"). Both share the identical `zdfi.me/@{zendtag}/{request_id}`
  /// URL shape, so the dispatch decision can only be made after fetching
  /// the request's `source` field (Requirement 4.1) — open/fixed-amount
  /// intents with no `requestLinkId` are always peer-to-peer and go
  /// straight to [QrPaymentSheet] without any fetch.
  Future<void> _dispatchPaymentIntent(BuildContext context, QrPaymentIntent intent) async {
    if (intent.requestLinkId == null) {
      showQrPaymentSheet(context, intent: intent);
      return;
    }

    String source = 'app';
    try {
      final details = await widget.model.walletService.apiClient
          .getPublicUserRequestData(intent.zendtag, intent.requestLinkId!);
      source = details.source;
    } catch (_) {
      // Fetch failure (e.g. 404 for an expired/paid request) — fall back to
      // QrPaymentSheet, which already has its own fetch-and-error-state
      // handling for exactly this case.
      source = 'app';
    }

    if (!mounted) return;
    // Use NavigatorState (not BuildContext) captured after the async gap,
    // matching the existing showQrPaymentSheetFromNavigator pattern in this
    // file — avoids holding a BuildContext across the await above.
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    if (source == 'api') {
      showDevPaymentModalSheet(
        navigator.context,
        zendtag: intent.zendtag,
        requestLinkId: intent.requestLinkId!,
      );
    } else {
      showQrPaymentSheetFromNavigator(navigator, intent: intent);
    }
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
        unawaited(model.dropDiscoverabilityService.onAppForeground());

        final bgDuration = _pausedAt != null
            ? DateTime.now().difference(_pausedAt!)
            : Duration.zero; // null means we were never actually paused

        // Lock if backgrounded for 2+ minutes — brief switches don't lock.
        if (bgDuration.inSeconds >= 120 && model.appLockService.pinIsAvailable) {
          model.appLockService.lock();
        }

        if (bgDuration.inMinutes >= 2) {
          model.forceRestartRealTimeUpdates();
        } else {
          model.startRealTimeUpdates();
        }
        _pausedAt = null;
        unawaited(model.fetchBalance());
        unawaited(model.fetchHistory());
        model.appLockService.startTimer();
      }

      // Handle pending drop confirmed push notification (arrived while backgrounded)
      final pendingDrop = PushNotificationService.consumePendingDropConfirmed();
      if (pendingDrop != null) {
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (!mounted || !model.isAuthenticated) return;
          // Apply the same transfer_id dedup as _onDropConfirmed — the reconciler
          // fires both a second SSE and a second FCM push ~45s after the initial
          // drop; without this guard the push path bypasses the SSE dedup and
          // shows the sheet twice.
          final tId = pendingDrop['transfer_id'] as String?;
          if (tId != null && _shownDropTransferIds.contains(tId)) return;
          model.handleDropConfirmedFromPush(pendingDrop);
        });
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

      // Consume any other notification destination that arrived while backgrounded.
      final pendingDest = PendingNotificationService.consume();
      if (pendingDest != null) {
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          if (!model.isAuthenticated || model.appLockService.isLocked) {
            PendingNotificationService.store(pendingDest);
            return;
          }
          final ctx = _navigatorKey.currentContext;
          if (ctx != null) {
            NotificationNavigator.dispatch(ctx, pendingDest, model); // ignore: use_build_context_synchronously
          }
        });
      }
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      _pausedAt = DateTime.now();
      model.dropDiscoverabilityService.onAppBackground();
      if (state == AppLifecycleState.detached) {
        model.stopRealTimeUpdates();
      }
      if (model.isAuthenticated) {
        // Don't lock immediately on every background transition — brief switches
        // (notification shade, permission dialogs) would lock constantly.
        // Lock is applied on RESUME if we were gone long enough (see above).
        // Only lock immediately on detached (process about to die).
        if (state == AppLifecycleState.detached) {
          model.appLockService.lock();
        }
        // For paused: stopTimer so the inactivity countdown stops while backgrounded.
        // Lock will be applied on resume if bgDuration >= threshold.
        model.appLockService.stopTimer();
      }
    } else if (state == AppLifecycleState.inactive) {
      // The notification shade was pulled down, another app overlaid,
      // or the app switcher was opened — the app is still visible (not fully
      // backgrounded). Record the time so that if the user quickly returns
      // we know the actual elapsed time and don't default to a large value.
      // Do NOT stop the inactivity timer or lock here — these brief overlays
      // should be transparent to the lock mechanism.
      _pausedAt ??= DateTime.now();
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
