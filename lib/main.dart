import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'src/core/zend_state.dart';
import 'src/services/api_client.dart';
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

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

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
    zendtagService: zendtagService,
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

  final model = ZendAppModel(
    authService: authService,
    walletService: walletService,
    zendtagService: zendtagService,
    transferService: transferService,
    fxService: fxService,
    recentContactsStore: recentContactsStore,
    sseService: sseService,
    pushNotificationService: pushNotificationService,
  );

  await model.hydrateRecentContacts();

  runApp(ZendApp(model: model));
}
