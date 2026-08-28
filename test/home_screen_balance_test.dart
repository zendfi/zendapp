// Regression test for the home-balance display bug.
//
// HomeScreen.initState() seeds _displayedBalance from the model inside an
// addPostFrameCallback (because the model isn't guaranteed ready at
// build-time for the very first frame). The callback used to mutate
// _displayedBalance directly without calling setState, so no new frame was
// ever scheduled — the hero balance number could sit at "$0.00" indefinitely
// after the real balance became available, indistinguishable from a
// genuinely empty wallet.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zendapp/src/core/zend_state.dart';
import 'package:zendapp/src/data/local/app_database.dart';
import 'package:zendapp/src/features/money/home_screen.dart';
import 'package:zendapp/src/services/api_client.dart';
import 'package:zendapp/src/services/app_lock_service.dart';
import 'package:zendapp/src/services/auth_service.dart';
import 'package:zendapp/src/services/fx_service.dart';
import 'package:zendapp/src/services/pocket_service.dart';
import 'package:zendapp/src/services/push_notification_service.dart';
import 'package:zendapp/src/services/recent_contacts_store.dart';
import 'package:zendapp/src/services/savings_service.dart';
import 'package:zendapp/src/services/sse_service.dart';
import 'package:zendapp/src/services/transfer_service.dart';
import 'package:zendapp/src/services/wallet_service.dart';
import 'package:zendapp/src/services/zendtag_service.dart';
import 'package:zendapp/src/services/sui_oauth_provider.dart';
import 'package:zendapp/src/services/sui_zklogin_service.dart';

ZendAppModel _buildModel() {
  const secureStorage = FlutterSecureStorage();
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
  final apiClient = ApiClient(
    baseUrl: 'https://test.invalid',
    secureStorage: secureStorage,
    dio: dio,
  );
  final authService = AuthService(apiClient: apiClient, secureStorage: secureStorage);
  final walletService = WalletService(apiClient: apiClient, secureStorage: secureStorage);
  final zendtagService = ZendtagService(apiClient: apiClient);
  final transferService = TransferService(apiClient: apiClient, walletService: walletService);
  final fxService = FxService(apiClient: apiClient);
  final recentContactsStore = RecentContactsStore(secureStorage: secureStorage);
  final sseService = SseService(baseUrl: 'https://test.invalid', secureStorage: secureStorage);
  final pushNotificationService = PushNotificationService(apiClient: apiClient);
  final appLockService = AppLockService();
  final savingsService = SavingsService(apiClient: apiClient);
  final pocketService = PocketService(apiClient: apiClient);
  // Constructed so ZendAppModel can be built; no test here signs in, and the
  // redirect host is unreachable, so the OAuth round-trip is never attempted.
  final zkLoginService = SuiZkLoginService(
    apiClient: apiClient,
    oauthProvider: GoogleZkLoginOAuthProvider(
      clientId: 'test.apps.googleusercontent.com',
      redirectUri: 'https://test.invalid/auth/callback',
      callbackUrlScheme: 'https',
      httpsHost: 'test.invalid',
      httpsPath: '/auth/callback',
      flow: SuiOAuthFlow.implicitIdToken,
    ),
  );

  return ZendAppModel(
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
    localDb: AppDatabase.instance,
    zkLoginService: zkLoginService,
  );
}

void main() {
  testWidgets(
    'HomeScreen shows the real balance after the first frame, not a '
    'permanent \$0.00, when the model already has a nonzero balance',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // The Savings/Pools summary cards render a fixed-height text column
      // that overflows by a few px at every test-harness viewport regardless
      // of size (their layout assumes real font metrics from bundled fonts
      // not present under `flutter test`). That overflow is unrelated to
      // this regression test's target (the hero balance's setState fix), so
      // suppress just the RenderFlex-overflow reporting for the duration of
      // this test rather than chasing an unrelated pre-existing layout issue.
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final isOverflow = details.exception is FlutterError &&
            details.exception.toString().contains('overflowed by');
        if (!isOverflow) previousOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousOnError);

      final model = _buildModel();
      // Simulate a balance that was already fetched before HomeScreen ever
      // mounted (e.g. restored from a previous session/tab).
      model.balance = 250.75;
      model.spendableBalance = 250.75;

      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => ZendScope(notifier: model, child: child!),
        home: HomeScreen(
          onOpenReceive: () {},
          onOpenWithdraw: () {},
          onViewAll: () {},
        ),
      ));

      // The hero balance Text carries a stable Key (set in home_screen.dart)
      // so this test doesn't depend on font size/family, which are cosmetic
      // and have already drifted once (88pt InstrumentSerif -> 72pt Satoshi)
      // independently of this regression test's actual concern: the
      // post-frame setState fix below.
      Finder heroBalance() => find.byKey(const Key('zend-hero-balance-text'));

      // First frame: _displayedBalance is still 0.0 (the field's initial
      // value) because the post-frame callback hasn't run yet.
      expect(
        tester.widget<Text>(heroBalance()).data,
        '\$0.00',
        reason: 'sanity check: the hero balance starts at its initial value '
            'before the post-frame callback runs',
      );

      // Let the post-frame callback fire (setState schedules the rebuild),
      // then let the 1200ms TweenAnimationBuilder counter animation settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));

      expect(
        tester.widget<Text>(heroBalance()).data,
        '\$250.75',
        reason: 'the post-frame callback must call setState so the real '
            'balance actually reaches the screen instead of leaving the '
            'hero number stuck at the initial \$0.00',
      );
    },
  );
}
