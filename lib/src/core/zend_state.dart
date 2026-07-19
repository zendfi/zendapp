import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/zend_tokens.dart';
import '../features/pools/pool.dart';
import '../features/request/payment_request.dart';
import '../models/api_models.dart';
import '../models/email_intent.dart';
import '../models/recent_contact.dart';
import '../models/activity_edge.dart';
import '../services/activity_data_service.dart';
import '../services/app_lock_service.dart';
import '../services/auth_service.dart';
import '../services/contacts_service.dart';
import '../services/drop_discoverability_service.dart';
import '../services/email_intent_service.dart';
import '../services/fx_service.dart';
import '../services/push_notification_service.dart';
import '../services/recent_contacts_store.dart';
import '../services/signing_policy_service.dart';
import '../services/sound_service.dart';
import '../services/sse_service.dart';
import '../services/transfer_service.dart';
import '../services/pocket_service.dart';
import '../services/savings_service.dart';
import '../services/wallet_service.dart';
import '../services/wallet_session_cache.dart';
import '../services/zendtag_service.dart';
import '../services/cloud_backup_service.dart';
import '../services/recovery_service.dart';
import '../data/local/app_database.dart';
import '../models/payment_request_notification.dart';
import '../models/payment_request_item.dart';
import '../models/pocket_models.dart';
import '../models/savings_models.dart';

const Map<String, String> _localeGreetings = {
  'yo': 'Ẹ káàbọ̀',
  'ig': 'Nnọọ',
  'ha': 'Sannu',
  'pt': 'Oi',
  'es': 'Hola',
  'fr': 'Salut',
  'de': 'Hey',
  'ar': 'أهلاً',
  'zh': '嗨',
  'ja': 'やあ',
  'ko': '안녕',
  'sw': 'Habari',
  'en-GB': 'Wagwan',
};

const List<String> _fallbackGreetings = ['Hey', 'Hello', 'Hi'];

String _greetingForLocale(Locale locale) {
  final tag = locale.toLanguageTag();

  if (_localeGreetings.containsKey(tag)) return _localeGreetings[tag]!;

  final lang = locale.languageCode;
  if (_localeGreetings.containsKey(lang)) return _localeGreetings[lang]!;

  return _fallbackGreetings[Random().nextInt(_fallbackGreetings.length)];
}

