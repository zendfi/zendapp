import 'dart:math';

import 'package:flutter/material.dart';

import '../design/zend_tokens.dart';
import '../features/pools/pool.dart';
import '../features/request/payment_request.dart';

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
  ZendAppModel()
      : recentTransactions = [
          ZendTransaction(
            name: 'Monmouth Coffee',
            note: 'London, UK',
            amount: '-\$4.80',
            time: '08:42 AM',
            avatarLabel: 'M',
          ),
          ZendTransaction(
            name: 'Yield distribution',
            note: 'USDC Auto-Staking',
            amount: '+\$2.14',
            time: 'Yesterday',
            avatarLabel: '↓',
            amountColor: ZendColors.positive,
          ),
          ZendTransaction(
            name: 'Alex Johnson',
            note: 'Dinner split',
            amount: '-\$45.00',
            time: 'Oct 12',
            avatarLabel: 'A',
          ),
        ] {
    // Seed mock pools
    pools.addAll([
      Pool(
        id: 'pool001',
        name: 'Birthday Gift',
        targetAmount: 200.0,
        gathered: 142.50,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        deadline: DateTime.now().add(const Duration(days: 4)),
        participants: [
          const PoolParticipant(displayName: '@carissa', avatarLabel: 'C', contribution: 65.00),
          const PoolParticipant(displayName: '@david', avatarLabel: 'D', contribution: 42.50),
          const PoolParticipant(displayName: '@amara', avatarLabel: 'A', contribution: 35.00),
          const PoolParticipant(displayName: 'Josh', avatarLabel: 'J', isExternal: true),
        ],
      ),
      Pool(
        id: 'pool002',
        name: 'Team Lunch',
        targetAmount: 80.0,
        gathered: 45.00,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        participants: [
          const PoolParticipant(displayName: '@tunde', avatarLabel: 'T', contribution: 25.00),
          const PoolParticipant(displayName: '@blessed', avatarLabel: 'B', contribution: 20.00),
        ],
      ),
    ]);
  }

  Locale _locale = const Locale('en');
  late String greetingPrefix = _greetingForLocale(_locale);

  String username = 'blessed';
  bool balanceHidden = false;
  double balance = 789.13;
  double monthlyYield = 2.14;
  String selectedCurrency = 'USD';
  final List<ZendTransaction> recentTransactions;
  
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

  void sendMoney({
    required String name,
    required String note,
    required double amount,
    bool external = false,
  }) {
    balance = (balance - amount).clamp(0, double.infinity);
    recentTransactions.insert(
      0,
      ZendTransaction(
        name: name,
        note: note,
        amount: external ? '-\$${amount.toStringAsFixed(2)}' : '-\$${amount.toStringAsFixed(2)}',
        time: 'Just now',
        avatarLabel: name.isNotEmpty ? name[0].toUpperCase() : '?',
      ),
    );
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
}

class ZendScope extends InheritedNotifier<ZendAppModel> {
  const ZendScope({super.key, required ZendAppModel notifier, required super.child}) : super(notifier: notifier);

  static ZendAppModel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ZendScope>();
    assert(scope != null, 'ZendScope not found in widget tree');
    return scope!.notifier!;
  }
}
