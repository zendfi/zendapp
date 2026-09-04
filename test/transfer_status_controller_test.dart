// Tests for TransferStatusController — the app-scoped owner of send/request
// execution behind the instant flow.
//
// The flow's whole premise is that the sheet closes the moment the user
// commits, so the outcome resolves with no sheet left to show it. That's
// only an honest trade if a failure is as loud as a success, which is what
// most of these assert:
//
//   * a failed send lands on `failed`, carries a reason, and NEVER
//     auto-dismisses
//   * a failure that resolves after a newer action started still takes over
//     the banner, rather than being dropped for tidy semantics
//   * the action id is stable across `sending → terminal`, which is what
//     lets the banner mutate in place instead of replaying its entrance
//
// No network is mocked: the services point at an unreachable host, so the
// transfer genuinely fails. That's deliberate — it asserts the failure
// path holds for *whatever* the stack throws, not just for one exception
// type someone remembered to stub.
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zendapp/src/core/zend_state.dart';
import 'package:zendapp/src/data/local/app_database.dart';
import 'package:zendapp/src/features/send/transfer_status_controller.dart';
import 'package:zendapp/src/services/api_client.dart';
import 'package:zendapp/src/services/app_lock_service.dart';
import 'package:zendapp/src/services/auth_service.dart';
import 'package:zendapp/src/services/fx_service.dart';
import 'package:zendapp/src/services/pocket_service.dart';
import 'package:zendapp/src/services/push_notification_service.dart';
import 'package:zendapp/src/services/recent_contacts_store.dart';
import 'package:zendapp/src/services/savings_service.dart';
import 'package:zendapp/src/services/sse_service.dart';
import 'package:zendapp/src/services/sui_oauth_provider.dart';
import 'package:zendapp/src/services/sui_zklogin_service.dart';
import 'package:zendapp/src/services/transfer_service.dart';
import 'package:zendapp/src/services/wallet_service.dart';
import 'package:zendapp/src/services/zendtag_service.dart';

