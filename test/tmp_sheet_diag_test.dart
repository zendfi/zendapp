// TEMPORARY diagnostic — exercises the REAL modal route with a simulated
// keyboard and dumps geometry. Delete after diagnosis.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

ZendAppModel _buildModel() {
  const secureStorage = FlutterSecureStorage();
  final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
  final apiClient = ApiClient(baseUrl: 'https://test.invalid', secureStorage: secureStorage, dio: dio);
  return ZendAppModel(
    authService: AuthService(apiClient: apiClient, secureStorage: secureStorage),
    walletService: WalletService(apiClient: apiClient, secureStorage: secureStorage),
    zendtagService: ZendtagService(apiClient: apiClient),
    transferService: TransferService(
        apiClient: apiClient,
        walletService: WalletService(apiClient: apiClient, secureStorage: secureStorage)),
    fxService: FxService(apiClient: apiClient),
    recentContactsStore: RecentContactsStore(secureStorage: secureStorage),
    sseService: SseService(baseUrl: 'https://test.invalid', secureStorage: secureStorage),
    pushNotificationService: PushNotificationService(apiClient: apiClient),
    appLockService: AppLockService(),
    savingsService: SavingsService(apiClient: apiClient),
    pocketService: PocketService(apiClient: apiClient),
    localDb: AppDatabase.instance,
    zkLoginService: SuiZkLoginService(
      apiClient: apiClient,
      oauthProvider: GoogleZkLoginOAuthProvider(
        clientId: 'test.apps.googleusercontent.com',
        redirectUri: 'https://test.invalid/auth/callback',
        callbackUrlScheme: 'https',
        httpsHost: 'test.invalid',
        httpsPath: '/auth/callback',
        flow: SuiOAuthFlow.implicitIdToken,
      ),
    ),
  )..spendableBalance = 1000.0;
}

void _dump(WidgetTester tester, String label, Finder f) {
  if (f.evaluate().isEmpty) {
    debugPrint('  $label: NOT FOUND');
    return;
  }
  final r = tester.getRect(f.first);
  debugPrint('  $label: $r  size=${r.size}');
}

/// Is the centre of [f] actually reachable by a pointer?
bool _hittable(WidgetTester tester, Finder f) {
  if (f.evaluate().isEmpty) return false;
  final centre = tester.getCenter(f.first);
  final target = tester.renderObject(f.first);
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, centre, tester.view.viewId);
  return result.path.any((e) => e.target == target || _isDescendantTarget(e.target, target));
}

bool _isDescendantTarget(Object hit, RenderObject ancestor) {
  if (hit is! RenderObject) return false;
  RenderObject? n = hit;
  while (n != null) {
    if (n == ancestor) return true;
    n = n.parent;
  }
  return false;
}

void main() {
  testWidgets('DIAG real modal route, keyboard closed then open', (tester) async {
    // A common phone: 393 x 852 logical @ 3.0
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    tester.view.viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    final model = _buildModel();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: buildZendTheme(),
      builder: (context, child) => ZendScope(notifier: model, child: child!),
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })),
    ));

    showZendEntrySheet(ctx, prefilledRecipient: 'omooba');
    await tester.pumpAndSettle();

    debugPrint('=== KEYBOARD CLOSED ===');
    debugPrint('  screen: ${tester.view.physicalSize / tester.view.devicePixelRatio}');
    _dump(tester, 'sheet', find.byType(ZendEntrySheet));
    _dump(tester, 'amount field', find.byType(TextField).first);
    _dump(tester, 'note field', find.byType(TextField).last);
    _dump(tester, 'Request', find.text('Request'));
    _dump(tester, 'Zend', find.text('Zend'));
    debugPrint('  hittable amount=${_hittable(tester, find.byType(TextField).first)} '
        'note=${_hittable(tester, find.byType(TextField).last)} '
        'Request=${_hittable(tester, find.text('Request'))} '
        'Zend=${_hittable(tester, find.text('Zend'))}');
    debugPrint('  exception: ${tester.takeException()}');

    // Now simulate the keyboard being up (it will be, since we autofocus).
    tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
    await tester.pumpAndSettle();

    debugPrint('=== KEYBOARD OPEN (336dp) ===');
    _dump(tester, 'sheet', find.byType(ZendEntrySheet));
    _dump(tester, 'amount field', find.byType(TextField).first);
    _dump(tester, 'note field', find.byType(TextField).last);
    _dump(tester, 'Request', find.text('Request'));
    _dump(tester, 'Zend', find.text('Zend'));
    debugPrint('  hittable amount=${_hittable(tester, find.byType(TextField).first)} '
        'note=${_hittable(tester, find.byType(TextField).last)} '
        'Request=${_hittable(tester, find.text('Request'))} '
        'Zend=${_hittable(tester, find.text('Zend'))}');
    debugPrint('  exception: ${tester.takeException()}');
  });

  testWidgets('DIAG identity stage real modal route with keyboard', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    tester.view.viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    final model = _buildModel();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: buildZendTheme(),
      builder: (context, child) => ZendScope(notifier: model, child: child!),
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })),
    ));

    showZendEntrySheet(ctx);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
    await tester.pumpAndSettle();

    debugPrint('=== IDENTITY, KEYBOARD OPEN ===');
    _dump(tester, 'sheet', find.byType(ZendEntrySheet));
    _dump(tester, 'search field', find.byType(TextField));
    debugPrint('  hittable search=${_hittable(tester, find.byType(TextField))}');
    debugPrint('  exception: ${tester.takeException()}');
  });
}
