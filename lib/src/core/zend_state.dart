import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../design/zend_tokens.dart';
import '../features/pools/pool.dart';
import '../features/request/payment_request.dart';
import '../models/api_models.dart';
import '../models/recent_contact.dart';
import '../services/app_lock_service.dart';
import '../services/auth_service.dart';
import '../services/fx_service.dart';
import '../services/push_notification_service.dart';
import '../services/recent_contacts_store.dart';
import '../services/sound_service.dart';
import '../services/sse_service.dart';
import '../services/transfer_service.dart';
import '../services/pocket_service.dart';
import '../services/savings_service.dart';
import '../services/wallet_service.dart';
import '../services/zendtag_service.dart';
import '../models/payment_request_notification.dart';
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
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String name;
  final String note;
  final String amount;
  final String time;
  final String avatarLabel;
  final Color? amountColor;
  final DateTime createdAt;
  /// Full history entry — present for zend-to-zend transfers.
  final TransferHistoryEntry? entry;
  /// Raw bank send order map — present for bank send transactions.
  final Map<String, dynamic>? bankOrder;
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
  });

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

  // ── SSE subscription ──
  StreamSubscription<SseEvent>? _sseSubscription;

  // ── Fallback polling (used when SSE is unavailable) ──
  Timer? _pollingTimer;
  static const Duration _pollingInterval = Duration(seconds: 30);
  bool _sseConnected = false;

  /// Start real-time updates via SSE.
  /// Falls back to polling if SSE fails to connect within 5 seconds.
  void startRealTimeUpdates() {
    _stopAll();
    _sseConnected = false;

    // Start SSE
    sseService.start();
    _sseSubscription = sseService.events.listen(
      _onSseEvent,
      onError: (_) => _startFallbackPolling(),
      onDone: () {
        // SSE stream ended — start fallback polling until SSE reconnects
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
        // A transfer happened — refresh both balance and history
        unawaited(fetchBalance());
        unawaited(fetchHistory());
      case SseEventType.transferFailed:
        // A pending transfer failed — refresh history so status is accurate
        unawaited(fetchHistory());
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
      // poolMessage, poolReaction, poolReactionRemoved are handled
      // directly by the MissionRoom widget — no-op at the model level
      case SseEventType.poolMessage:
      case SseEventType.poolReaction:
      case SseEventType.poolReactionRemoved:
        break;
      case SseEventType.paymentRequest:
        // Show in-app banner for incoming payment requests
        final notification = PaymentRequestNotification.fromJson(event.data);
        pendingPaymentRequest = notification;
        notifyListeners();
      default:
        break;
    }
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

  @override
  void dispose() {
    _stopAll();
    sseService.dispose();
    super.dispose();
  }

  bool isAuthenticated = false;
  String? currentUserId;
  String? currentZendtag;
  String? currentDisplayName;

  String? walletAddress;
  bool hasWallet = false;
  bool hasPinSetup = false;

  double balance = 0.0;
  double monthlyYield = 0.0;
  bool balanceLoading = false;
  String? lastBalanceError;

  // ── Transfer history ──
  List<ZendTransaction> recentTransactions = [];
  List<RecentContact> recentContacts = [];
  bool historyLoading = false;
  String? lastHistoryError;

  Locale _locale = const Locale('en');
  late String greetingPrefix = _greetingForLocale(_locale);

  String username = 'blessed';
  bool balanceHidden = false;
  bool isDarkMode = false;
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

  // ── Savings ──
  double savingsApy = 0.0;
  double savingsBalance = 0.0;
  bool savingsLoading = false;

  void setLocale(Locale locale) {
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
      final usdcBalance = await walletService.getBalance();
      balance = double.tryParse(usdcBalance) ?? 0.0;
      lastBalanceError = null;
    } catch (e) {
      lastBalanceError = e.toString();
    } finally {
      balanceLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchHistory() async {
    // Only show loading state on first load — background refreshes are silent.
    final firstLoad = recentTransactions.isEmpty && !historyLoading;
    historyLoading = true;
    lastHistoryError = null;
    if (firstLoad) notifyListeners();
    try {
      // Fetch zend-to-zend transfers, bank sends, and payins in parallel
      final results = await Future.wait([
        transferService.getHistory(),
        walletService.apiClient.getBankSendOrders().catchError((_) => <dynamic>[]),
        walletService.apiClient.getPayinOrders().catchError((_) => <dynamic>[]),
        walletService.apiClient.getCryptoDepositHistory().catchError((_) => <dynamic>[]),
      ]);

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
        return ZendTransaction(
          name: '@$counterparty',
          note: entry.note ?? '',
          amount: '$sign\$$amt',
          time: _formatTimestamp(entry.createdAt),
          avatarLabel: counterparty.isNotEmpty ? counterparty[0].toUpperCase() : '?',
          amountColor: isSent ? null : ZendColors.positive,
          entry: entry,
          createdAt: entry.createdAt,
        );
      }).toList();

      // Build rows from bank send orders
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
  }) {
    isAuthenticated = true;
    currentUserId = userId;
    currentZendtag = zendtag;
    currentDisplayName = displayName;
    if (walletAddr != null) walletAddress = walletAddr;
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
    // and we have a valid session token to register the FCM token with
    unawaited(pushNotificationService.initialize());
    // Load pools from backend
    unawaited(fetchPools());
    // Load savings snapshot
    unawaited(fetchSavingsSnapshot());
  }

  Future<void> recordTransfer({
    required String recipientZendtag,
    required String recipientDisplayName,
    required double amount,
    String? note,
  }) async {
    balance = (balance - amount).clamp(0, double.infinity);
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
    isAuthenticated = false;
    currentUserId = null;
    currentZendtag = null;
    currentDisplayName = null;
    walletAddress = null;
    hasWallet = false;
    hasPinSetup = false;
    balance = 0.0;
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
    notifyListeners();
  }

  void addPaymentRequest(PaymentRequest request) {
    paymentRequests.insert(0, request);
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
      final tag = counterparty.trim();
      if (tag.isEmpty || seen.contains(tag)) continue;
      seen.add(tag);
      // Check if we already have a richer contact record cached (with display name)
      final cached = recentContacts.firstWhere(
        (c) => c.tag == tag,
        orElse: () => RecentContact(name: '', tag: tag, avatarLabel: ''),
      );
      // Use cached name if it's a real display name (not empty, not just the tag)
      final name = (cached.name.isNotEmpty && cached.name != tag && cached.name != '@$tag')
          ? cached.name
          : ''; // empty = no display name, tile will show only @tag
      final avatarLabel = name.isNotEmpty
          ? name[0].toUpperCase()
          : tag.isNotEmpty ? tag[0].toUpperCase() : '?';
      contacts.add(
        RecentContact(
          name: name,
          tag: tag,
          avatarLabel: avatarLabel,
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
