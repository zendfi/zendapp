import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';

enum _DepositStage { amount, pin, processing, success, error }

class SavingsDepositSheet extends StatefulWidget {
  const SavingsDepositSheet({
    super.key,
    this.pocketId,
    this.pocketLabel,
  });

  /// If set, deposits into this specific pocket (goal or lock).
  final String? pocketId;

  /// If set, shown at the top of the amount stage instead of "Save money".
  final String? pocketLabel;

  @override
  State<SavingsDepositSheet> createState() => _SavingsDepositSheetState();
}

class _SavingsDepositSheetState extends State<SavingsDepositSheet> {
  _DepositStage _stage = _DepositStage.amount;

  String _amountInput = '';
  String? _amountError;

  String _pinDigits = '';
  String? _pinError;

  String? _errorMessage;

  static const double _minDeposit = 1.0;

  double get _parsedAmount {
    if (_amountInput.isEmpty) return 0.0;
    return double.tryParse(_amountInput) ?? 0.0;
  }

  double get _userBalance {
    try {
      return ZendScope.of(context).balance;
    } catch (_) {
      return 0.0;
    }
  }

  bool get _hasSufficientBalance => _parsedAmount <= _userBalance;
  bool get _meetsMinimum => _parsedAmount >= _minDeposit;
  bool get _amountValid => _meetsMinimum && _hasSufficientBalance;

  String get _displayAmount =>
      _amountInput.isEmpty ? '\$0' : '\$$_amountInput';

  void _onAmountKey(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      _amountError = null;
      if (key == 'del') {
        if (_amountInput.isNotEmpty) {
          _amountInput = _amountInput.substring(0, _amountInput.length - 1);
        }
        return;
      }
      if (key == '.' && _amountInput.contains('.')) return;
      if (key == '.' && _amountInput.isEmpty) {
        _amountInput = '0.';
        return;
      }
      final dotIdx = _amountInput.indexOf('.');
      if (dotIdx >= 0 && _amountInput.length - dotIdx > 2) return;
      _amountInput += key;
    });
  }

  void _onAmountConfirm() {
    if (!_meetsMinimum) {
      setState(() => _amountError = 'Minimum deposit is \$1.00');
      return;
    }
    if (!_hasSufficientBalance) {
      setState(() => _amountError = 'Insufficient balance');
      return;
    }
    setState(() => _stage = _DepositStage.pin);
  }

  void _onPinKey(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      _pinError = null;
      if (key == 'del') {
        if (_pinDigits.isNotEmpty) {
          _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
        }
        return;
      }
      if (_pinDigits.length >= 4) return;
      _pinDigits += key;
    });
    if (_pinDigits.length == 4) {
      _submitDeposit();
    }
  }

  Future<void> _submitDeposit() async {
    setState(() => _stage = _DepositStage.processing);

    try {
      final model = ZendScope.of(context);
      final savingsService = model.savingsService;
      final walletService = model.walletService;

      // Step 1: prepare — backend calls Kamino, returns unsigned tx bytes
      // Pass pocket_id if targeting a specific pocket
      final prepare = await savingsService.prepareDeposit(
        _parsedAmount,
        pocketId: widget.pocketId,
      );

      // Step 2: sign on-device with PIN
      final signedTx = await walletService.signExistingTransaction(
        pin: _pinDigits,
        txBytesB64: prepare.txBytesB64,
      );

      // Step 3: submit — backend co-signs as fee payer and broadcasts
      await savingsService.submitDeposit(
        signedTx,
        pocketId: widget.pocketId,
      );

      // Optimistic balance deduction + background refresh
      model.balance =
          (model.balance - _parsedAmount).clamp(0, double.infinity);
      unawaited(model.fetchBalance());
      unawaited(model.fetchSavingsSnapshot());

      if (!mounted) return;
      setState(() => _stage = _DepositStage.success);
      HapticFeedback.mediumImpact();
    } on PinDecryptionException {
      if (!mounted) return;
      setState(() {
        _pinDigits = '';
        _pinError = 'Incorrect PIN';
        _stage = _DepositStage.pin;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = _DepositStage.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = _DepositStage.error;
      });
    }
  }

  double get _heightFactor => switch (_stage) {
        _DepositStage.amount => 0.82,
        _DepositStage.pin => 0.70,
        _DepositStage.processing => 0.45,
        _DepositStage.success => 0.50,
        _DepositStage.error => 0.55,
      };

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _stage != _DepositStage.processing,
      child: Container(
        height: screenHeight * _heightFactor,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZendRadii.xxl),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 14),
            const ZendSheetHandle(),
            const SizedBox(height: 8),
            Expanded(child: _buildStage()),
          ],
        ),
      ),
    );
  }

  Widget _buildStage() {
    return switch (_stage) {
      _DepositStage.amount => _AmountStage(
          amountInput: _amountInput,
          displayAmount: _displayAmount,
          amountError: _amountError,
          userBalance: _userBalance,
          amountValid: _amountValid,
          onKey: _onAmountKey,
          onConfirm: _onAmountConfirm,
          pocketLabel: widget.pocketLabel,
        ),
      _DepositStage.pin => _PinStage(
          amount: _parsedAmount,
          pinDigits: _pinDigits,
          pinError: _pinError,
          onKey: _onPinKey,
          onBack: () => setState(() {
            _pinDigits = '';
            _pinError = null;
            _stage = _DepositStage.amount;
          }),
        ),
      _DepositStage.processing => _ProcessingStage(amount: _parsedAmount),
      _DepositStage.success => _SuccessStage(
          amount: _parsedAmount,
          onDone: () => Navigator.of(context).pop(),
        ),
      _DepositStage.error => _ErrorStage(
          message: _errorMessage ?? 'Something went wrong.',
          onRetry: () => setState(() {
            _pinDigits = '';
            _pinError = null;
            _stage = _DepositStage.pin;
          }),
          onCancel: () => Navigator.of(context).pop(),
        ),
    };
  }
}