class ZendTransaction {
  ZendTransaction({
    required this.name,
    required this.note,
    required this.amount,
    required this.time,
    required this.avatarLabel,
    this.amountColor,
    this.entry,
    this.bankOrder,
    this.avatarUrl,
    this.countryCode,
    this.isPending = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String name;
  final String note;
  final String amount;
  final String time;
  final String avatarLabel;
  final Color? amountColor;
  final DateTime createdAt;
  final bool isPending;
  final TransferHistoryEntry? entry;
  final Map<String, dynamic>? bankOrder;
  final String? avatarUrl;
  final String? countryCode;
}

/// A pending in-app banner for "someone reacted to an Activity_Edge you're
/// a party on" — delivered over SSE (`SseEventType.activityEdgeReaction`).
class ActivityReactionNotification {
  const ActivityReactionNotification({
    required this.edgeKind,
    required this.edgeId,
    required this.reactorZendtag,
    required this.emoji,
  });

  final String edgeKind;
  final String edgeId;
  final String reactorZendtag;
  final String emoji;
}

/// A pending in-app banner for "someone commented on an Activity_Edge
/// you're a party on" — delivered over SSE (`SseEventType.activityEdgeComment`).
class ActivityCommentNotification {
  const ActivityCommentNotification({
    required this.edgeKind,
    required this.edgeId,
    required this.authorZendtag,
    required this.body,
  });

  final String edgeKind;
  final String edgeId;
  final String authorZendtag;
  final String body;
}

class ZendAppModel extends ChangeNotifier {
  ZendAppModel({
    required this.authService,
    required this.walletService,
    required this.zendtagService,
    required this.transferService,
    required this.fxService,
    required this.recentContactsStore,
    required this.sseService,
    required this.pushNotificationService,
    required this.appLockService,
    required this.savingsService,
    required this.pocketService,
    required this.localDb,
    EmailIntentService? emailIntentService,
  }) : _emailIntentService = emailIntentService;

  final AuthService authService;
  final WalletService walletService;
  final ZendtagService zendtagService;
  final TransferService transferService;
  final FxService fxService;
  final RecentContactsStore recentContactsStore;
  final SseService sseService;
  final PushNotificationService pushNotificationService;
  final AppLockService appLockService;
  final SavingsService savingsService;
  final PocketService pocketService;

  /// Drop discoverability service — manages BLE beacon advertising as a receiver.
  late final DropDiscoverabilityService dropDiscoverabilityService =
      DropDiscoverabilityService(
    apiClient: walletService.apiClient,
    walletService: walletService,
  );

  /// Contacts service — reads device contacts and resolves against Zend accounts.
  late final ContactsService contactsService =
      ContactsService(apiClient: walletService.apiClient);

  /// Activity Relationship Graph (Phase 2/3) data service — parallel to
  /// [transferService]/`fetchHistory()`, not a replacement for it.
  late final ActivityDataService activityDataService =
      ActivityDataService(apiClient: walletService.apiClient);

  /// On-device SQLite database for pool message persistence.
  final AppDatabase localDb;

  /// Optional email intent service — injected when email intents feature is active.
  final EmailIntentService? _emailIntentService;

  /// Public accessor for the email intent service.
  EmailIntentService? get emailIntentService => _emailIntentService;

  /// Signing policy service — controls session vs PIN-per-payment behaviour.
  final SigningPolicyService signingPolicyService = SigningPolicyService();

  /// Recovery service — manages National ID recovery packet creation/decryption.
  /// Injected lazily after wallet service is ready.
  RecoveryService? _recoveryService;
  RecoveryService get recoveryService {
    _recoveryService ??= RecoveryService(
      wallet: walletService,
      cloud: CloudBackupService(),
    );
    return _recoveryService!;
  }

  // ── SSE subscription ──
  StreamSubscription<SseEvent>? _sseSubscription;

  // ── Drop confirmed stream ──
  /// Broadcasts Drop confirmation events to any listening UI (Drop sheet, home screen).
  /// Each event map contains: role, amount_usdc, counterparty_zendtag, note?, tx_hash.
  final _dropConfirmedController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get dropConfirmedEvents => _dropConfirmedController.stream;

  // ── Fallback polling (used when SSE is unavailable) ──
  Timer? _pollingTimer;
  static const Duration _pollingInterval = Duration(seconds: 30);
  bool _sseConnected = false;

  /// Start real-time updates via SSE.
  /// Guard: if SSE is already active and connected, don't restart it —
  /// app-resume cycles would otherwise kill healthy connections.
  void startRealTimeUpdates() {
    if (_sseConnected && _sseSubscription != null) {
      // SSE is working fine — just restart fallback polling guard in case
      // the polling timer expired while we were in background.
      return;
    }
    _stopAll();
    _sseConnected = false;

    // Start SSE
    sseService.start();
    _sseSubscription = sseService.events.listen(
      _onSseEvent,
      onError: (_) {
        _sseConnected = false;
        _startFallbackPolling();
      },
      onDone: () {
        // SSE stream ended — reset connected flag and start fallback polling.
        // This ensures the guard in startRealTimeUpdates() doesn't block reconnection.
        _sseConnected = false;
        if (isAuthenticated) _startFallbackPolling();
      },
    );

    // Start fallback polling immediately — it will be cancelled if SSE delivers
    // its first event within the polling interval, confirming SSE is working.
    _startFallbackPolling();
  }

  void _onSseEvent(SseEvent event) {
    // SSE is working — cancel fallback polling
    if (!_sseConnected) {
      _sseConnected = true;
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }

    switch (event.type) {
      case SseEventType.transferUpdate:
        // A transfer happened — badge the Activity tab and refresh data.
        activityUnreadCount++;
        // Immediately patch any matching pending entry to 'confirmed' so open
        // receipt sheets update live without waiting for fetchHistory() to complete.
        _patchTransferStatus(event.data);
        unawaited(fetchBalance());
        unawaited(fetchHistory());
        if (_threadedActivityEverLoaded) unawaited(fetchThreadedActivity());
      case SseEventType.transferFailed:
        unawaited(fetchHistory());
        if (_threadedActivityEverLoaded) unawaited(fetchThreadedActivity());
      case SseEventType.balanceUpdate:
        // Direct balance update from server — re-fetch for accuracy
        // (empty usdc_balance means "please re-fetch")
        final raw = event.data['usdc_balance'] as String?;
        if (raw != null && raw.isNotEmpty) {
          final parsed = double.tryParse(raw);
          if (parsed != null) {
            balance = parsed;
            notifyListeners();
          }
        } else {
          unawaited(fetchBalance());
        }
      case SseEventType.refreshRequired:
        // Server told us we missed events — do a full refresh
        unawaited(fetchBalance());
        unawaited(fetchHistory());
        if (_threadedActivityEverLoaded) unawaited(fetchThreadedActivity());
      case SseEventType.poolContribution:
        // Update the cached pool's gathered amount
        final poolId = event.data['pool_id'] as String?;
        final gatheredStr = event.data['gathered_amount_usdc'] as String?;
        if (poolId != null && gatheredStr != null) {
          final gathered = double.tryParse(gatheredStr);
          final idx = pools.indexWhere((p) => p.id == poolId);
          if (idx >= 0 && gathered != null) {
            pools[idx].gathered = gathered;
            notifyListeners();
            // Play contribution chime (background — not currently viewing)
            unawaited(PoolSoundService.playContributionChime());
          } else if (idx < 0) {
            // Pool not in local cache — refresh the full list
            unawaited(fetchPools());
          }
        }
      case SseEventType.poolStatusChanged:
        // Update the cached pool's status
        final poolId = event.data['pool_id'] as String?;
        final newStatus = event.data['new_status'] as String?;
        if (poolId != null && newStatus != null) {
          final idx = pools.indexWhere((p) => p.id == poolId);
          if (idx >= 0) {
            final statusMap = {
              'active': PoolStatus.active,
              'completed': PoolStatus.completed,
              'expired': PoolStatus.expired,
              'cancelled': PoolStatus.cancelled,
            };
            final status = statusMap[newStatus];
            if (status != null) {
              pools[idx].status = status;
              notifyListeners();
            }
          } else {
            // Pool not in local cache — refresh
            unawaited(fetchPools());
          }
        }
      // poolReaction and poolReactionRemoved are handled directly
      // by the MissionRoom widget — no-op at the model level.
      // Note: poolMessage was removed — pool chat is WebSocket-only now.
      case SseEventType.poolReaction:
      case SseEventType.poolReactionRemoved:
        break;
      case SseEventType.paymentRequest:
        // Show in-app banner for incoming payment requests
        final notification = PaymentRequestNotification.fromJson(event.data);
        pendingPaymentRequest = notification;
        notifyListeners();
      case SseEventType.activityEdgeReaction:
        activityUnreadCount++;
        pendingActivityReaction = ActivityReactionNotification(
          edgeKind: event.data['edge_kind'] as String? ?? '',
          edgeId: event.data['edge_id'] as String? ?? '',
          reactorZendtag: event.data['reactor_zendtag'] as String? ?? '',
          emoji: event.data['emoji'] as String? ?? '',
        );
        notifyListeners();
      case SseEventType.activityEdgeComment:
        activityUnreadCount++;
        pendingActivityComment = ActivityCommentNotification(
          edgeKind: event.data['edge_kind'] as String? ?? '',
          edgeId: event.data['edge_id'] as String? ?? '',
          authorZendtag: event.data['author_zendtag'] as String? ?? '',
          body: event.data['body'] as String? ?? '',
        );
        notifyListeners();
      case SseEventType.dropConfirmed:
        // A Drop transfer was confirmed.
        // 1. Update balance immediately from the SSE payload so the UI reacts
        //    in real time without waiting for fetchBalance() to complete.
        //    We use the server-computed new_balance for the sender (authoritative),
        //    and add the amount for the receiver (server doesn't know their balance).
        //    Critically: do NOT call fetchBalance() immediately — Solana hasn't
        //    confirmed yet and the chain query will return the pre-transfer balance,
        //    causing the UI to dial back down.
        final dropAmountStr = event.data['amount_usdc'] as String?;
        final dropRole = event.data['role'] as String?;
        final dropAmount = double.tryParse(dropAmountStr ?? '') ?? 0.0;
        final newBalanceStr = event.data['new_balance_usdc'] as String?;
        final serverNewBalance = newBalanceStr != null ? double.tryParse(newBalanceStr) : null;

        if (dropAmount > 0) {
          if (dropRole == 'sender' && serverNewBalance != null) {
            // Sender: use the server-computed balance (it subtracted the amount)
            balance = serverNewBalance;
            spendableBalance = serverNewBalance;
          } else if (dropRole == 'receiver') {
            // Receiver: add incoming amount to cached balance immediately
            balance = (balance + dropAmount).clamp(0.0, double.maxFinite);
            spendableBalance = (spendableBalance + dropAmount).clamp(0.0, double.maxFinite);
          }
          notifyListeners();
        }
        // 2. Broadcast to Drop UI for haptics/animations/overlay immediately
        _dropConfirmedController.add(event.data);
        // 3. Schedule authoritative re-fetch after 4s — by then Solana should have
        //    confirmed and the chain balance will match what we showed optimistically.
        Future.delayed(const Duration(seconds: 4), () {
          if (isAuthenticated) {
            unawaited(fetchBalance());
            unawaited(fetchHistory());
          }
        });
      default:
        break;
    }
  }

  /// Immediately patches a pending [TransferHistoryEntry] in [recentTransactions]
  /// to 'confirmed' when a `transfer_update` SSE event arrives.
  ///
  /// The SSE payload carries `transfer_id` — we use it to find the matching
  /// entry and flip its status without waiting for the full fetchHistory() round-
  /// trip. This means open receipt sheets see "Confirmed" the moment the on-chain
  /// reconciler fires, rather than ~30–45s later when the history refetch lands.
  void _patchTransferStatus(Map<String, dynamic> data) {
    final transferId = data['transfer_id'] as String?;
    if (transferId == null || transferId.isEmpty) return;

    final idx = recentTransactions.indexWhere(
      (tx) => tx.entry?.id == transferId,
    );
    if (idx == -1) return;

    final existing = recentTransactions[idx];
    if (existing.entry == null) return;
    // Only upgrade — never downgrade a confirmed entry back to pending.
    if (existing.entry!.status == 'confirmed') return;

    // Rebuild with updated status, keeping everything else identical.
    final updated = ZendTransaction(
      name: existing.name,
      note: existing.note,
      amount: existing.amount,
      time: existing.time,
      avatarLabel: existing.avatarLabel,
      amountColor: existing.amountColor,
      entry: TransferHistoryEntry(
        id: existing.entry!.id,
        senderZendtag: existing.entry!.senderZendtag,
        recipientZendtag: existing.entry!.recipientZendtag,
        amountUsdc: existing.entry!.amountUsdc,
        transactionSignature: existing.entry!.transactionSignature,
        note: existing.entry!.note,
        status: 'confirmed',
        createdAt: existing.entry!.createdAt,
        senderAvatarUrl: existing.entry!.senderAvatarUrl,
        recipientAvatarUrl: existing.entry!.recipientAvatarUrl,
        senderDisplayName: existing.entry!.senderDisplayName,
        recipientDisplayName: existing.entry!.recipientDisplayName,
        emailRecipientHint: existing.entry!.emailRecipientHint,
      ),
      bankOrder: existing.bankOrder,
      avatarUrl: existing.avatarUrl,
      countryCode: existing.countryCode,
      isPending: false,
      createdAt: existing.createdAt,
    );

    recentTransactions[idx] = updated;
    notifyListeners();
  }

  void _startFallbackPolling() {
    if (!isAuthenticated) return;
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      if (isAuthenticated && !_sseConnected) {
        unawaited(fetchBalance());
        unawaited(fetchHistory());
      }
    });
  }

