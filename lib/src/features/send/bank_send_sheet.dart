import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_country_flag.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/sound_service.dart';

part 'bank_send_stages.dart';

Future<void> showBankSendSheet(BuildContext context, {required double amount}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => BankSendSheet(amount: amount),
  );
}

enum _BankSendRail {
  ngn,
  ach,
  fp,
  sepa,
}

extension _BankSendRailExt on _BankSendRail {
  String get currency => switch (this) {
        _BankSendRail.ngn => 'NGN',
        _BankSendRail.ach => 'USD',
        _BankSendRail.fp => 'GBP',
        _BankSendRail.sepa => 'EUR',
      };

  String get bridgeCurrency => switch (this) {
        _BankSendRail.ach => 'usd',
        _BankSendRail.fp => 'gbp',
        _BankSendRail.sepa => 'eur',
        _ => '',
      };

  String get bridgeRail => switch (this) {
        _BankSendRail.ach => 'ach',
        _BankSendRail.fp => 'faster_payments',
        _BankSendRail.sepa => 'sepa',
        _ => '',
      };

  bool get isIntl => this != _BankSendRail.ngn;
}

enum _BankSendStage {
  railSelect,
  bankInput,
  bankPicker,
  addIntlAccount,
  intlAccounts,
  resolving,
  confirmation,
  pin,
  processing,
  success,
  error,
}

class BankSendSheet extends StatefulWidget {
  const BankSendSheet({super.key, required this.amount});

  final double amount;

  @override
  State<BankSendSheet> createState() => _BankSendSheetState();
}