// ── Amount stage ──────────────────────────────────────────────────────────────

class _AmountStage extends StatelessWidget {
  const _AmountStage({
    required this.amountInput,
    required this.displayAmount,
    required this.amountError,
    required this.userBalance,
    required this.amountValid,
    required this.onKey,
    required this.onConfirm,
    this.pocketLabel,
  });

  final String amountInput;
  final String displayAmount;
  final String? amountError;
  final double userBalance;
  final bool amountValid;
  final ValueChanged<String> onKey;
  final VoidCallback onConfirm;
  final String? pocketLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pocketLabel?.trim().isNotEmpty == true ? pocketLabel! : 'Save money',
            style: const TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: ZendColors.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.lg),

          Center(
            child: Text(
              displayAmount,
              style: const TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 48,
                fontWeight: FontWeight.w700,
                color: ZendColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: ZendSpacing.xs),

          Center(
            child: Text(
              amountError ?? 'Available: \$${userBalance.toStringAsFixed(2)}',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: amountError != null
                    ? ZendColors.destructive
                    : ZendColors.textSecondary,
              ),
            ),
          ),

          const Spacer(),

          _NumericKeypad(onKey: onKey),
          const SizedBox(height: ZendSpacing.md),

          PrimaryButton(
            label: 'Save $displayAmount',
            onPressed: amountValid ? onConfirm : null,
          ),
        ],
      ),
    );
  }
}

// ── PIN stage ─────────────────────────────────────────────────────────────────

class _PinStage extends StatelessWidget {
  const _PinStage({
    required this.amount,
    required this.pinDigits,
    required this.pinError,
    required this.onKey,
    required this.onBack,
  });

  final double amount;
  final String pinDigits;
  final String? pinError;
  final ValueChanged<String> onKey;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: const Icon(Icons.arrow_back,
                  color: ZendColors.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Save \$${amount.toStringAsFixed(2)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ZendColors.textPrimary,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < pinDigits.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? ZendColors.textPrimary
                      : ZendColors.bgSecondary,
                  border: Border.all(color: ZendColors.border),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            pinError ?? 'Confirm with your PIN',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: pinError != null
                  ? ZendColors.destructive
                  : ZendColors.textSecondary,
            ),
          ),
          const Spacer(),
          _NumericKeypad(onKey: onKey),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── Processing stage ──────────────────────────────────────────────────────────

class _ProcessingStage extends StatelessWidget {
  const _ProcessingStage({required this.amount});
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor:
                AlwaysStoppedAnimation<Color>(ZendColors.accentBright),
          ),
          const SizedBox(height: 20),
          Text(
            'Saving \$${amount.toStringAsFixed(2)}...',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: ZendColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Success stage ─────────────────────────────────────────────────────────────

class _SuccessStage extends StatelessWidget {
  const _SuccessStage({required this.amount, required this.onDone});
  final double amount;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: ZendColors.positive,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            const Text(
              'Money saved! 🎉',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 32,
                color: ZendColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${amount.toStringAsFixed(2)} added to your savings',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: ZendColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: 'Done', onPressed: onDone),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error stage ───────────────────────────────────────────────────────────────

class _ErrorStage extends StatelessWidget {
  const _ErrorStage({
    required this.message,
    required this.onRetry,
    required this.onCancel,
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: ZendColors.destructive,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: ZendColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZendColors.textSecondary,
                      side: const BorderSide(color: ZendColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZendRadii.lg),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontFamily: 'DMSans')),
                  ),
                ),
                const SizedBox(width: ZendSpacing.md),
                Expanded(
                  child: PrimaryButton(label: 'Retry', onPressed: onRetry),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Numeric keypad ────────────────────────────────────────────────────────────

class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({required this.onKey});
  final ValueChanged<String> onKey;

  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', 'del'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _keys.map((row) {
        return Row(
          children: row.map((key) {
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => onKey(key),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  child: key == 'del'
                      ? const Icon(Icons.backspace_outlined,
                          size: 20, color: ZendColors.textPrimary)
                      : Text(
                          key,
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: ZendColors.textPrimary,
                          ),
                        ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