  /// Stop all real-time updates (SSE + polling).
  void stopRealTimeUpdates() {
    _stopAll();
    sseService.stop();
  }

  void _stopAll() {
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _sseConnected = false;
  }

  // Keep these for backward compatibility — they now delegate to startRealTimeUpdates
  void startPolling() => startRealTimeUpdates();
  void stopPolling() => stopRealTimeUpdates();

  /// Handle a drop confirmed event that arrived via push notification
  /// (when the app was backgrounded and SSE was not connected).
  /// Triggers the same UI reactions as the SSE path.
  void handleDropConfirmedFromPush(Map<String, dynamic> data) {
    _onSseEvent(SseEvent(type: SseEventType.dropConfirmed, data: data));
  }
  /// Use this when coming back from a long background period where
  /// the SSE connection is known to be stale (e.g. > 5 minutes paused).
  void forceRestartRealTimeUpdates() {
    _stopAll();
    _sseConnected = false;
    sseService.stop();
    sseService.start();
    _sseSubscription = sseService.events.listen(
      _onSseEvent,
      onError: (_) {
        _sseConnected = false;
        _startFallbackPolling();
      },
      onDone: () {
        _sseConnected = false;
        if (isAuthenticated) _startFallbackPolling();
      },
    );
    _startFallbackPolling();
  }

  @override
  void dispose() {
    _stopAll();
    _dropConfirmedController.close();
    sseService.dispose();
    super.dispose();
  }

  bool isAuthenticated = false;
  String? currentUserId;
  String? currentZendtag;
  String? currentDisplayName;
  String? currentAvatarUrl;

  String? walletAddress;
  bool hasWallet = false;
  bool hasPinSetup = false;

  double balance = 0.0;
  double spendableBalance = 0.0;
  double monthlyYield = 0.0;
  bool balanceLoading = false;
  String? lastBalanceError;

  // ── Email intents ──
  List<EmailIntent> _pendingEmailIntents = [];
  List<EmailIntent> get pendingEmailIntents => List.unmodifiable(_pendingEmailIntents);

  // ── Transfer history ──
  List<ZendTransaction> recentTransactions = [];
  List<RecentContact> recentContacts = [];
  bool historyLoading = false;
  String? lastHistoryError;

  // ── Threaded activity (Phase 2 Activity Relationship Graph) ──
  // A parallel, additive state slice consumed only by ThreadedActivityScreen.
  // Deliberately independent of recentTransactions/fetchHistory() above —
  // see design.md's "parallel path, not extend/wrap fetchHistory()" decision
  // (Req 22.4 backward compatibility).
  List<ActivityEdge> threadedActivityEdges = [];
  bool threadedActivityLoading = false;
  String? lastThreadedActivityError;
  String? _threadedActivityNextCursor;

