// Regression tests for two Contribute-sheet defects:
//
// 1. Double-submit: _onAmountConfirm awaited `requiresPinForAmount()` (a
//    secure-storage platform-channel round trip) before ever disabling the
//    "Contribute" button, so two fast taps could sign and submit two
//    on-chain contributions. Fixed with a `_confirmInFlight` guard.
//
// 2. Dismissible mid-transaction: PopScope only blocks the system back
//    gesture, not a bottom sheet's own drag-to-dismiss. A user could drag
//    the sheet away while a contribution was signing/submitting and never
//    learn the outcome. Fixed by claiming the vertical drag gesture with a
//    GestureDetector while the processing stage is active.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zendapp/src/core/zend_state.dart';
import 'package:zendapp/src/data/local/app_database.dart';
import 'package:zendapp/src/features/pools/contribute_sheet.dart';
import 'package:zendapp/src/features/pools/pool.dart';
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
  )..spendableBalance = 1000.0; // sufficient balance for every amount tested here
}

Pool _testPool() {
  return Pool(
    id: 'pool-1',
    name: 'Test Pool',
    targetAmount: 100.0,
    gathered: 0.0,
    participants: const [],
    createdAt: DateTime(2024, 1, 1),
    creatorUserId: 'creator-1',
    creatorZendtag: 'creator',
  );
}

void main() {
  testWidgets(
    'tapping Contribute twice in quick succession disables the button '
    'after the first tap instead of allowing a second submit',
    (tester) async {
      // Drive ContributeSheet through a real modal bottom sheet, same as
      // production (showContributeSheet) — it sizes itself as a fraction of
      // the ambient screen height. The default 800x600 test viewport is
      // too short for the amount stage's content (keypad + progress ring +
      // balance label) at 0.80 * height, so use a taller surface —
      // unrelated to the double-submit assertion this test makes.
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final model = _buildModel();
      await tester.pumpWidget(MaterialApp(
        // ZendScope must wrap the Navigator (via `builder`), not just `home`.
        // A modal bottom sheet is pushed as its own route — a sibling Overlay
        // entry alongside the `home` route, not a descendant of it — so
        // wrapping only `home` leaves the sheet's own context unable to find
        // ZendScope, and _userBalance's try/catch silently falls back to 0.0.
        builder: (context, child) => ZendScope(notifier: model, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ContributeSheet(pool: _testPool()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Enter a valid amount via the numeric keypad.
      await tester.tap(find.text('5'));
      await tester.pump();

      final button = find.widgetWithText(ElevatedButton, 'Contribute \$5');
      expect(button, findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(button).onPressed,
        isNotNull,
        reason: 'button should be enabled before the first tap',
      );

      // First tap starts the async requiresPinForAmount() lookup — before it
      // resolves, the button must already be disabled so a second tap in
      // that window is a no-op rather than a second submission.
      await tester.tap(button);
      await tester.pump(); // one frame: setState(_confirmInFlight = true) applied

      final buttonAfterTap = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Contribute \$5'),
      );
      expect(
        buttonAfterTap.onPressed,
        isNull,
        reason: 'button must be disabled immediately after the first tap, '
            'before requiresPinForAmount() resolves',
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'sheet remains drag-dismissible at the amount stage (dismissal is not '
    'globally disabled — only blocked during the processing stage)',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final model = _buildModel();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => ZendScope(notifier: model, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  isDismissible: true,
                  enableDrag: true,
                  builder: (_) => ContributeSheet(pool: _testPool()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ContributeSheet), findsOneWidget);

      await tester.fling(
        find.byType(ContributeSheet),
        const Offset(0, 500),
        3000,
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(ContributeSheet),
        findsNothing,
        reason: 'the amount stage (the default, non-processing stage) must '
            'remain drag-dismissible for users who change their mind',
      );
    },
  );

  testWidgets(
    'the sheet content claims the vertical drag gesture only while '
    'blockDismissal is active (initial/amount stage: callbacks are null)',
    (tester) async {
      // ContributeSheet sizes itself to a fraction of the ambient screen
      // height (_heightFactor), so — same as the real app, where it's shown
      // via showModalBottomSheet — drive it through an actual modal sheet
      // rather than dropping it straight into a Scaffold body, which starves
      // it of the screen-height context it expects and overflows.
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final model = _buildModel();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => ZendScope(notifier: model, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ContributeSheet(pool: _testPool()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The outermost GestureDetector inside ContributeSheet is the one
      // build() uses to claim/release the vertical drag axis depending on
      // stage. At the initial (amount) stage it must NOT claim the drag —
      // otherwise every user's attempt to interact vertically with the
      // amount stage (e.g. the surrounding sheet's own drag handle) would be
      // silently swallowed.
      final detector = tester.widget<GestureDetector>(
        find
            .descendant(
              of: find.byType(ContributeSheet),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(detector.onVerticalDragStart, isNull);
      expect(detector.onVerticalDragUpdate, isNull);
      expect(detector.onVerticalDragEnd, isNull);
    },
  );
}
