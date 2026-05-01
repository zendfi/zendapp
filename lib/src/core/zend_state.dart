import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../design/zend_tokens.dart';
import '../features/pools/pool.dart';
import '../features/request/payment_request.dart';
import '../models/api_models.dart';
import '../models/recent_contact.dart';
import '../services/auth_service.dart';
import '../services/fx_service.dart';
import '../services/recent_contacts_store.dart';
import '../services/transfer_service.dart';
import '../services/wallet_service.dart';
import '../services/zendtag_service.dart';

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
    required this.recentContactsStore,
  });

  final AuthService authService;
  final WalletService walletService;
  final ZendtagService zendtagService;
  final TransferService transferService;
  final FxService fxService;
  final RecentContactsStore recentContactsStore;

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
  String selectedCurrency = 'USD';

  bool isLoading = false;
  String loadingMessage = 'Loading';

  final List<PaymentRequest> paymentRequests = [];
  final List<Pool> pools = [];

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
    isDarkMode = !isDarkMode;
    notifyListeners();
  }

  void setUsername(String value) {
    username = value.trim().isEmpty ? 'blessed' : value.trim().toLowerCase();
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

  Future<void> fetchHistory() async {
    historyLoading = true;
    lastHistoryError = null;
    notifyListeners();
    try {
      final entries = await transferService.getHistory();
      final contacts = _buildRecentContactsFromHistory(entries);
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
      recentContacts = contacts;
      await recentContactsStore.save(recentContacts);
      lastHistoryError = null;
    } catch (e) {
      lastHistoryError = e.toString();
    } finally {
      historyLoading = false;
      notifyListeners();
    }
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
    notifyListeners();
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
        : '@$recipientZendtag';
    final contactAvatar = recipientDisplayName.isNotEmpty
        ? recipientDisplayName[0].toUpperCase()
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

    await recentContactsStore.save(recentContacts);
    notifyListeners();
  }

  void resetState() {
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
    balanceHidden = false;
    isDarkMode = false;
    selectedCurrency = 'USD';
    isLoading = false;
    loadingMessage = 'Loading';
    unawaited(recentContactsStore.clear());
    notifyListeners();
  }

  void addPaymentRequest(PaymentRequest request) {
    paymentRequests.insert(0, request);
    notifyListeners();
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
      contacts.add(
        RecentContact(
          name: '@$tag',
          tag: tag,
          avatarLabel: tag[0].toUpperCase(),
        ),
      );
    }

    return contacts.take(20).toList();
  }

  List<RecentContact> _mergeRecentContacts(RecentContact contact) {
    final remaining = recentContacts.where((c) => c.tag != contact.tag);
    return [contact, ...remaining].take(20).toList();
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