  /// True when all pages have been loaded locally — i.e. there is no
  /// outstanding next cursor. When false, per-counterparty edge counts
  /// derived from the local list are lower bounds, not exact totals.
  bool get threadedActivityHasMore => _threadedActivityNextCursor != null;

  // ── Unread/badge counts ────────────────────────────────────────────────────
  // Lightweight counters for UI badges — not persisted, reset when the user
  // navigates to the relevant screen.

  /// Number of new activity events (transfers, reactions, comments) since the
  /// user last viewed the Activity tab. Incremented by SSE events, cleared
  /// when the Activity tab is opened.
  int activityUnreadCount = 0;

  /// Pool IDs that have received at least one new message since the user last
  /// opened that pool's mission room.
  final Set<String> poolsWithNewMessages = {};

  void markActivityRead() {
    if (activityUnreadCount != 0) {
      activityUnreadCount = 0;
      notifyListeners();
    }
  }

  void markPoolRead(String poolId) {
    if (poolsWithNewMessages.remove(poolId)) {
      notifyListeners();
    }
  }

  bool get hasAnyPoolNewMessage => poolsWithNewMessages.isNotEmpty;

  /// Triggers a rebuild for all listeners. Used externally (e.g. main.dart)
  /// when state is mutated directly before the auth flow completes.
  void triggerRebuild() => notifyListeners();

  /// Optional callback fired the moment the user successfully authenticates
  /// (or re-authenticates). Used by app.dart to dispatch any pending
  /// notification destination that was parked before authentication completed —
  /// covers the device-lock → notification tap → app unlock path where
  /// _onLockStateChanged never fires because isLocked was never set.
  VoidCallback? onAuthenticated;

  // Set true the first time fetchThreadedActivity() runs (i.e. once the
  // Activity tab has been opened this session). Used to gate SSE-driven
  // refreshes of the threaded feed so we don't fetch it before it's ever
  // been needed — see _onSseEvent()'s transferUpdate/transferFailed/
  // refreshRequired cases.
  bool _threadedActivityEverLoaded = false;

  /// Fetches the first page of the visibility-filtered Activity_Edge feed.
  /// Called by `ThreadedActivityScreen.initState()`, mirroring exactly how
  /// `ActivityScreen.initState()` calls `fetchHistory()`.
  Future<void> fetchThreadedActivity() async {
    _threadedActivityEverLoaded = true;
    threadedActivityLoading = true;
    lastThreadedActivityError = null;
    notifyListeners();
    try {
      final response = await activityDataService.getActivityEdges(limit: 50);
      threadedActivityEdges = response.edges;
      _threadedActivityNextCursor = response.nextCursor;
    } catch (e) {
      lastThreadedActivityError = e.toString();
    } finally {
      threadedActivityLoading = false;
      notifyListeners();
    }
  }

  /// Loads and appends the next page, if any. No-op if there is no further
  /// page or a fetch is already in flight.
  Future<void> fetchMoreThreadedActivity() async {
    if (threadedActivityLoading || _threadedActivityNextCursor == null) return;
    threadedActivityLoading = true;
    notifyListeners();
    try {
      final response = await activityDataService.getActivityEdges(
        cursor: _threadedActivityNextCursor,
        limit: 50,
      );
      threadedActivityEdges = [...threadedActivityEdges, ...response.edges];
      _threadedActivityNextCursor = response.nextCursor;
    } catch (e) {
      lastThreadedActivityError = e.toString();
    } finally {
      threadedActivityLoading = false;
      notifyListeners();
    }
  }

  Locale _locale = const Locale('en');
  late String greetingPrefix = _greetingForLocale(_locale);

  String username = 'blessed';
  bool balanceHidden = false;
  bool isDarkMode = false;
  /// Whether this user's mutual connections are notified when they make
  /// an activity public. Default true — the social signal is intentional.
  bool notifyMutualsOnShare = true;
  /// True once the user has explicitly toggled dark/light mode.
  /// False = follow system theme.
  bool hasExplicitTheme = false;
  String selectedCurrency = 'USD';

  // Waitlist hold-over fields — set by the OTP verify response when
  // the visitor's email matches a Zend! consumer-waitlist row, then
  // consumed by the NameScreen and UsernameScreen so the onboarding
  // flow can greet returning visitors and prefill what they already
  // told us. Cleared on `setAuthenticated` and `signOut` so they
  // don't leak across sessions.
  bool pendingWaitlistMatch = false;
  String? pendingReservedZendtag;
  String? pendingWaitlistFullName;

  bool isLoading = false;
  String loadingMessage = 'Loading';

  final List<PaymentRequest> paymentRequests = [];
  final List<Pool> pools = [];
  bool poolsLoading = false;
  String? lastPoolsError;

  /// Pending payment request notification from SSE — shown as in-app banner.
  PaymentRequestNotification? pendingPaymentRequest;

  /// Pending Activity_Edge reaction notification from SSE — shown as an
  /// in-app banner (Threaded_Activity_View listens for this).
  ActivityReactionNotification? pendingActivityReaction;

  /// Pending Activity_Edge comment notification from SSE — shown as an
  /// in-app banner.
  ActivityCommentNotification? pendingActivityComment;

  // ── Payment requests (activity feed) ──
  List<PaymentRequestItem> outboundPaymentRequests = [];
  List<PaymentRequestItem> inboundPaymentRequests = [];

  // ── Savings ──
  double savingsApy = 0.0;
  double savingsBalance = 0.0;
  bool savingsLoading = false;

  void setLocale(Locale locale) {
    // Guard: only notify if the locale actually changed to avoid rebuild loops.
    // localeResolutionCallback fires on every MaterialApp build, so without
    // this guard it creates a cycle: setLocale → notifyListeners → setState →
    // MaterialApp rebuild → localeResolutionCallback → setLocale → ...
    if (_locale.languageCode == locale.languageCode &&
        _locale.countryCode == locale.countryCode) {
      return;
    }
    _locale = locale;
    greetingPrefix = _greetingForLocale(locale);
    notifyListeners();
  }

  void refreshGreeting() {
    greetingPrefix = _greetingForLocale(_locale);
    notifyListeners();
  }

