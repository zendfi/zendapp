import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/sound_service.dart';

part 'bank_send_stages.dart';

Future<void> showBankSendSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => const BankSendSheet(),
  );
}

enum _BankSendRail { ngn, intl }

enum _BankSendStage {
  railSelect,
  bankInput,
  addIntlAccount,
  resolving,
  amountInput,
  confirmation,
  pin,
  processing,
  success,
  error,
}

class BankSendSheet extends StatefulWidget {
  const BankSendSheet({super.key});

  @override
  State<BankSendSheet> createState() => _BankSendSheetState();
}

class _BankSendSheetState extends State<BankSendSheet>
    with SingleTickerProviderStateMixin {
  static const Duration _transition = Duration(milliseconds: 180);
  static const Duration _resize = Duration(milliseconds: 220);

  _BankSendStage _stage = _BankSendStage.railSelect;
  _BankSendRail _rail = _BankSendRail.ngn;

  // NGN state
  List<Map<String, dynamic>> _banks = [];
  Map<String, dynamic>? _selectedBank;
  final _accountController = TextEditingController();
  String? _resolvedAccountName;
  double _ngnRate = 0;

  // Intl state
  List<Map<String, dynamic>> _savedAccounts = [];
  Map<String, dynamic>? _selectedSavedAccount;

  // Amount
  final _amountController = TextEditingController();
  double? _amountUsdc;
  double? _fiatAmount;
  String _fiatCurrency = 'NGN';

  // Order
  String? _orderId;
  String? _depositAddress;
  String? _blockhash;
  String? _feePayer;

  // PIN
  String _pinDigits = '';
  String? _pinError;
  int _pinAttempts = 0;

  // Error
  String? _errorMessage;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _accountController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  double get _sheetHeightFraction {
    switch (_stage) {
      case _BankSendStage.railSelect:
        return 0.45;
      case _BankSendStage.bankInput:
        return 0.85;
      case _BankSendStage.addIntlAccount:
        return 0.85;
      case _BankSendStage.resolving:
        return 0.45;
      case _BankSendStage.amountInput:
        return 0.60;
      case _BankSendStage.confirmation:
        return 0.72;
      case _BankSendStage.pin:
        return 0.72;
      case _BankSendStage.processing:
        return 0.45;
      case _BankSendStage.success:
        return 0.52;
      case _BankSendStage.error:
        return 0.52;
    }
  }

  void _goTo(_BankSendStage stage) => setState(() => _stage = stage);

  Future<void> _selectRail(_BankSendRail rail) async {
    _rail = rail;
    _goTo(_BankSendStage.resolving);

    try {
      final model = ZendScope.of(context);
      if (rail == _BankSendRail.ngn) {
        final results = await Future.wait([
          model.walletService.apiClient.getBankSendNgnBanks(),
          model.walletService.apiClient.getBankSendNgnRates(),
        ]);
        final banks = (results[0] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final rates = results[1] as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _banks = banks;
          _ngnRate = (rates['rate_ngn_per_usd'] as num?)?.toDouble() ?? 0;
          _fiatCurrency = 'NGN';
          _stage = _BankSendStage.bankInput;
        });
      } else {
        final accounts = await model.walletService.apiClient
            .getIntlSavedAccounts();
        if (!mounted) return;
        setState(() {
          _savedAccounts = accounts.cast<Map<String, dynamic>>();
          _fiatCurrency = 'USD';
          _stage = _BankSendStage.bankInput;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load bank options. Please try again.';
        _stage = _BankSendStage.error;
      });
    }
  }

  Future<void> _resolveNgnAccount() async {
    final accountNumber = _accountController.text.trim();
    if (_selectedBank == null || accountNumber.length < 10) return;

    _goTo(_BankSendStage.resolving);
    try {
      final model = ZendScope.of(context);
      final result = await model.walletService.apiClient.resolveNgnBankAccount(
        bankId: _selectedBank!['id'] as String,
        accountNumber: accountNumber,
      );
      if (!mounted) return;
      setState(() {
        _resolvedAccountName = result['account_name'] as String?;
        _stage = _BankSendStage.amountInput;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is ApiException
            ? e.userMessage
            : 'Could not verify account. Check the details and try again.';
        _stage = _BankSendStage.bankInput;
      });
    }
  }

  void _selectSavedAccount(Map<String, dynamic> account) {
    setState(() {
      _selectedSavedAccount = account;
      _fiatCurrency =
          (account['currency'] as String? ?? 'usd').toUpperCase();
      _stage = _BankSendStage.amountInput;
    });
  }

  Future<void> _prepare() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;
    _amountUsdc = amount;

    _goTo(_BankSendStage.resolving);
    try {
      final model = ZendScope.of(context);
      Map<String, dynamic> result;

      if (_rail == _BankSendRail.ngn) {
        result = await model.walletService.apiClient.prepareNgnBankSend(
          amountUsdc: amount,
          bankId: _selectedBank!['id'] as String,
          accountNumber: _accountController.text.trim(),
        );
      } else {
        result = await model.walletService.apiClient.prepareIntlBankSend(
          amountUsdc: amount,
          savedAccountId: _selectedSavedAccount!['id'] as String,
        );
      }

      if (!mounted) return;
      setState(() {
        _orderId = result['order_id'] as String?;
        _depositAddress = result['deposit_address'] as String?;
        _blockhash = result['blockhash'] as String?;
        _feePayer = result['fee_payer'] as String?;
        _fiatAmount = (result['fiat_amount'] as num?)?.toDouble();
        _fiatCurrency = result['fiat_currency'] as String? ?? _fiatCurrency;
        _resolvedAccountName ??= result['account_name'] as String?;
        _stage = _BankSendStage.confirmation;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is ApiException
            ? e.userMessage
            : 'Failed to prepare transfer. Please try again.';
        _stage = _BankSendStage.error;
      });
    }
  }

  void _onPinKey(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      _pinError = null;
      if (value == 'del') {
        if (_pinDigits.isNotEmpty) {
          _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
        }
        return;
      }
      if (_pinDigits.length >= 4) return;
      _pinDigits += value;
    });
    if (_pinDigits.length == 4) _submitWithPin(_pinDigits);
  }

  Future<void> _submitWithPin(String pin) async {
    _goTo(_BankSendStage.processing);
    try {
      final model = ZendScope.of(context);

      // Build + sign the transaction using the server-provided blockhash
      final signedTx =
          await model.walletService.buildAndSignTransactionToAddress(
        pin: pin,
        amountUsdc: _amountUsdc!,
        destinationAddress: _depositAddress!,
        blockhash: _blockhash!,
        feePayerAddress: _feePayer ?? 'FM7tTDb8CSERXF6WjuTQGvba46L2r3YfCQp345RjxW52',
      );

      // Submit
      if (_rail == _BankSendRail.ngn) {
        await model.walletService.apiClient.confirmBankSend(
          orderId: _orderId!,
          partiallySignedTx: signedTx,
        );
      } else {
        await model.walletService.apiClient.confirmIntlBankSend(
          orderId: _orderId!,
          partiallySignedTx: signedTx,
        );
      }

      if (!mounted) return;
      unawaited(model.fetchBalance());
      setState(() => _stage = _BankSendStage.success);
      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());
    } on PinDecryptionException {
      if (!mounted) return;
      _pinAttempts++;
      _shakeController.forward(from: 0);
      if (_pinAttempts >= 5) {
        setState(() {
          _errorMessage = 'Too many incorrect PIN attempts.';
          _stage = _BankSendStage.error;
        });
      } else {
        setState(() {
          _pinDigits = '';
          _pinError = 'Incorrect PIN';
          _stage = _BankSendStage.pin;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is ApiException
            ? e.userMessage
            : 'Something went wrong. Please try again.';
        _stage = _BankSendStage.error;
      });
    }
  }

  void _dismiss() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _stage != _BankSendStage.processing,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
        child: AnimatedContainer(
          duration: _resize,
          curve: Curves.easeOutCubic,
          height: screenHeight * _sheetHeightFraction,
          decoration: BoxDecoration(
            color: ZendTheme.of(context).bgPrimary,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZendRadii.xxl),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 14),
              const ZendSheetHandle(),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: _transition,
                  reverseDuration: const Duration(milliseconds: 140),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: _buildStage(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case _BankSendStage.railSelect:
        return _RailSelectStage(
          key: const ValueKey('rail'),
          onSelect: _selectRail,
        );
      case _BankSendStage.bankInput:
        return _rail == _BankSendRail.ngn
            ? _NgnBankInputStage(
                key: const ValueKey('ngn-bank'),
                banks: _banks,
                selectedBank: _selectedBank,
                accountController: _accountController,
                errorMessage: _errorMessage,
                onBankSelected: (b) => setState(() {
                  _selectedBank = b;
                  _errorMessage = null;
                }),
                onContinue: _resolveNgnAccount,
                onBack: () => _goTo(_BankSendStage.railSelect),
              )
            : _IntlAccountStage(
                key: const ValueKey('intl-acct'),
                savedAccounts: _savedAccounts,
                onSelect: _selectSavedAccount,
                onBack: () => _goTo(_BankSendStage.railSelect),
                onAddAccount: () => _goTo(_BankSendStage.addIntlAccount),
              );
      case _BankSendStage.addIntlAccount:
        return _AddIntlAccountStage(
          key: const ValueKey('add-intl'),
          onBack: () => _goTo(_BankSendStage.bankInput),
          onSaved: (account) {
            _savedAccounts = [..._savedAccounts, account];
            _selectSavedAccount(account);
          },
        );
      case _BankSendStage.resolving:
        return const _ResolvingStage(key: ValueKey('resolving'));
      case _BankSendStage.amountInput:
        return _AmountInputStage(
          key: const ValueKey('amount'),
          rail: _rail,
          accountName: _resolvedAccountName,
          bankName: _selectedBank?['name'] as String? ??
              (_selectedSavedAccount?['bank_name'] as String?),
          accountNumberMasked: _accountController.text.isNotEmpty
              ? _maskAccount(_accountController.text.trim())
              : (_selectedSavedAccount?['account_last4'] != null
                  ? '••••${_selectedSavedAccount!['account_last4']}'
                  : null),
          ngnRate: _ngnRate,
          fiatCurrency: _fiatCurrency,
          amountController: _amountController,
          onContinue: _prepare,
          onBack: () => _goTo(_BankSendStage.bankInput),
        );
      case _BankSendStage.confirmation:
        return _ConfirmationStage(
          key: const ValueKey('confirm'),
          rail: _rail,
          amountUsdc: _amountUsdc ?? 0,
          fiatAmount: _fiatAmount,
          fiatCurrency: _fiatCurrency,
          accountName: _resolvedAccountName ?? '',
          bankName: _selectedBank?['name'] as String? ??
              (_selectedSavedAccount?['bank_name'] as String? ?? ''),
          accountNumberMasked: _accountController.text.isNotEmpty
              ? _maskAccount(_accountController.text.trim())
              : (_selectedSavedAccount?['account_last4'] != null
                  ? '••••${_selectedSavedAccount!['account_last4']}'
                  : ''),
          onConfirm: () => _goTo(_BankSendStage.pin),
          onBack: () => _goTo(_BankSendStage.amountInput),
        );
      case _BankSendStage.pin:
        return _PinStage(
          key: const ValueKey('pin'),
          amountUsdc: _amountUsdc ?? 0,
          fiatCurrency: _fiatCurrency,
          pinDigits: _pinDigits,
          pinError: _pinError,
          shakeAnimation: _shakeAnimation,
          shakeController: _shakeController,
          onKey: _onPinKey,
          onBack: () {
            setState(() {
              _pinDigits = '';
              _pinError = null;
              _stage = _BankSendStage.confirmation;
            });
          },
        );
      case _BankSendStage.processing:
        return const _ProcessingStage(key: ValueKey('processing'));
      case _BankSendStage.success:
        return _SuccessStage(
          key: const ValueKey('success'),
          rail: _rail,
          amountUsdc: _amountUsdc ?? 0,
          fiatAmount: _fiatAmount,
          fiatCurrency: _fiatCurrency,
          bankName: _selectedBank?['name'] as String? ??
              (_selectedSavedAccount?['bank_name'] as String? ?? ''),
          onDone: _dismiss,
        );
      case _BankSendStage.error:
        return _ErrorStage(
          key: const ValueKey('error'),
          message: _errorMessage ?? 'Something went wrong.',
          onRetry: () {
            setState(() {
              _errorMessage = null;
              _pinDigits = '';
              _stage = _BankSendStage.confirmation;
            });
          },
          onCancel: _dismiss,
        );
    }
  }

  String _maskAccount(String n) {
    if (n.length <= 4) return n;
    return '••••${n.substring(n.length - 4)}';
  }
}