ZendAppModel _buildModel() {
  const secureStorage = FlutterSecureStorage();
  // Short timeouts: these requests are expected to fail, and there's no
  // reason for the suite to wait out a default connect timeout to find out.
  final dio = Dio(BaseOptions(
    baseUrl: 'https://test.invalid',
    connectTimeout: const Duration(milliseconds: 300),
    receiveTimeout: const Duration(milliseconds: 300),
  ));
  final apiClient = ApiClient(
    baseUrl: 'https://test.invalid',
    secureStorage: secureStorage,
    dio: dio,
  );
  final walletService = WalletService(apiClient: apiClient, secureStorage: secureStorage);

  return ZendAppModel(
    authService: AuthService(apiClient: apiClient, secureStorage: secureStorage),
    walletService: walletService,
    zendtagService: ZendtagService(apiClient: apiClient),
    transferService: TransferService(apiClient: apiClient, walletService: walletService),
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

const _sessionAuth = TransferAuth.forTest(TransferAuthMode.session);

/// flutter_secure_storage has no implementation under `flutter_test`, and
/// ApiClient reads the auth token from it inside a Dio *queued* interceptor.
/// Left unstubbed, the resulting MissingPluginException escapes as an
/// unhandled async error and the request future never completes — the call
/// hangs rather than failing, which looks like a controller bug but isn't.
/// Returning null for every read lets the request proceed and fail honestly
/// at the network layer, which is what these tests are actually about.
void _stubSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_stubSecureStorage);

  group('failed send', () {
    test('lands on failed, carries a reason, and never auto-dismisses', () async {
      final model = _buildModel();
      final controller = model.transferStatus;

      await controller.send(
        amount: 20,
        recipientZendtag: 'omooba',
        auth: _sessionAuth,
        recipientDisplayName: 'Omooba',
        note: 'lunch',
      );

      final status = controller.status;
      expect(status, isNotNull, reason: 'a failure must leave something on screen');
      expect(status!.kind, TransferStatusKind.failed);
      expect(status.message, isNotNull, reason: 'a failure must say why');
      expect(status.message, isNotEmpty);

      // The banner must still be there well after a success would have
      // faded. Optimistic UI is only honest if failures stay put.
      await Future<void>.delayed(
        TransferStatusController.sentLinger + const Duration(milliseconds: 300),
      );
      expect(controller.status?.kind, TransferStatusKind.failed,
          reason: 'a failed send must not auto-dismiss');
    });

    test('keeps the failing amount and recipient so the banner names them', () async {
      final model = _buildModel();
      final controller = model.transferStatus;

      await controller.send(
        amount: 20,
        recipientZendtag: 'omooba',
        auth: _sessionAuth,
      );

      final status = controller.status!;
      expect(status.amount, 20);
      expect(status.recipientZendtag, 'omooba');
      // "Couldn't send" alone would leave the user guessing which payment.
      expect(status.amountLabel, '\$20');
      expect(status.recipientLabel, '@omooba');
    });

    test('is retryable, since nothing is known to have moved', () async {
      final model = _buildModel();
      final controller = model.transferStatus;

      await controller.send(amount: 5, recipientZendtag: 'omooba', auth: _sessionAuth);

      expect(controller.status!.canRetry, isTrue);
    });

    test('dismiss clears it', () async {
      final model = _buildModel();
      final controller = model.transferStatus;

      await controller.send(amount: 5, recipientZendtag: 'omooba', auth: _sessionAuth);
      expect(controller.status, isNotNull);

      controller.dismiss();
      expect(controller.status, isNull);
    });
  });

  group('failed request', () {
    test('is reported as a request, not a send', () async {
      final model = _buildModel();
      final controller = model.transferStatus;

      await controller.request(amount: 12, recipientZendtag: 'omooba');

      final status = controller.status!;
      expect(status.kind, TransferStatusKind.failed);
      // Drives "Couldn't request $12 from @omooba" rather than "send ... to".
      expect(status.isRequest, isTrue);
      expect(status.message, isNotNull);
    });
  });

  group('banner identity', () {
    test('action id is stable from sending through to the terminal status', () async {
      final model = _buildModel();
      final controller = model.transferStatus;

      final seen = <TransferStatus>[];
      controller.addListener(() {
        final s = controller.status;
        if (s != null) seen.add(s);
      });

      await controller.send(amount: 7, recipientZendtag: 'omooba', auth: _sessionAuth);

      expect(seen.length, greaterThanOrEqualTo(2),
          reason: 'expected at least a sending status and a terminal one');
      expect(seen.first.kind, TransferStatusKind.sending);
      expect(seen.last.kind, TransferStatusKind.failed);
      // Same id across the lifecycle is what makes the banner mutate in
      // place instead of tearing down and replaying its slide-in.
      expect(seen.last.actionId, seen.first.actionId,
          reason: 'a single send must keep one action id throughout');
    });

    test('a second send gets a new action id, so its banner is a new event', () async {
      final model = _buildModel();
      final controller = model.transferStatus;

      await controller.send(amount: 1, recipientZendtag: 'omooba', auth: _sessionAuth);
      final first = controller.status!.actionId;

      await controller.send(amount: 2, recipientZendtag: 'omooba', auth: _sessionAuth);
      final second = controller.status!.actionId;

      expect(second, isNot(first));
    });
  });

  group('TransferStatus copy', () {
    test('amountLabel drops the decimals only on whole amounts', () {
      const whole = TransferStatus(
        kind: TransferStatusKind.sent,
        amount: 20,
        actionId: 1,
        recipientZendtag: 'omooba',
      );
      const fractional = TransferStatus(
        kind: TransferStatusKind.sent,
        amount: 20.5,
        actionId: 1,
        recipientZendtag: 'omooba',
      );
      expect(whole.amountLabel, '\$20');
      expect(fractional.amountLabel, '\$20.50');
    });

    test('recipientLabel falls back to the email for a non-Zend recipient', () {
      const byEmail = TransferStatus(
        kind: TransferStatusKind.sent,
        amount: 20,
        actionId: 1,
        recipientEmail: 'someone@example.com',
      );
      expect(byEmail.recipientLabel, 'someone@example.com');
    });

    test('copyWith preserves the action id and the recipient', () {
      const sending = TransferStatus(
        kind: TransferStatusKind.sending,
        amount: 20,
        actionId: 42,
        recipientZendtag: 'omooba',
        note: 'lunch',
      );
      final failed = sending.copyWith(
        kind: TransferStatusKind.failed,
        message: 'nope',
        canRetry: true,
      );

      expect(failed.actionId, 42);
      expect(failed.recipientZendtag, 'omooba');
      expect(failed.note, 'lunch');
      expect(failed.amount, 20);
      expect(failed.message, 'nope');
    });
  });
}