  Future<void> hydrateRecentContacts() async {
    final cached = await recentContactsStore.load();
    if (cached.isEmpty) return;
    recentContacts = cached;
    notifyListeners();
  }

  Future<void> restoreUserIdentity() async {
    try {
      final profile = await authService.tryRestoreUserIdentity();
      if (profile != null) {
        setAuthenticated(
          userId: profile.userId,
          zendtag: profile.zendtag,
          displayName: profile.displayName,
          walletAddr: profile.walletAddress,
          avatarUrl: profile.avatarUrl,
        );
        return;
      }

      final apiProfile = await walletService.apiClient.getCurrentUser();
      await authService.saveUserIdentity(apiProfile);
      setAuthenticated(
        userId: apiProfile.userId,
        zendtag: apiProfile.zendtag,
        displayName: apiProfile.displayName,
        walletAddr: apiProfile.walletAddress,
        avatarUrl: apiProfile.avatarUrl,
      );
    } catch (e) {
      lastHistoryError = 'Failed to restore user identity: $e';
    }
  }


  void toggleBalanceHidden() {
    balanceHidden = !balanceHidden;
    notifyListeners();
  }

  void toggleDarkMode() {
    hasExplicitTheme = true;
    isDarkMode = !isDarkMode;
    notifyListeners();
  }

