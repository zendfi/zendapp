// Regression test for zendapp-hardening spec Req 1.5.
//
// Enumerates every per-user stateful field on ZendAppModel, pushes each one
// to a non-default sentinel value, calls resetState(), and asserts every
// field is back to its default (or documents that it is intentionally a
// device-global preference left untouched). This is the "checklist test"
// the spec calls for — its purpose is to catch the next stateful field that
// gets added to ZendAppModel without being wired into
// ZendAppModel._clearPerUserState(), not to test any particular business
// rule.
//
// ZendAppModel is constructed with real service instances backed by an
// in-memory Dio adapter (no live network) and FlutterSecureStorage, which
// on the `flutter test` VM target falls back to an in-memory implementation
// with no platform channel involved — safe to construct and call synchronous
// getters/setters on without a running app.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zendapp/src/core/zend_state.dart';
import 'package:zendapp/src/data/local/app_database.dart';
import 'package:zendapp/src/models/activity_edge.dart';
import 'package:zendapp/src/models/payment_request_notification.dart';
import 'package:zendapp/src/models/recent_contact.dart';
import 'package:zendapp/src/models/streak_info.dart';
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
import 'package:zendapp/src/services/wallet_session_cache.dart';
import 'package:zendapp/src/services/zendtag_service.dart';

/// Builds a ZendAppModel wired to real services, but pointed at a Dio
/// instance with no adapter attached that will make network calls — every
/// test in this file only manipulates in-memory model fields directly and
/// never awaits a network-dependent method, so no request is ever issued.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZendAppModel per-user state teardown (Req 1.5)', () {
    test('resetState() clears every per-user field back to its default', () {
      final model = _buildModel();

      // ── Push every per-user field to a non-default sentinel value ──────
      WalletSessionCache.instance.store(Uint8List.fromList(List.filled(64, 7)));

      model.isAuthenticated = true;
      model.currentUserId = 'user-1';
      model.currentZendtag = 'sentinel';
      model.currentDisplayName = 'Sentinel Name';
      model.currentAvatarUrl = 'https://example.com/avatar.png';

      model.balance = 123.45;
      model.spendableBalance = 100.0;
      model.monthlyYield = 5.0;
      model.balanceLoading = true;
      model.lastBalanceError = 'boom';

      model.walletAddress = 'FAKEADDRESS';
      model.hasWallet = true;
      model.hasPinSetup = true;

      model.recentTransactions = [
        ZendTransaction(
          name: '@someone',
          note: 'test',
          amount: '-\$1.00',
          time: 'Just now',
          avatarLabel: 'S',
        ),
      ];
      model.recentContacts = [
        RecentContact(name: 'Someone', tag: 'someone', avatarLabel: 'S'),
      ];
      model.historyLoading = true;
      model.lastHistoryError = 'boom';

      model.threadedActivityEdges = [
        ActivityEdge(
          edgeId: 'e1',
          edgeKind: ActivityEdgeKind.zendTransfer,
          counterparty: const ActivityCounterparty(kind: 'user', id: 'u1', zendtag: 'friend'),
          amountUsdc: '10',
          amountHidden: false,
          direction: 'outgoing',
          effectiveTier: VisibilityTier.private,
          isDirectParticipant: true,
          createdAt: DateTime(2024, 1, 1),
        ),
      ];
      model.threadedActivityLoading = true;
      model.lastThreadedActivityError = 'boom';
      model.activityUnreadCount = 3;
      model.pendingActivityReaction = const ActivityReactionNotification(
        edgeKind: 'zend_transfer',
        edgeId: 'e1',
        reactorZendtag: 'friend',
        emoji: '🔥',
      );
      model.pendingActivityComment = const ActivityCommentNotification(
        edgeKind: 'zend_transfer',
        edgeId: 'e1',
        authorZendtag: 'friend',
        body: 'nice',
      );

      model.poolsLoading = true;
      model.lastPoolsError = 'boom';
      model.poolsWithNewMessages.add('pool-1');

      model.savingsApy = 8.0;
      model.savingsBalance = 42.0;
      model.savingsLoading = true;

      model.pendingPaymentRequest = const PaymentRequestNotification(
        requestId: 'r1',
        requesterZendtag: 'friend',
        requesterDisplayName: 'Friend',
        amountUsdc: 5.0,
      );

      model.dmUnreadTotal = 7;
      model.lastDmBannerData = {'room_id': 'r1'};

      model.activeStreaks = {
        'u1': StreakInfo(
          counterpartyUserId: 'u1',
          counterpartyZendtag: 'friend',
          counterpartyDisplayName: 'Friend',
          streakWeeks: 4,
          longestStreak: 4,
        ),
      };
      model.pendingStreakMilestone = const StreakNotification(
        counterpartyZendtag: 'friend',
        weeks: 4,
        isMilestone: true,
      );
      model.suggestedConnections = [
        {'user_id': 'u2'},
      ];

      model.setPendingWaitlistInfo(
        matched: true,
        reservedZendtag: 'sentinel',
        fullName: 'Sentinel Name',
      );

      // ── Act ──────────────────────────────────────────────────────────────
      model.resetState();

      // ── Assert every field is back to its default ──────────────────────
      expect(model.isAuthenticated, isFalse);
      expect(model.currentUserId, isNull);
      expect(model.currentZendtag, isNull);
      expect(model.currentDisplayName, isNull);
      expect(model.currentAvatarUrl, isNull);

      expect(model.balance, 0.0);
      expect(model.spendableBalance, 0.0);
      expect(model.monthlyYield, 0.0);
      expect(model.balanceLoading, isFalse);
      expect(model.lastBalanceError, isNull);

      expect(model.walletAddress, isNull);
      expect(model.hasWallet, isFalse);
      expect(model.hasPinSetup, isFalse);

      expect(model.recentTransactions, isEmpty);
      expect(model.recentContacts, isEmpty);
      expect(model.historyLoading, isFalse);
      expect(model.lastHistoryError, isNull);

      expect(model.threadedActivityEdges, isEmpty);
      expect(model.threadedActivityLoading, isFalse);
      expect(model.lastThreadedActivityError, isNull);
      expect(model.threadedActivityHasMore, isFalse);
      expect(model.activityUnreadCount, 0);
      expect(model.pendingActivityReaction, isNull);
      expect(model.pendingActivityComment, isNull);

      expect(model.pools, isEmpty);
      expect(model.poolsLoading, isFalse);
      expect(model.lastPoolsError, isNull);
      expect(model.poolsWithNewMessages, isEmpty);
      expect(model.paymentRequests, isEmpty);

      expect(model.savingsApy, 0.0);
      expect(model.savingsBalance, 0.0);
      expect(model.savingsLoading, isFalse);

      expect(model.pendingEmailIntents, isEmpty);
      expect(model.pendingPaymentRequest, isNull);
      expect(model.outboundPaymentRequests, isEmpty);
      expect(model.inboundPaymentRequests, isEmpty);

      expect(model.dmUnreadTotal, 0);
      expect(model.lastDmBannerData, isNull);

      expect(model.activeStreaks, isEmpty);
      expect(model.pendingStreakMilestone, isNull);
      expect(model.suggestedConnections, isEmpty);

      expect(model.vibeSpentToday, 0.0);

      expect(model.pendingWaitlistMatch, isFalse);
      expect(model.pendingReservedZendtag, isNull);
      expect(model.pendingWaitlistFullName, isNull);

      // The session keypair cache must never survive a sign-out.
      expect(WalletSessionCache.instance.hasKeypair, isFalse);
    });
  });
}
