import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'src/core/zend_state.dart';
import 'src/services/api_client.dart';
import 'src/features/deeplink/deep_link_handler.dart';
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
  );

  await model.hydrateRecentContacts();

  await DeepLinkHandler.init();

  runApp(ZendApp(model: model));
}