  /// Loads persisted user preferences. Call once after model initialisation.
  Future<void> loadPersistedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    notifyMutualsOnShare = prefs.getBool('notify_mutuals_on_share') ?? true;
    notifyListeners();
  }

  /// Toggles whether mutuals are notified when the user makes an activity public.
  /// Persists locally AND syncs the preference to the server so the backend
  /// respects it server-side (the server also checks this flag before sending).
  Future<void> toggleNotifyMutualsOnShare() async {
    notifyMutualsOnShare = !notifyMutualsOnShare;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify_mutuals_on_share', notifyMutualsOnShare);
    // Sync to server — fire-and-forget, non-fatal
    walletService.apiClient
        .updateVisibilitySettings(notifyMutualsOnShare: notifyMutualsOnShare)
        .ignore();
  }

  void setUsername(String value) {
    username = value.trim().isEmpty ? 'blessed' : value.trim().toLowerCase();
    notifyListeners();
  }

  /// Capture waitlist hold-over fields from the OTP verify response.
  /// Called by the OTP screen on the new-user path. The values are
  /// then read by NameScreen (full name prefill + welcome line) and
  /// UsernameScreen (zendtag prefill + "RESERVED FOR YOU" eyebrow).
  void setPendingWaitlistInfo({
    required bool matched,
    String? reservedZendtag,
    String? fullName,
  }) {
    pendingWaitlistMatch = matched;
    pendingReservedZendtag = reservedZendtag;
    pendingWaitlistFullName = fullName;
    notifyListeners();
  }

  /// Drop the waitlist hold-over so the next visitor on a shared device
  /// (or a re-used logout/login session) doesn't see stale prefill.
  void clearPendingWaitlistInfo() {
    pendingWaitlistMatch = false;
    pendingReservedZendtag = null;
    pendingWaitlistFullName = null;
    notifyListeners();
  }

  void setDisplayName(String value) {
    final trimmed = value.trim();
    currentDisplayName = trimmed.isEmpty ? null : trimmed;
    notifyListeners();
  }

  /// Update the current user's avatar URL and notify listeners.
  void setAvatarUrl(String? url) {
    currentAvatarUrl = url;
    notifyListeners();
    // Persist so it survives app restarts
    unawaited(authService.updateAvatarUrl(url));
  }

  void setCurrency(String value) {
    selectedCurrency = value;
    notifyListeners();
  }

  void setMonthlyYield(double yield) {
    monthlyYield = (yield).clamp(0.0, 100.0);
    notifyListeners();
  }

  void startLoading(String message) {
    isLoading = true;
    loadingMessage = message;
    notifyListeners();
  }

  void stopLoading() {
    isLoading = false;
    loadingMessage = 'Loading';
    notifyListeners();
  }

  Future<void> fetchBalance() async {
    // Only notify for the loading state if we have no data yet (first load).
    // Background refreshes update silently to avoid mid-transition rebuilds.
    final firstLoad = balance == 0.0 && !balanceLoading;
    balanceLoading = true;
    lastBalanceError = null;
    if (firstLoad) notifyListeners();
    try {
      final response = await walletService.apiClient.getBalance();
      balance = double.tryParse(response.usdcBalance) ?? 0.0;
      spendableBalance = double.tryParse(response.spendableBalance) ?? balance;
      lastBalanceError = null;
    } catch (e) {
      lastBalanceError = e.toString();
    } finally {
      balanceLoading = false;
      notifyListeners();
    }
  }

  /// Fetches pending email intents from the server and updates [pendingEmailIntents].
  /// No-op if [_emailIntentService] is not injected.
  Future<void> fetchEmailIntents() async {
    final intents = await _emailIntentService?.listIntents();
    if (intents != null) {
      _pendingEmailIntents = intents;
      notifyListeners();
    }
  }

  /// Fetches outbound payment requests (sent by this user) for the activity feed.
  Future<void> fetchOutboundPaymentRequests() async {
    try {
      final data = await walletService.apiClient.getPaymentRequests();
      final list = (data['requests'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .where((r) => r['amount_usdc'] != null)
          .map(PaymentRequestItem.fromOutboundJson)
          .toList();
      outboundPaymentRequests = list;
      notifyListeners();
    } catch (_) {
      // Non-fatal — activity feed still shows transactions
    }
  }

  /// Fetches inbound payment requests (sent to this user) for the activity feed.
  Future<void> fetchInboundPaymentRequests() async {
    try {
      final data = await walletService.apiClient.getReceivedPaymentRequests();
      final list = (data['requests'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .where((r) => r['amount_usdc'] != null)
          .map(PaymentRequestItem.fromInboundJson)
          .toList();
      inboundPaymentRequests = list;
      notifyListeners();
    } catch (_) {
      // Non-fatal
    }
  }

  /// Cancels a pending email intent by [id].
  /// Removes it from [_pendingEmailIntents] on success and notifies listeners.
  /// No-op if [_emailIntentService] is not injected.
  Future<void> cancelEmailIntent(String id) async {
    await _emailIntentService?.cancelIntent(id);
    _pendingEmailIntents = _pendingEmailIntents.where((i) => i.id != id).toList();
    notifyListeners();
  }

  Future<void> fetchHistory() async {
    final firstLoad = recentTransactions.isEmpty && !historyLoading;
    historyLoading = true;
    lastHistoryError = null;
    if (firstLoad) notifyListeners();
    try {
      // Fetch zend-to-zend transfers, bank sends, payins, and email intents in parallel
      final results = await Future.wait([
        transferService.getHistory(),
        walletService.apiClient.getBankSendOrders().catchError((_) => <dynamic>[]),
        walletService.apiClient.getPayinOrders().catchError((_) => <dynamic>[]),
        walletService.apiClient.getCryptoDepositHistory().catchError((_) => <dynamic>[]),
      ]);
      // Fetch email intents in parallel but separately (returns void)
      unawaited(fetchEmailIntents());
      // Fetch payment requests for activity feed in parallel
      unawaited(fetchOutboundPaymentRequests());
      unawaited(fetchInboundPaymentRequests());

      final entries = results[0] as List<TransferHistoryEntry>;
      final bankOrders = results[1].cast<Map<String, dynamic>>();
      final payinOrders = results[2].cast<Map<String, dynamic>>();
      final cryptoDeposits = results[3].cast<Map<String, dynamic>>();
      final contacts = _buildRecentContactsFromHistory(entries);

      // Build rows from zend-to-zend transfers
      final transferRows = entries.map((entry) {
        final isSent = entry.senderZendtag == currentZendtag;
        final counterparty = isSent ? entry.recipientZendtag : entry.senderZendtag;
        final sign = isSent ? '-' : '+';
        final amt = entry.amountUsdc;
        // Avatar URL comes directly from the history entry (backend JOIN)
        final avatarUrl = isSent ? entry.recipientAvatarUrl : entry.senderAvatarUrl;

        // For email-intent claims on the sender side, prefer the masked email hint
        // (e.g. "te***@gmail.com") over the recipient's zendtag — it's more
        // meaningful because the sender never knew the recipient's zendtag.
        final displayName = (isSent && entry.emailRecipientHint != null)
            ? entry.emailRecipientHint!
            : '@$counterparty';

        return ZendTransaction(
          name: displayName,
          note: entry.note ?? '',
          amount: '$sign\$$amt',
          time: _formatTimestamp(entry.createdAt),
          avatarLabel: counterparty.isNotEmpty ? counterparty[0].toUpperCase() : '?',
          amountColor: isSent ? null : ZendColors.positive,
          entry: entry,
          avatarUrl: avatarUrl,
          createdAt: entry.createdAt,
        );
      }).toList();
      final bankRows = bankOrders.map((order) {
        final amountUsdc = (order['amount_usdc'] as num?)?.toDouble() ?? 0.0;
        final fiatAmount = (order['fiat_amount'] as num?)?.toDouble();
        final fiatCurrency = order['fiat_currency'] as String? ?? '';
        final bankName = order['bank_name'] as String? ?? 'Bank';
        final accountName = order['account_name'] as String?;
        final accountMasked = order['account_number_masked'] as String?;
        final status = order['status'] as String? ?? '';
        final createdAtStr = order['created_at'] as String? ?? '';
        final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();

        // Title: account holder name if available, otherwise bank name
        final title = (accountName != null && accountName.isNotEmpty)
            ? _toTitleCase(accountName)
            : bankName;

        // Note: fiat amount + bank name + masked account
        final fiatPart = fiatAmount != null && fiatAmount > 0 && fiatCurrency.isNotEmpty
            ? _formatFiatDisplay(fiatAmount, fiatCurrency)
            : null;
        final bankPart = bankName.isNotEmpty ? bankName : null;
        final accountPart = accountMasked != null && accountMasked.isNotEmpty
            ? accountMasked
            : null;
        final noteParts = [fiatPart, bankPart, accountPart].whereType<String>().toList();
        final note = noteParts.isNotEmpty ? noteParts.join(' · ') : '→ $bankName';

        final amtStr = amountUsdc == amountUsdc.roundToDouble()
            ? '-\$${amountUsdc.toStringAsFixed(0)}'
            : '-\$${amountUsdc.toStringAsFixed(2)}';

        final timeStr = (status == 'pending_payment' || status == 'processing')
            ? 'Processing'
            : status == 'paid'
                ? 'Sent'
                : status == 'completed'
                    ? 'Delivered'
                    : status == 'failed'
                        ? 'Failed'
                        : _formatTimestamp(createdAt);

        return ZendTransaction(
          name: title,
          note: note,
          amount: amtStr,
          time: timeStr,
          avatarLabel: 'B',
          amountColor: null,
          entry: null,
          bankOrder: order,
          countryCode: _countryCodeFromCurrency(fiatCurrency),
          createdAt: createdAt,
        );
      }).toList();

      // Build rows from payin orders — only show completed ones (USDC confirmed in wallet)
      final payinRows = payinOrders
          .where((order) => (order['status'] as String? ?? '') == 'completed')
          .map((order) {
        final amountUsdc = (order['amount_usdc'] as num?)?.toDouble() ?? 0.0;
        final fiatAmount = (order['fiat_amount'] as num?)?.toDouble();
        final createdAtStr = order['created_at'] as String? ?? '';
        final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();

        final fiatPart = fiatAmount != null && fiatAmount > 0
            ? _formatFiatDisplay(fiatAmount, 'NGN')
            : null;
        final note = fiatPart != null ? '$fiatPart received' : 'NGN payin';

        final amtStr = amountUsdc == amountUsdc.roundToDouble()
            ? '+${amountUsdc.toStringAsFixed(0)}'
            : '+${amountUsdc.toStringAsFixed(2)}';

        return ZendTransaction(
          name: 'NGN Payin',
          note: note,
          amount: amtStr,
          time: _formatTimestamp(createdAt),
          avatarLabel: '₦',
          amountColor: ZendColors.positive,
          entry: null,
          bankOrder: order,
          createdAt: createdAt,
        );
      }).toList();

      // Build rows from crypto deposit events (Dextopus bridge deposits)
      final cryptoDepositRows = cryptoDeposits.map((order) {
        final amountUsdc = (order['amount_usdc'] as num?)?.toDouble() ?? 0.0;
        final originSymbol = order['origin_symbol'] as String? ?? 'Crypto';
        final originBlockchain = order['origin_blockchain'] as String? ?? '';
        final completedAtStr = order['completed_at'] as String?;
        final createdAtStr = order['created_at'] as String? ?? '';
        final createdAt = DateTime.tryParse(completedAtStr ?? createdAtStr) ?? DateTime.now();

        final amtStr = amountUsdc == amountUsdc.roundToDouble()
            ? '+\$${amountUsdc.toStringAsFixed(0)}'
            : '+\$${amountUsdc.toStringAsFixed(2)}';

        final note = originBlockchain.isNotEmpty
            ? '$originSymbol via $originBlockchain'
            : originSymbol;

        return ZendTransaction(
          name: 'Crypto Deposit',
          note: note,
          amount: amtStr,
          time: _formatTimestamp(createdAt),
          avatarLabel: '₿',
          amountColor: ZendColors.positive,
          entry: null,
          bankOrder: order,
          createdAt: createdAt,
        );
      }).toList();

      // Merge and sort newest first
      final all = [...transferRows, ...bankRows, ...payinRows, ...cryptoDepositRows]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      recentTransactions = all;
      recentContacts = contacts;
      await recentContactsStore.save(recentContacts).catchError((_) {});
      lastHistoryError = null;
    } catch (e) {
      lastHistoryError = e.toString();
    } finally {
      historyLoading = false;
      notifyListeners();
    }
  }

  /// Maps fiat currency code to ISO country code for flag display.
  static String? _countryCodeFromCurrency(String currency) {
    return switch (currency.toUpperCase()) {
      'NGN' => 'ng',
      'USD' => 'us',
      'GBP' => 'gb',
      'EUR' => 'eu',
      _ => null,
    };
  }

  String _toTitleCase(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  String _formatFiatDisplay(double value, String currency) {
    if (currency == 'NGN') {
      final rounded = value.round();
      final text = rounded.toString();
      final buf = StringBuffer();
      for (var i = 0; i < text.length; i++) {
        final fromEnd = text.length - i;
        buf.write(text[i]);
        if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
      }
      return '₦${buf.toString()}';
    }
    final symbol = switch (currency) {
      'GBP' => '£',
      'EUR' => '€',
      _ => '\$',
    };
    return '$symbol${value.toStringAsFixed(2)}';
  }

  void setAuthenticated({
    required String userId,
    required String zendtag,
    required String displayName,
    String? walletAddr,
    String? avatarUrl,
  }) {
    // If a different user is authenticating (account switch), zero out all
    // stale per-user state so the previous user's balance/history never
    // bleeds into the new session. On the same-user re-auth (app resume)
    // this is a no-op since the userId matches.
    if (isAuthenticated && currentUserId != null && currentUserId != userId) {
      // CRITICAL: clear the session keypair cache so the previous user's
      // decrypted keypair cannot be used to sign transactions for the new user.
      WalletSessionCache.instance.clear();
      balance = 0.0;
      spendableBalance = 0.0;
      monthlyYield = 0.0;
      recentTransactions = [];
      recentContacts = [];
      walletAddress = null;
      hasWallet = false;
      hasPinSetup = false;
      pools.clear();
      savingsBalance = 0.0;
      _pendingEmailIntents = [];
      outboundPaymentRequests = [];
      inboundPaymentRequests = [];
      pendingPaymentRequest = null;
      lastBalanceError = null;
      lastHistoryError = null;
      lastPoolsError = null;
    }

    isAuthenticated = true;
    currentUserId = userId;
    currentZendtag = zendtag;
    currentDisplayName = displayName;
    if (walletAddr != null) walletAddress = walletAddr;
    if (avatarUrl != null) currentAvatarUrl = avatarUrl;
    username = zendtag;
    // Onboarding done — drop any waitlist hold-over so it can't leak
    // into a future session if this device is later signed out and
    // signed back in by a different visitor.
    pendingWaitlistMatch = false;
    pendingReservedZendtag = null;
    pendingWaitlistFullName = null;
    notifyListeners();
    startPolling();
    // Start the inactivity lock timer now that the user is authenticated
    appLockService.startTimer();
    // Initialize push notifications now that the user is authenticated
    // and we have a valid session token to register the FCM token with.
    // Also wire pool message badge tracking.
    PushNotificationService.onPoolMessageReceived = (poolId) {
      poolsWithNewMessages.add(poolId);
      notifyListeners();
    };
    unawaited(pushNotificationService.initialize());
    // Fire the onAuthenticated hook so app.dart can dispatch any pending
    // notification destination that was parked before authentication.
    onAuthenticated?.call();
    // Load pools from backend
    unawaited(fetchPools());
    // Load savings snapshot
    unawaited(fetchSavingsSnapshot());
    // Restore Drop discoverability preference (non-blocking)
    unawaited(dropDiscoverabilityService.init());
  }

  Future<void> recordTransfer({
    required String recipientZendtag,
    required String recipientDisplayName,
    required double amount,
    String? note,
  }) async {
    // Do NOT optimistically deduct from balance here — the server is the
    // source of truth. We call fetchBalance() right after submission, and
    // an incorrect local deduction would either double-subtract (if the
    // server read comes back pre-confirmation) or show the wrong number
    // on multi-wallet devices. Let the server refresh do all balance updates.
    recentTransactions.insert(
      0,
      ZendTransaction(
        name: '@$recipientZendtag',
        note: note ?? 'Sent from ZendApp',
        amount: '-\$${amount.toStringAsFixed(2)}',
        time: 'Just now',
        avatarLabel: recipientDisplayName.isNotEmpty
            ? recipientDisplayName[0].toUpperCase()
            : '?',
        isPending: true,
      ),
    );

    final contactName = recipientDisplayName.isNotEmpty
        ? recipientDisplayName
        : ''; // empty = no display name, tile shows only @tag
    final contactAvatar = contactName.isNotEmpty
        ? contactName[0].toUpperCase()
        : recipientZendtag.isNotEmpty
            ? recipientZendtag[0].toUpperCase()
            : '?';

    recentContacts = _mergeRecentContacts(
      RecentContact(
        name: contactName,
        tag: recipientZendtag,
        avatarLabel: contactAvatar,
      ),
    );

    await recentContactsStore.save(recentContacts).catchError((_) {
      // Best-effort, don't fail the transfer if contact caching fails
    });
    notifyListeners();
  }

  void resetState() {
    stopPolling(); // Stop live updates on logout
    appLockService.reset(); // Stop inactivity timer and clear lock state
    // CRITICAL: zero and clear the in-memory keypair so it cannot be reused
    // by a subsequent user logging in on the same device.
    WalletSessionCache.instance.clear();
    isAuthenticated = false;
    currentUserId = null;
    currentZendtag = null;
    currentDisplayName = null;
    currentAvatarUrl = null;
    walletAddress = null;
    hasWallet = false;
    hasPinSetup = false;
    balance = 0.0;
    spendableBalance = 0.0;
    monthlyYield = 0.0;
    balanceLoading = false;
    lastBalanceError = null;
    recentTransactions = [];
    recentContacts = [];
    historyLoading = false;
    lastHistoryError = null;
    username = 'blessed';
    pendingWaitlistMatch = false;
    pendingReservedZendtag = null;
    pendingWaitlistFullName = null;
    balanceHidden = false;
    isDarkMode = false;
    hasExplicitTheme = false;
    selectedCurrency = 'USD';
    isLoading = false;
    loadingMessage = 'Loading';
    unawaited(recentContactsStore.clear());
    pools.clear();
    poolsLoading = false;
    lastPoolsError = null;
    savingsApy = 0.0;
    savingsBalance = 0.0;
    savingsLoading = false;
    pendingPaymentRequest = null;
    outboundPaymentRequests = [];
    inboundPaymentRequests = [];
    _pendingEmailIntents = [];
    notifyListeners();
  }

  void addPaymentRequest(PaymentRequest request) {
    paymentRequests.insert(0, request);
    notifyListeners();
  }

  void clearPendingActivityReaction() {
    pendingActivityReaction = null;
    notifyListeners();
  }

  void clearPendingActivityComment() {
    pendingActivityComment = null;
    notifyListeners();
  }

  void clearPendingPaymentRequest() {
    pendingPaymentRequest = null;
    notifyListeners();
  }

  Future<void> fetchSavingsSnapshot() async {
    // Silent background refresh — no loading spinner for home screen card.
    savingsLoading = true;
    try {
      final results = await Future.wait([
        pocketService.listPockets(),
        savingsService.getSavingsMetrics(),
      ]);
      final pockets = results[0] as List<SavingsPocket>;
      final metrics = results[1] as SavingsMetrics;
      savingsApy = metrics.apy;
      // Monthly yield as a percentage ≈ annual APY / 12.
      // This is displayed on the home screen as "X.X% earned this month".
      monthlyYield = (metrics.apy / 12.0).clamp(0.0, 100.0);
      // Sum all pocket balances + yields
      savingsBalance = pockets.fold(
        0.0,
        (sum, p) => sum + p.balanceUsd + p.pocketYieldUsd,
      );
    } catch (_) {
      // Non-fatal — failures must never crash the home screen
    } finally {
      savingsLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPools() async {
    final firstLoad = pools.isEmpty && !poolsLoading;
    poolsLoading = true;
    lastPoolsError = null;
    if (firstLoad) notifyListeners();
    try {
      final fetched = await walletService.apiClient.listPools();
      pools
        ..clear()
        ..addAll(fetched);
      lastPoolsError = null;
    } catch (e) {
      lastPoolsError = e.toString();
    } finally {
      poolsLoading = false;
      notifyListeners();
    }
  }

  void addPool(Pool pool) {
    pools.insert(0, pool);
    notifyListeners();
  }

  double get totalPoolsGathered => pools
      .where((p) => p.status == PoolStatus.active)
      .fold(0.0, (sum, p) => sum + p.gathered);

  List<PoolParticipant> get recentPoolParticipants {
    final active = pools.where((p) => p.status == PoolStatus.active);
    return active.isEmpty ? [] : active.first.participants;
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  List<RecentContact> _buildRecentContactsFromHistory(
    List<TransferHistoryEntry> entries,
  ) {
    final seen = <String>{};
    final contacts = <RecentContact>[];

    for (final entry in entries) {
      final isSent = entry.senderZendtag == currentZendtag;
      final counterparty = isSent ? entry.recipientZendtag : entry.senderZendtag;
      final counterpartyAvatarUrl = isSent ? entry.recipientAvatarUrl : entry.senderAvatarUrl;
      // Display name comes directly from the history entry now
      final counterpartyDisplayName = isSent
          ? entry.recipientDisplayName
          : entry.senderDisplayName;
      final tag = counterparty.trim();
      if (tag.isEmpty || seen.contains(tag)) continue;
      seen.add(tag);

      // Use the display name from the history entry if available,
      // otherwise fall back to any cached name we already have
      final cached = recentContacts.firstWhere(
        (c) => c.tag == tag,
        orElse: () => RecentContact(name: '', tag: tag, avatarLabel: ''),
      );
      final name = (counterpartyDisplayName != null && counterpartyDisplayName.trim().isNotEmpty)
          ? counterpartyDisplayName.trim()
          : (cached.name.isNotEmpty && cached.name != tag && cached.name != '@$tag')
              ? cached.name
              : '';

      final avatarLabel = name.isNotEmpty
          ? name[0].toUpperCase()
          : tag.isNotEmpty ? tag[0].toUpperCase() : '?';
      // Prefer the freshest avatar URL: history entry > cached contact
      final avatarUrl = counterpartyAvatarUrl ?? cached.avatarUrl;
      contacts.add(
        RecentContact(
          name: name,
          tag: tag,
          avatarLabel: avatarLabel,
          avatarUrl: avatarUrl,
        ),
      );
    }

    return contacts.take(15).toList();
  }

  List<RecentContact> _mergeRecentContacts(RecentContact contact) {
    final remaining = recentContacts.where((c) => c.tag != contact.tag);
    return [contact, ...remaining].take(15).toList();
  }
}

class ZendScope extends InheritedNotifier<ZendAppModel> {
  const ZendScope({
    super.key,
    required ZendAppModel notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ZendAppModel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ZendScope>();
    assert(scope != null, 'ZendScope not found in widget tree');
    return scope!.notifier!;
  }
}
