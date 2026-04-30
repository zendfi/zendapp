import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'src/core/zend_state.dart';
import 'src/services/api_client.dart';
import 'src/services/auth_service.dart';
import 'src/services/wallet_service.dart';
import 'src/services/zendtag_service.dart';
import 'src/services/transfer_service.dart';
import 'src/services/fx_service.dart';

const kApiBaseUrl = 'https://api-v2.zendfi.tech';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Create shared dependencies ──
  const secureStorage = FlutterSecureStorage();

  final apiClient = ApiClient(
    baseUrl: kApiBaseUrl,
    secureStorage: secureStorage,
  );

  // ── Create services ──
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

  // ── Create app model with injected services ──
  final model = ZendAppModel(
    authService: authService,
    walletService: walletService,
    zendtagService: zendtagService,
    transferService: transferService,
    fxService: fxService,
  );

  runApp(ZendApp(model: model));
}
