import 'dart:math';

import 'package:flutter/material.dart';

import '../design/zend_tokens.dart';
import '../features/pools/pool.dart';
import '../features/request/payment_request.dart';
import '../services/auth_service.dart';
import '../services/wallet_service.dart';
import '../services/zendtag_service.dart';
import '../services/transfer_service.dart';
import '../services/fx_service.dart';

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
    this.amountColor = ZendColors.textPrimary,
  });

  final String name;
  final String note;
  final String amount;
  final String time;
  final String avatarLabel;
  final Color amountColor;
}

class ZendAppModel extends ChangeNotifier {
  ZendAppModel({
    required this.authService,
    required this.walletService,
    required this.zendtagService,
    required this.transferService,
    required this.fxService,
  });

  // ── Injected services ──
  final AuthService authService;
  final WalletService walletService;
  final ZendtagService zendtagService;
  final TransferService transferService;
  final FxService fxService;

  // ── Auth state ──
  bool isAuthenticated = false;
  String? currentUserId;
  String? currentZendtag;
  String? currentDisplayName;

  // ── Wallet state ──
  String? walletAddress;
  bool hasWallet = false;
  bool hasPinSetup = false;

  // ── Balance (USDC only — SOL never displayed) ──
  double balance = 0.0;
  bool balanceLoading = false;
  String? lastBalanceError;

  // ── Transfer history ──
  List<ZendTransaction> recentTransactions = [];
  bool historyLoading = false;
  String? lastHistoryError;

  // ── Retained local-only state ──
  Locale _locale = const Locale('en');
  late String greetingPrefix = _greetingForLocale(_locale);

  String username = 'blessed';
  bool balanceHidden = false;
  String selectedCurrency = 'USD';

  bool isLoading = false;
  String loadingMessage = 'Loading';

  // ── Pool & payment request state (separate feature, retained) ──
  final List<PaymentRequest> paymentRequests = [];
  final List<Pool> pools = [];

  // ── Locale / greeting methods ──

  void setLocale(Locale locale) {
    _locale = locale;
    greetingPrefix = _greetingForLocale(locale);
    notifyListeners();
  }

  void refreshGreeting() {
    greetingPrefix = _greetingForLocale(_locale);
    notifyListeners();
  }

  // ── UI toggle methods ──

  void toggleBalanceHidden() {
    balanceHidden = !balanceHidden;
    notifyListeners();
  }

  void setUsername(String value) {
    username = value.trim().isEmpty ? 'blessed' : value.trim().toLowerCase();
    notifyListeners();
  }

  void setCurrency(String value) {
    selectedCurrency = value;
    notifyListeners();
  }

  // ── Loading overlay ──

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

  // ── Service-delegating methods ──

  /// Fetch USDC balance from the backend and update local state.
  Future<void> fetchBalance() async {
    balanceLoading = true;
    lastBalanceError = null;
    notifyListeners();
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

  /// Fetch transfer history from the backend and update local state.
  Future<void> fetchHistory() async {
    historyLoading = true;
    lastHistoryError = null;
    notifyListeners();
    try {
      final entries = await transferService.getHistory();
      recentTransactions = entries.map((entry) {
        final isSent = entry.senderZendtag == currentZendtag;
        final counterparty = isSent ? entry.recipientZendtag : entry.senderZendtag;
        final sign = isSent ? '-' : '+';
        return ZendTransaction(
          name: '@$counterparty',
          note: entry.note ?? '',
          amount: '$sign\$${entry.amountUsdc}',
          time: _formatTimestamp(entry.createdAt),
          avatarLabel: counterparty.isNotEmpty ? counterparty[0].toUpperCase() : '?',
          amountColor: isSent ? ZendColors.textPrimary : ZendColors.positive,
        );
      }).toList();
      lastHistoryError = null;
    } catch (e) {
      lastHistoryError = e.toString();
    } finally {
      historyLoading = false;
      notifyListeners();
    }
  }

  /// Mark the user as authenticated and populate identity fields.
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
    notifyListeners();
  }

  /// Record a successful transfer locally (deduct balance, add to history).
  void recordTransfer({
    required String recipientZendtag,
    required String recipientDisplayName,
    required double amount,
    String? note,
  }) {
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
    notifyListeners();
  }

  /// Reset all state to defaults (used on logout).
  void resetState() {
    isAuthenticated = false;
    currentUserId = null;
    currentZendtag = null;
    currentDisplayName = null;
    walletAddress = null;
    hasWallet = false;
    hasPinSetup = false;
    balance = 0.0;
    balanceLoading = false;
    lastBalanceError = null;
    recentTransactions = [];
    historyLoading = false;
    lastHistoryError = null;
    username = 'blessed';
    balanceHidden = false;
    selectedCurrency = 'USD';
    isLoading = false;
    loadingMessage = 'Loading';
    notifyListeners();
  }

  // ── Pool & payment request methods (retained) ──

  void addPaymentRequest(PaymentRequest request) {
    paymentRequests.insert(0, request);
    notifyListeners();
  }

  void addPool(Pool pool) {
    pools.insert(0, pool);
    notifyListeners();
  }

  /// Total gathered across all active pools.
  double get totalPoolsGathered => pools
      .where((p) => p.status == PoolStatus.active)
      .fold(0.0, (sum, p) => sum + p.gathered);

  /// Participants from the most recent active pool (for the card).
  List<PoolParticipant> get recentPoolParticipants {
    final active = pools.where((p) => p.status == PoolStatus.active);
    return active.isEmpty ? [] : active.first.participants;
  }

  // ── Private helpers ──

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

class ZendScope extends InheritedNotifier<ZendAppModel> {
  const ZendScope({super.key, required ZendAppModel notifier, required super.child}) : super(notifier: notifier);

  static ZendAppModel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ZendScope>();
    assert(scope != null, 'ZendScope not found in widget tree');
    return scope!.notifier!;
  }
}
