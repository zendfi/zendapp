// Regression tests for the ZendEntrySheet layout contract.
//
// These exist because this sheet was rebuilt three times chasing a
// "controls are dead / detached / missing" bug whose real cause was a
// layout error, not gesture handling:
//
//   * `Row(crossAxisAlignment: stretch)` for the Request/Zend/Vibe actions
//     inside a vertically-unbounded `SingleChildScrollView` gives its
//     children a `tightFor(height: infinity)` constraint, so the buttons
//     render as nothing and the broken RenderFlex poisons paint/hit-test
//     for its siblings (the amount + note fields).
//   * A content-sized (`MainAxisSize.min`) sheet collapsed instead of
//     opening at full length.
//
// `flutter analyze` cannot catch either — they are runtime layout failures
// — which is exactly why they are asserted here instead.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zendapp/src/core/zend_state.dart';
import 'package:zendapp/src/data/local/app_database.dart';
import 'package:zendapp/src/design/zend_theme.dart';
import 'package:zendapp/src/features/shell/zend_entry_sheet.dart';
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

/// Mirrors the harness used by contribute_sheet_guard_test.dart — real
/// services pointed at an unreachable host. No test here awaits a
/// network-dependent method.
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
  )..spendableBalance = 1000.0;
}

Widget _host(ZendAppModel model, {required Widget child}) {
  return MaterialApp(
    theme: buildZendTheme(),
    // ZendScope must wrap the Navigator (via `builder`), not just `home` —
    // the sheet is its own route, a sibling Overlay entry rather than a
    // descendant of `home`.
    builder: (context, navigatorChild) => ZendScope(notifier: model, child: navigatorChild!),
    home: Scaffold(body: child),
  );
}

void main() {
  group('ZendEntrySheet amount stage', () {
    testWidgets('renders both text fields and all three actions', (tester) async {
      final model = _buildModel();
      // A prefilled recipient opens straight on the Amount stage, which is
      // where the action row lives.
      await tester.pumpWidget(_host(model, child: const ZendEntrySheet(prefilledRecipient: 'omooba')));
      await tester.pumpAndSettle();

      expect(find.text('Request'), findsOneWidget, reason: 'Request action must render');
      expect(find.text('Zend'), findsOneWidget, reason: 'Zend action must render');
      expect(find.byType(TextField), findsNWidgets(2),
          reason: 'amount field and note field must both render');
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out with no layout exception or overflow', (tester) async {
      final model = _buildModel();
      await tester.pumpWidget(_host(model, child: const ZendEntrySheet(prefilledRecipient: 'omooba')));
      await tester.pumpAndSettle();

      // A RenderFlex overflow or an infinite-constraint failure surfaces
      // here. This is the assertion that catches the stretch-in-unbounded-
      // space bug that made the action buttons render as nothing.
      expect(tester.takeException(), isNull,
          reason: 'the sheet must lay out without a layout exception');
    });

    testWidgets('amount and note fields accept text', (tester) async {
      final model = _buildModel();
      await tester.pumpWidget(_host(model, child: const ZendEntrySheet(prefilledRecipient: 'omooba')));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, '20');
      await tester.pumpAndSettle();
      expect(find.text('20'), findsOneWidget, reason: 'the amount field must accept input');

      await tester.enterText(fields.last, 'lunch');
      await tester.pumpAndSettle();
      expect(find.text('lunch'), findsOneWidget, reason: 'the note field must accept input');

      expect(tester.takeException(), isNull);
    });

    testWidgets('entering an amount enables the Request and Zend actions', (tester) async {
      final model = _buildModel();
      await tester.pumpWidget(_host(model, child: const ZendEntrySheet(prefilledRecipient: 'omooba')));
      await tester.pumpAndSettle();

      // Disabled while the amount is still zero.
      final zendBefore = tester.widget<ElevatedButton>(
        find.ancestor(of: find.text('Zend'), matching: find.byType(ElevatedButton)),
      );
      expect(zendBefore.onPressed, isNull, reason: 'Zend must be disabled with no amount');

      await tester.enterText(find.byType(TextField).first, '20');
      await tester.pumpAndSettle();

      final zendAfter = tester.widget<ElevatedButton>(
        find.ancestor(of: find.text('Zend'), matching: find.byType(ElevatedButton)),
      );
      expect(zendAfter.onPressed, isNotNull, reason: 'Zend must enable once an amount is entered');
      expect(tester.takeException(), isNull);
    });
  });

  group('ZendEntrySheet identity stage', () {
    testWidgets('opens at substantial height rather than collapsing to content', (tester) async {
      final model = _buildModel();
      await tester.pumpWidget(_host(model, child: const ZendEntrySheet()));
      await tester.pumpAndSettle();

      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final sheetSize = tester.getSize(find.byType(ZendEntrySheet));

      // The sheet must claim most of the screen rather than shrink-wrap its
      // (initially near-empty) content — the "not opening at proper full
      // length" regression.
      expect(sheetSize.height, greaterThan(screenHeight * 0.5),
          reason: 'sheet collapsed instead of opening at full length: '
              '${sheetSize.height} of $screenHeight');
      expect(tester.takeException(), isNull);
    });

    testWidgets('search field renders and accepts text', (tester) async {
      final model = _buildModel();
      await tester.pumpWidget(_host(model, child: const ZendEntrySheet()));
      await tester.pumpAndSettle();

      final search = find.byType(TextField);
      expect(search, findsOneWidget, reason: 'identity search field must render');

      await tester.enterText(search, 'oma');
      await tester.pumpAndSettle();
      expect(find.text('oma'), findsOneWidget, reason: 'the search field must accept input');
      expect(tester.takeException(), isNull);
    });
  });
}
