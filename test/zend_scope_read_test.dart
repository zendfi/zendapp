// Regression test for ZendScope.read() vs ZendScope.of().
//
// ZendScope.of() calls dependOnInheritedWidgetOfExactType(), which is
// illegal before a State's initState() has completed and throws a
// FlutterError in debug builds ("...was called before SomeState.initState()
// completed"). That assertion is stripped in release builds, so several
// screens called ZendScope.of() directly from initState()/dispose() without
// anyone noticing outside a debug session. ZendScope.read() is the safe,
// non-subscribing alternative for one-shot reads in those lifecycle methods.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zendapp/src/core/zend_state.dart';
import 'package:zendapp/src/data/local/app_database.dart';
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

/// Builds a ZendAppModel wired to real services pointed at an unreachable
/// host — mirrors zend_app_model_reset_state_test.dart's helper. No test in
/// this file awaits a network-dependent method.
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
  );
}

class _ReadsInInitState extends StatefulWidget {
  const _ReadsInInitState();
  @override
  State<_ReadsInInitState> createState() => _ReadsInInitStateState();
}

class _ReadsInInitStateState extends State<_ReadsInInitState> {
  int? seenUnread;

  @override
  void initState() {
    super.initState();
    // Must not throw. If this used ZendScope.of(context) instead, Flutter
    // would throw a FlutterError before this line returns.
    seenUnread = ZendScope.read(context).dmUnreadTotal;
  }

  @override
  Widget build(BuildContext context) => Text('$seenUnread');
}

class _DependsInBuild extends StatefulWidget {
  const _DependsInBuild();
  @override
  State<_DependsInBuild> createState() => _DependsInBuildState();
}

class _DependsInBuildState extends State<_DependsInBuild> {
  @override
  Widget build(BuildContext context) {
    // ZendScope.of() from build() must still work and subscribe to changes.
    final model = ZendScope.of(context);
    return Text('${model.dmUnreadTotal}');
  }
}

void main() {
  testWidgets('ZendScope.read() does not throw when called from initState()',
      (tester) async {
    final model = _buildModel();
    model.dmUnreadTotal = 3;

    await tester.pumpWidget(MaterialApp(
      home: ZendScope(
        notifier: model,
        child: const _ReadsInInitState(),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('ZendScope.of() from build() still rebuilds on notifyListeners()',
      (tester) async {
    final model = _buildModel();
    model.dmUnreadTotal = 1;

    await tester.pumpWidget(MaterialApp(
      home: ZendScope(
        notifier: model,
        child: const _DependsInBuild(),
      ),
    ));
    expect(find.text('1'), findsOneWidget);

    model.setDmUnreadTotal(5);
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets(
    'ZendScope.of() throws when called from initState() '
    '(documents the exact bug class ZendScope.read() exists to avoid)',
    (tester) async {
      final model = _buildModel();

      await tester.pumpWidget(MaterialApp(
        home: ZendScope(
          notifier: model,
          child: const _WronglyUsesOfInInitState(),
        ),
      ));

      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (e) => e.toString(),
          'message',
          contains('initState'),
        ),
      );
    },
  );
}

/// Deliberately reproduces the historical bug for the regression test above:
/// calling ZendScope.of() (which subscribes via
/// dependOnInheritedWidgetOfExactType) from initState() throws in debug mode.
class _WronglyUsesOfInInitState extends StatefulWidget {
  const _WronglyUsesOfInInitState();
  @override
  State<_WronglyUsesOfInInitState> createState() =>
      _WronglyUsesOfInInitStateState();
}

class _WronglyUsesOfInInitStateState extends State<_WronglyUsesOfInInitState> {
  @override
  void initState() {
    super.initState();
    ZendScope.of(context); // ignore: unused_result
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
