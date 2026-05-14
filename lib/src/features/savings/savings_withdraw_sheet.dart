import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/savings_models.dart';

enum _WithdrawStage { confirm, pin, processing, success, error }

class SavingsWithdrawSheet extends StatefulWidget {
  const SavingsWithdrawSheet({super.key, required this.position});

  final SavingsPosition position;

  @override
  State<SavingsWithdrawSheet> createState() => _SavingsWithdrawSheetState();
}

class _SavingsWithdrawSheetState extends State<SavingsWithdrawSheet> {
  _WithdrawStage _stage = _WithdrawStage.confirm;

  String _pinDigits = '';
  String? _pinError;
  String? _errorMessage;

  // Amount the user will receive: principal + net yield
  double get _receiveAmount =>
      widget.position.principalUsd + widget.position.netYieldUsd;

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
      _submitWithdraw();
    }
  }

  Future<void> _submitWithdraw() async {
    setState(() => _stage = _WithdrawStage.processing);

    try {
      final model = ZendScope.of(context);
      final savingsService = model.savingsService;
      final walletService = model.walletService;

      // Step 1: prepare — backend loads ALTs, builds v0 tx with fee instruction
      final prepare = await savingsService.prepareWithdraw();

      // Step 2: sign on-device with PIN
      final signedTx = await walletService.signExistingTransaction(
        pin: _pinDigits,
        txBytesB64: prepare.txBytesB64,
      );

      // Step 3: submit — backend co-signs as fee payer and broadcasts
      await savingsService.submitWithdraw(signedTx);

      // Refresh balance and savings snapshot
      unawaited(model.fetchBalance());
      unawaited(model.fetchSavingsSnapshot());

      if (!mounted) return;
      setState(() => _stage = _WithdrawStage.success);
      HapticFeedback.mediumImpact();
    } on PinDecryptionException {
      if (!mounted) return;
      setState(() {
        _pinDigits = '';
        _pinError = 'Incorrect PIN';
        _stage = _WithdrawStage.pin;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = _WithdrawStage.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = _WithdrawStage.error;
      });
    }
  }

  double get _heightFactor => switch (_stage) {
        _WithdrawStage.confirm => 0.60,
        _WithdrawStage.pin => 0.70,
        _WithdrawStage.processing => 0.45,
        _WithdrawStage.success => 0.50,
        _WithdrawStage.error => 0.55,
      };

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _stage != _WithdrawStage.processing,
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
      _WithdrawStage.confirm => _ConfirmStage(
          position: widget.position,
          receiveAmount: _receiveAmount,
          onConfirm: () => setState(() => _stage = _WithdrawStage.pin),
        ),
      _WithdrawStage.pin => _PinStage(
          receiveAmount: _receiveAmount,
          pinDigits: _pinDigits,
          pinError: _pinError,
          onKey: _onPinKey,
          onBack: () => setState(() {
            _pinDigits = '';
            _pinError = null;
            _stage = _WithdrawStage.confirm;
          }),
        ),
      _WithdrawStage.processing => const _ProcessingStage(),
      _WithdrawStage.success => _SuccessStage(
          receiveAmount: _receiveAmount,
          onDone: () => Navigator.of(context).pop(),
        ),
      _WithdrawStage.error => _ErrorStage(
          message: _errorMessage ?? 'Something went wrong.',
          onRetry: () => setState(() {
            _pinDigits = '';
            _pinError = null;
            _stage = _WithdrawStage.pin;
          }),
          onCancel: () => Navigator.of(context).pop(),
        ),
    };
  }
}

// ── Confirm stage ─────────────────────────────────────────────────────────────

class _ConfirmStage extends StatelessWidget {
  const _ConfirmStage({
    required this.position,
    required this.receiveAmount,
    required this.onConfirm,
  });

  final SavingsPosition position;
  final double receiveAmount;
  final VoidCallback onConfirm;

  String _fmt(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cash out',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: ZendColors.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.lg),

          // ── Breakdown rows ─────────────────────────────────────────
          _BreakdownRow(
            label: 'Saved',
            value: _fmt(position.principalUsd),
          ),
          const Divider(color: ZendColors.border, height: 24),
          _BreakdownRow(
            label: 'Money earned',
            value: _fmt(position.grossYieldUsd),
            valueColor: ZendColors.accentBright,
          ),
          const SizedBox(height: ZendSpacing.xs),
          _BreakdownRow(
            label: 'ZendFi fee (${(position.feeBps / 100).toStringAsFixed(0)}%)',
            value: '−${_fmt(position.feeUsd)}',
            valueColor: ZendColors.textSecondary,
            labelStyle: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: ZendColors.textSecondary,
            ),
          ),
          const Divider(color: ZendColors.border, height: 24),
          _BreakdownRow(
            label: "You'll receive",
            value: _fmt(receiveAmount),
            bold: true,
          ),

          const Spacer(),

          PrimaryButton(
            label: 'Confirm withdrawal',
            onPressed: onConfirm,
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
    this.labelStyle,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: labelStyle ??
              TextStyle(
                fontFamily: 'DMSans',
                fontSize: bold ? 15 : 14,
                fontWeight:
                    bold ? FontWeight.w600 : FontWeight.w400,
                color: ZendColors.textPrimary,
              ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'DMMono',
            fontSize: bold ? 15 : 14,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            color: valueColor ?? ZendColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── PIN stage ─────────────────────────────────────────────────────────────────

class _PinStage extends StatelessWidget {
  const _PinStage({
    required this.receiveAmount,
    required this.pinDigits,
    required this.pinError,
    required this.onKey,
    required this.onBack,
  });

  final double receiveAmount;
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
            'Cash out \$${receiveAmount.toStringAsFixed(2)}',
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
  const _ProcessingStage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor:
                AlwaysStoppedAnimation<Color>(ZendColors.accentBright),
          ),
          SizedBox(height: 20),
          Text(
            'Cashing out...',
            textAlign: TextAlign.center,
            style: TextStyle(
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
  const _SuccessStage({required this.receiveAmount, required this.onDone});
  final double receiveAmount;
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
              'Cashed out! 💸',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 32,
                color: ZendColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You received \$${receiveAmount.toStringAsFixed(2)}',
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
