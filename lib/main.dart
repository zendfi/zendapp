import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'src/core/zend_state.dart';
import 'src/data/local/app_database.dart';
import 'src/models/notification_destination.dart';
import 'src/services/api_client.dart';
import 'src/features/deeplink/deep_link_handler.dart';
import 'src/services/pending_notification_service.dart';
import 'src/services/app_lock_service.dart';
import 'src/services/auth_service.dart';
import 'src/services/push_notification_service.dart';
import 'src/services/recent_contacts_store.dart';
import 'src/services/sound_service.dart';
import 'src/services/sse_service.dart';
import 'src/services/wallet_service.dart';
import 'src/services/zendtag_service.dart';
import 'src/services/transfer_service.dart';
import 'src/services/fx_service.dart';
import 'src/services/savings_service.dart';
import 'src/services/pocket_service.dart';
import 'src/services/email_intent_service.dart';

const kApiBaseUrl = 'https://api-v2.zendfi.tech';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch any Flutter framework errors and log them instead of crashing silently
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
    debugPrint('${details.stack}');
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    // Firebase init failure is non-fatal — app works without push notifications
    debugPrint('Firebase init failed: $e');
  }

  // Pre-warm audio — completely non-fatal
  SoundService.init().ignore();

  const secureStorage = FlutterSecureStorage();

  final apiClient = ApiClient(
    baseUrl: kApiBaseUrl,
    secureStorage: secureStorage,
  );

  final authService = AuthService(
    apiClient: apiClient,
    secureStorage: secureStorage,
  );

  final walletService = WalletService(
    apiClient: apiClient,
    secureStorage: secureStorage,
  );

  final zendtagService = ZendtagService(apiClient: apiClient);

  final transferService = TransferService(
    apiClient: apiClient,
    walletService: walletService,
  );

  final fxService = FxService(apiClient: apiClient);

  final recentContactsStore = RecentContactsStore(
    secureStorage: secureStorage,
  );

  final sseService = SseService(
    baseUrl: kApiBaseUrl,
    secureStorage: secureStorage,
  );

  final pushNotificationService = PushNotificationService(
    apiClient: apiClient,
  );

  final appLockService = AppLockService();

  final savingsService = SavingsService(apiClient: apiClient);

  final pocketService = PocketService(apiClient: apiClient);

  final emailIntentService = EmailIntentService(
    apiClient: apiClient,
    walletService: walletService,
  );

  // Initialise the local SQLite database (warm up the connection).
  final localDb = AppDatabase.instance;

  final model = ZendAppModel(
    authService: authService,
    walletService: walletService,
    zendtagService: zendtagService,
    transferService: transferService,
    fxService: fxService,
    recentContactsStore: recentContactsStore,
    sseService: sseService,
    pushNotificationService: pushNotificationService,
    appLockService: appLockService,
    savingsService: savingsService,
    pocketService: pocketService,
    emailIntentService: emailIntentService,
    localDb: localDb,
  );

  await model.hydrateRecentContacts();
  await model.loadPersistedPreferences();

  await DeepLinkHandler.init();

  // Register pool message badge callback early — before auth — so FCM messages
  // that arrive before authentication completes still mark the pool as unread.
  PushNotificationService.onPoolMessageReceived = (poolId) {
    model.poolsWithNewMessages.add(poolId);
    model.triggerRebuild();
  };

  // Check for a notification tap that launched the app from a killed state
  // (getInitialMessage) — must happen BEFORE runApp so the destination is
  // stored in PendingNotificationService before the widget tree builds.
  await _checkInitialNotificationTap();

  runApp(ZendApp(model: model));
}

/// Checks Firebase's `getInitialMessage` for a notification tap that cold-launched
/// the app, and parks the parsed destination in [PendingNotificationService].
/// Called before `runApp` so the destination is available immediately when the
/// widget tree builds — avoiding the race between `initialize()` (post-auth) and
/// `app.dart`'s `initState` postFrameCallback.
Future<void> _checkInitialNotificationTap() async {
  try {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    if (message != null) {
      final destination = NotificationDestination.fromData(message.data);
      PendingNotificationService.store(destination);
    }
  } catch (_) {
    // Non-fatal — notification tap simply won't deep-link if this fails.
  }
}