class _BankSendSheetState extends State<BankSendSheet>
    with TickerProviderStateMixin {
  static const Duration _transition = Duration(milliseconds: 140);
  static const Duration _resize = Duration(milliseconds: 200);

  _BankSendStage _stage = _BankSendStage.railSelect;
  _BankSendRail _rail = _BankSendRail.ngn;

  List<Map<String, dynamic>> _banks = [];
  Map<String, dynamic>? _selectedBank;
  final _accountController = TextEditingController();
  String? _resolvedAccountName;
  double _ngnRate = 0;

  List<Map<String, dynamic>> _savedAccounts = [];
  Map<String, dynamic>? _selectedSavedAccount;

  String? _orderId;
  String? _depositAddress;
  String? _blockhash;
  String? _feePayer;
  double? _fiatAmount;

  String _pinDigits = '';
  String? _pinError;
  int _pinAttempts = 0;

  String? _errorMessage;
  String _resolvingMessage = 'Verifying...';

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
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  double get _sheetHeightFraction => switch (_stage) {
        _BankSendStage.railSelect => 0.55,
        _BankSendStage.bankInput => 0.72,
        _BankSendStage.bankPicker => 0.88,
        _BankSendStage.addIntlAccount => 0.88,
        _BankSendStage.intlAccounts => 0.72,
        _BankSendStage.resolving => 0.45,
        _BankSendStage.confirmation => 0.72,
        _BankSendStage.pin => 0.72,
        _BankSendStage.processing => 0.45,
        _BankSendStage.success => 0.52,
        _BankSendStage.error => 0.52,
      };

  void _goTo(_BankSendStage stage) => setState(() => _stage = stage);

  Future<void> _selectRail(_BankSendRail rail) async {
    _rail = rail;
    _goTo(_BankSendStage.resolving);

    try {
      final model = ZendScope.of(context);
      if (!rail.isIntl) {
        final results = await Future.wait([
          model.walletService.apiClient.getBankSendNgnBanks(),
          model.walletService.apiClient.getBankSendNgnRates(),
        ]);
        final banks = (results[0] as List<dynamic>).cast<Map<String, dynamic>>();
        final rates = results[1] as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _banks = banks;
          _ngnRate = (rates['rate_ngn_per_usd'] as num?)?.toDouble() ?? 0;
          _stage = _BankSendStage.bankInput;
        });
      } else {
        final accounts = await model.walletService.apiClient.getIntlSavedAccounts();
        if (!mounted) return;
        final filtered = accounts
            .cast<Map<String, dynamic>>()
            .where((a) =>
                (a['currency'] as String? ?? '').toLowerCase() ==
                rail.bridgeCurrency)
            .toList();
        setState(() {
          _savedAccounts = filtered;
          _stage = _BankSendStage.intlAccounts;
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
      await _prepare();
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

  Future<void> _selectSavedAccount(Map<String, dynamic> account) async {
    _selectedSavedAccount = account;
    _goTo(_BankSendStage.resolving);
    try {
      await _prepare();
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

  Future<void> _prepare() async {
    setState(() {
      _stage = _BankSendStage.resolving;
      _resolvingMessage = !_rail.isIntl
          ? 'Verifying bank details...\nSit tight!'
          : 'Preparing transfer...';
    });
    try {
      if (widget.amount <= 0) {
        setState(() {
          _errorMessage = 'Please enter an amount before sending.';
          _stage = _BankSendStage.error;
        });
        return;
      }
      final model = ZendScope.of(context);
      Map<String, dynamic> result;

      if (!_rail.isIntl) {
        result = await model.walletService.apiClient.prepareNgnBankSend(
          amountUsdc: widget.amount,
          bankId: _selectedBank!['id'] as String,
          accountNumber: _accountController.text.trim(),
        );
      } else {
        result = await model.walletService.apiClient.prepareIntlBankSend(
          amountUsdc: widget.amount,
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
        _resolvedAccountName = result['account_name'] as String?;
        _stage = _BankSendStage.confirmation;
      });
    } on ApiException {
      if (!mounted) return;
      rethrow;
    } catch (_) {
      if (!mounted) return;
      rethrow;
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
      final signedTx = await model.walletService.buildAndSignTransactionToAddress(
        pin: pin,
        amountUsdc: widget.amount,
        destinationAddress: _depositAddress!,
        blockhash: _blockhash!,
        feePayerAddress: _feePayer ?? 'FM7tTDb8CSERXF6WjuTQGvba46L2r3YfCQp345RjxW52',
      );

      if (!_rail.isIntl) {
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
          curve: Curves.easeOut,
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
                  reverseDuration: const Duration(milliseconds: 100),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_stage),
                    child: _buildStage(),
                  ),
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
          amount: widget.amount,
          onSelect: _selectRail,
        );
      case _BankSendStage.bankInput:
        return _NgnBankInputStage(
          amount: widget.amount,
          ngnRate: _ngnRate,
          selectedBank: _selectedBank,
          accountController: _accountController,
          errorMessage: _errorMessage,
          onSelectBank: () => _goTo(_BankSendStage.bankPicker),
          onContinue: _resolveNgnAccount,
          onBack: () => _goTo(_BankSendStage.railSelect),
        );
      case _BankSendStage.bankPicker:
        return _BankPickerStage(
          banks: _banks,
          onSelect: (bank) {
            setState(() {
              _selectedBank = bank;
              _errorMessage = null;
              _stage = _BankSendStage.bankInput;
            });
          },
          onBack: () => _goTo(_BankSendStage.bankInput),
        );
      case _BankSendStage.intlAccounts:
        return _IntlAccountStage(
          rail: _rail,
          savedAccounts: _savedAccounts,
          onSelect: _selectSavedAccount,
          onBack: () => _goTo(_BankSendStage.railSelect),
          onAddAccount: () => _goTo(_BankSendStage.addIntlAccount),
        );
      case _BankSendStage.addIntlAccount:
        return _AddIntlAccountStage(
          rail: _rail,
          onBack: () => _goTo(_BankSendStage.intlAccounts),
          onSaved: (account) {
            _savedAccounts = [..._savedAccounts, account];
            _selectSavedAccount(account);
          },
        );
      case _BankSendStage.resolving:
        return _ResolvingStage(message: _resolvingMessage);
      case _BankSendStage.confirmation:
        return _ConfirmationStage(
          rail: _rail,
          amountUsdc: widget.amount,
          fiatAmount: _fiatAmount,
          accountName: _resolvedAccountName ?? '',
          bankName: _selectedBank?['name'] as String? ??
              (_selectedSavedAccount?['bank_name'] as String? ?? ''),
          accountNumberMasked: _accountController.text.isNotEmpty
              ? _maskAccount(_accountController.text.trim())
              : (_selectedSavedAccount?['account_last4'] != null
                  ? '••••${_selectedSavedAccount!['account_last4']}'
                  : ''),
          onConfirm: () => _goTo(_BankSendStage.pin),
          onBack: () => _goTo(
              _rail.isIntl ? _BankSendStage.intlAccounts : _BankSendStage.bankInput),
        );
      case _BankSendStage.pin:
        return _PinStage(
          amountUsdc: widget.amount,
          rail: _rail,
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
        return const _ProcessingStage();
      case _BankSendStage.success:
        return _SuccessStage(
          rail: _rail,
          amountUsdc: widget.amount,
          fiatAmount: _fiatAmount,
          bankName: _selectedBank?['name'] as String? ??
              (_selectedSavedAccount?['bank_name'] as String? ?? ''),
          onDone: _dismiss,
        );
      case _BankSendStage.error:
        return _ErrorStage(
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
