import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_country_flag.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/payment_rail_models.dart';
import '../../services/signing_policy_service.dart';
import '../../services/sound_service.dart';
import '../../services/wallet_session_cache.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../design/zend_modal.dart';
import '../../core/zend_format.dart';

part 'bank_send_stages.dart';

Future<void> showBankSendSheet(BuildContext context, {required double amount}) {
  return showZendModalSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => BankSendSheet(amount: amount),
  );
}

enum _BankSendRail { ngn, ach, fp, sepa }

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
  ngnAccounts,
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
  // Blockchain rail the backend resolved for this order: 'solana' or 'sui'.
  // Drives whether we co-sign a Solana SPL tx (PIN/keypair) or sign the Sui
  // gasless envelope via zkLogin. Null until prepare returns.
  String? _signRail;
  // Sui rail only: the unsigned gasless-transfer envelope the client must sign.
  RailEnvelope? _prepareEnvelope;
  double? _fiatAmount;
  double?
  _confirmedAmountUsdc; // amount_usdc returned by prepare (may be rounded up for PAJ)

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
    _shakeAnimation = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
        TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
        TweenSequenceItem(tween: Tween(begin: 10, end: -6), weight: 2),
        TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 2),
        TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
      ],
    ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));
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
    _BankSendStage.ngnAccounts => 0.72,
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
          model.walletService.apiClient.getNgnSavedAccounts(),
        ]);
        final banks = (results[0] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final rates = results[1] as Map<String, dynamic>;
        final savedAccounts = (results[2] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        if (!mounted) return;
        setState(() {
          _banks = banks;
          _ngnRate = (rates['rate_ngn_per_usd'] as num?)?.toDouble() ?? 0;
          _savedAccounts = savedAccounts;
          _stage = _BankSendStage.ngnAccounts;
        });
      } else {
        final accounts = await model.walletService.apiClient
            .getIntlSavedAccounts();
        if (!mounted) return;
        final filtered = accounts
            .cast<Map<String, dynamic>>()
            .where(
              (a) =>
                  (a['currency'] as String? ?? '').toLowerCase() ==
                  rail.bridgeCurrency,
            )
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

  /// Runs a bank-send prepare call, transparently handling the Sui gasless rail's
  /// deposit step.
  ///
  /// On Sui the USDC may sit in `Coin<T>` objects rather than the spendable
  /// address-balance accumulator the transfer draws on. When prepare reports that,
  /// deposit the coin objects and retry once — the same contract the P2P flow
  /// uses, kept invisible to the user (no extra auth; the zkLogin proof is cached
  /// for the session). Non-Sui prepares never hit this and pass straight through.
  Future<Map<String, dynamic>> _prepareWithSuiDepositRetry(
    ZendAppModel model,
    Future<Map<String, dynamic>> Function() runPrepare,
  ) async {
    try {
      return await runPrepare();
    } on ApiException catch (e) {
      if (e.errorCode != 'SUI_ADDRESS_BALANCE_INSUFFICIENT') rethrow;
      await model.zkLoginService.depositCoinObjectsToAddressBalance(
        rail: PaymentRail.sui,
        network: kSuiNetwork,
      );
      return runPrepare();
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
        // Use saved account data if one was selected, otherwise use manual input
        final bankId = _selectedSavedAccount != null
            ? (_selectedSavedAccount!['paj_bank_id'] as String? ??
                  _selectedBank!['id'] as String)
            : _selectedBank!['id'] as String;
        final accountNumber = _selectedSavedAccount != null
            ? (_selectedSavedAccount!['paj_account_number'] as String? ??
                  _accountController.text.trim())
            : _accountController.text.trim();
        final savedAccountId = _selectedSavedAccount?['id'] as String?;

        result = await _prepareWithSuiDepositRetry(
          model,
          () => model.walletService.apiClient.prepareNgnBankSend(
            amountUsdc: widget.amount,
            bankId: bankId,
            accountNumber: accountNumber,
            savedAccountId: savedAccountId,
          ),
        );
      } else {
        result = await _prepareWithSuiDepositRetry(
          model,
          () => model.walletService.apiClient.prepareIntlBankSend(
            amountUsdc: widget.amount,
            savedAccountId: _selectedSavedAccount!['id'] as String,
          ),
        );
      }

      if (!mounted) return;
      final envelopeJson = result['envelope'];
      setState(() {
        _orderId = result['order_id'] as String?;
        _signRail = result['rail'] as String?;
        _depositAddress = result['deposit_address'] as String?;
        _blockhash = result['blockhash'] as String?;
        _feePayer = result['fee_payer'] as String?;
        // Sui rail returns a signable envelope instead of Solana tx materials.
        _prepareEnvelope = envelopeJson is Map<String, dynamic>
            ? RailEnvelope.fromJson(envelopeJson)
            : null;
        _fiatAmount = (result['fiat_amount'] as num?)?.toDouble();
        _confirmedAmountUsdc =
            (result['amount_usdc'] as num?)?.toDouble() ?? widget.amount;
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
      if (_pinDigits.length >= 6) return;
      _pinDigits += value;
    });
    if (_pinDigits.length == 6) _submitWithPin(_pinDigits);
  }

  Future<void> _proceedFromConfirmation() async {
    // Sui gasless rail signs with the in-memory zkLogin ephemeral key, so there
    // is no PIN or stored keypair to gate on — skip the PIN policy entirely.
    if (_signRail == 'sui') {
      _goTo(_BankSendStage.processing);
      await _executeSui();
      return;
    }

    final policy = SigningPolicyService();
    final cache = WalletSessionCache.instance;
    final amount = _confirmedAmountUsdc ?? widget.amount;
    final needsPin = await policy.requiresPinForAmount(amount);

    if (!needsPin && cache.hasKeypair) {
      // Session signing — skip PIN
      _goTo(_BankSendStage.processing);
      await _executeWithKeypair(cache.keypair!);
    } else {
      _goTo(_BankSendStage.pin);
    }
  }

  Future<void> _submitWithPin(String pin) async {
    _goTo(_BankSendStage.processing);
    try {
      final model = ZendScope.of(context);

      // Verify PIN if session cache is available
      final cache = WalletSessionCache.instance;
      if (cache.hasKeypair) {
        final valid = await model.signingPolicyService.verifyPinAgainstCache(
          pin,
          model.walletService,
        );
        if (!valid) {
          if (!mounted) return;
          _pinAttempts++;
          if (_pinAttempts >= 5) {
            model.appLockService.lock();
            setState(() {
              _errorMessage =
                  'Too many incorrect PIN attempts. Please unlock again.';
              _stage = _BankSendStage.error;
            });
          } else {
            _shakeController.forward(from: 0);
            setState(() {
              _pinDigits = '';
              _pinError = 'Incorrect PIN';
              _stage = _BankSendStage.pin;
            });
          }
          return;
        }
        await _executeWithKeypair(cache.keypair!);
      } else {
        await _executeWithPinString(pin);
      }
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

  Future<void> _executeWithKeypair(dynamic keypairBytes) async {
    try {
      final model = ZendScope.of(context);
      final signedTx = await model.walletService
          .buildAndSignTransactionToAddressFromCache(
            keypairBytes: keypairBytes,
            amountUsdc: _confirmedAmountUsdc ?? widget.amount,
            destinationAddress: _depositAddress!,
            blockhash: _blockhash!,
            feePayerAddress:
                _feePayer ?? 'FM7tTDb8CSERXF6WjuTQGvba46L2r3YfCQp345RjxW52',
          );
      await _submitSignedTx(signedTx);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = _BankSendStage.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = _BankSendStage.error;
      });
    }
  }

  Future<void> _executeWithPinString(String pin) async {
    try {
      final model = ZendScope.of(context);
      final signedTx = await model.walletService
          .buildAndSignTransactionToAddress(
            pin: pin,
            amountUsdc: _confirmedAmountUsdc ?? widget.amount,
            destinationAddress: _depositAddress!,
            blockhash: _blockhash!,
            feePayerAddress:
                _feePayer ?? 'FM7tTDb8CSERXF6WjuTQGvba46L2r3YfCQp345RjxW52',
          );
      await _submitSignedTx(signedTx);
    } on PinDecryptionException {
      rethrow;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = _BankSendStage.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = _BankSendStage.error;
      });
    }
  }

  /// Sui gasless offramp: sign the prepared transfer envelope with zkLogin and
  /// submit it. No PIN/keypair — the ephemeral key and cached proof do the work.
  Future<void> _executeSui() async {
    try {
      final model = ZendScope.of(context);
      final envelope = _prepareEnvelope;
      if (envelope == null) {
        throw StateError('Missing Sui transfer envelope');
      }
      final transactionDataBcs =
          envelope.payload['transaction_data_bcs'] as String?;
      if (transactionDataBcs == null || transactionDataBcs.isEmpty) {
        throw StateError('Sui envelope carries no transaction bytes');
      }

      // Signs blake2b256(intent || bcs) with the ephemeral key, then has the
      // backend wrap that signature and the proof into a zkLogin authenticator.
      final signature = await model.zkLoginService.signPreparedTransaction(
        transactionDataBcsBase64: transactionDataBcs,
      );

      final signedEnvelope = RailEnvelope(
        type: 'sui_signed_transaction',
        version: 1,
        // `kind`/`version` are repeated inside the payload on purpose: the Sui
        // rail deserializes this payload on its own and requires an inner
        // `kind`, while the outer pair satisfies the shared envelope check.
        payload: {
          'kind': 'sui_signed_transaction',
          'version': 1,
          'transaction_data_bcs': transactionDataBcs,
          'signatures': [signature],
        },
      );

      // Route to the confirm endpoint matching the fiat rail — the Sui signing
      // is identical, only the backend order namespace (ngn vs intl) differs.
      if (!_rail.isIntl) {
        await model.walletService.apiClient.confirmBankSend(
          orderId: _orderId!,
          envelope: signedEnvelope,
        );
      } else {
        await model.walletService.apiClient.confirmIntlBankSend(
          orderId: _orderId!,
          envelope: signedEnvelope,
        );
      }

      if (!mounted) return;
      unawaited(model.fetchBalance());
      setState(() => _stage = _BankSendStage.success);
      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = _BankSendStage.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = _BankSendStage.error;
      });
    }
  }

  Future<void> _submitSignedTx(String signedTx) async {
    try {
      final model = ZendScope.of(context);
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
    final mq = MediaQuery.of(context);
    final screenHeight = mq.size.height;

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
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
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
        return _RailSelectStage(amount: widget.amount, onSelect: _selectRail);
      case _BankSendStage.bankInput:
        return _NgnBankInputStage(
          amount: widget.amount,
          ngnRate: _ngnRate,
          selectedBank: _selectedBank,
          accountController: _accountController,
          errorMessage: _errorMessage,
          onSelectBank: () => _goTo(_BankSendStage.bankPicker),
          onContinue: _resolveNgnAccount,
          onBack: () => _goTo(_BankSendStage.ngnAccounts),
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
      case _BankSendStage.ngnAccounts:
        return _IntlAccountStage(
          rail: _rail,
          savedAccounts: _savedAccounts,
          onSelect: _selectSavedAccount,
          onBack: () => _goTo(_BankSendStage.railSelect),
          onAddAccount: () => _goTo(_BankSendStage.bankInput),
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
          amountUsdc: _confirmedAmountUsdc ?? widget.amount,
          fiatAmount: _fiatAmount,
          accountName: _resolvedAccountName ?? '',
          bankName:
              _selectedBank?['name'] as String? ??
              (_selectedSavedAccount?['bank_name'] as String? ?? ''),
          accountNumberMasked: _accountController.text.isNotEmpty
              ? _maskAccount(_accountController.text.trim())
              : (_selectedSavedAccount != null
                    ? (_selectedSavedAccount!['account_last4'] != null
                          ? '••••${_selectedSavedAccount!['account_last4']}'
                          : ((_selectedSavedAccount!['account_number_masked']
                                            as String?)
                                        ?.isNotEmpty ==
                                    true
                                ? _selectedSavedAccount!['account_number_masked']
                                      as String
                                : '—'))
                    : '—'),
          onConfirm: _proceedFromConfirmation,
          onBack: () => _goTo(
            _rail.isIntl
                ? _BankSendStage.intlAccounts
                : _BankSendStage.ngnAccounts,
          ),
        );
      case _BankSendStage.pin:
        return _PinStage(
          amountUsdc: _confirmedAmountUsdc ?? widget.amount,
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
          amountUsdc: _confirmedAmountUsdc ?? widget.amount,
          fiatAmount: _fiatAmount,
          bankName:
              _selectedBank?['name'] as String? ??
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
