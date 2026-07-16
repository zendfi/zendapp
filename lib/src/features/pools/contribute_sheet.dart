import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/signing_policy_service.dart';
import '../../services/wallet_session_cache.dart';
import 'pool.dart';
import 'pool_progress_bar.dart';
import 'package:solar_icons/solar_icons.dart';

Future<void> showContributeSheet(
  BuildContext context, {
  required Pool pool,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ContributeSheet(pool: pool),
  );
}

enum _ContributeStage { amount, pin, processing, success, error }

class ContributeSheet extends StatefulWidget {
  const ContributeSheet({super.key, required this.pool});
  final Pool pool;

  @override
  State<ContributeSheet> createState() => _ContributeSheetState();
}

class _ContributeSheetState extends State<ContributeSheet> {
  _ContributeStage _stage = _ContributeStage.amount;

  String _amountInput = '';
  String? _amountError;

  String _pinDigits = '';
  String? _pinError;

  String? _errorMessage;

  double get _parsedAmount {
    if (_amountInput.isEmpty) return 0.0;
    return double.tryParse(_amountInput) ?? 0.0;
  }

  /// How much the pool still needs to reach its target.
  double get _remainingAmount {
    final rem = widget.pool.targetAmount - widget.pool.gathered;
    return rem < 0 ? 0.0 : rem;
  }

  bool get _amountValid =>
      _parsedAmount >= 0.01 &&
      _parsedAmount <= 10000.0 &&
      _parsedAmount <= _remainingAmount;

  double get _userBalance {
    try {
      return ZendScope.of(context).spendableBalance;
    } catch (_) {
      return 0.0;
    }
  }

  bool get _hasSufficientBalance => _parsedAmount <= _userBalance;

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

      // Build the candidate value and cap it at the remaining pool amount.
      final candidate = _amountInput + key;
      final candidateValue = double.tryParse(candidate) ?? 0.0;
      final cap = _remainingAmount;
      if (cap > 0 && candidateValue > cap) {
        // Snap to the exact remaining amount and show a hint.
        _amountInput = cap.toStringAsFixed(2);
        _amountError = 'Max contribution is \$${cap.toStringAsFixed(2)}';
        return;
      }

      _amountInput += key;
    });
  }

  void _onAmountConfirm() {
    if (_remainingAmount <= 0) {
      setState(() => _amountError = 'This pool is already full');
      return;
    }
    if (!_amountValid) {
      setState(() => _amountError =
          'Enter an amount between \$0.01 and \$${_remainingAmount.toStringAsFixed(2)}');
      return;
    }
    if (!_hasSufficientBalance) {
      setState(() => _amountError = 'Insufficient balance');
      return;
    }
    _proceedFromAmount();
  }

  Future<void> _proceedFromAmount() async {
    final policy = SigningPolicyService();
    final cache = WalletSessionCache.instance;
    final needsPin = await policy.requiresPinForAmount(_parsedAmount);

    if (!needsPin && cache.hasKeypair) {
      setState(() => _stage = _ContributeStage.processing);
      await _executeContribution(pin: null, keypairBytes: cache.keypair);
    } else {
      setState(() => _stage = _ContributeStage.pin);
    }
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
      if (_pinDigits.length >= 6) return;
      _pinDigits += key;
    });
    if (_pinDigits.length == 6) {
      _submitContribution();
    }
  }

  Future<void> _submitContribution() async {
    final pin = _pinDigits;
    setState(() => _stage = _ContributeStage.processing);

    try {
      final model = ZendScope.of(context);
      final cache = WalletSessionCache.instance;

      if (cache.hasKeypair) {
        final valid = await model.signingPolicyService.verifyPinAgainstCache(pin, model.walletService);
        if (!valid) {
          if (!mounted) return;
          setState(() {
            _pinDigits = '';
            _pinError = 'Incorrect PIN';
            _stage = _ContributeStage.pin;
          });
          return;
        }
        await _executeContribution(pin: null, keypairBytes: cache.keypair);
      } else {
        await _executeContribution(pin: pin, keypairBytes: null);
      }
    } on PinDecryptionException {
      if (!mounted) return;
      setState(() {
        _pinDigits = '';
        _pinError = 'Incorrect PIN';
        _stage = _ContributeStage.pin;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = _ContributeStage.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = _ContributeStage.error;
      });
    }
  }

  Future<void> _executeContribution({String? pin, dynamic keypairBytes}) async {
    try {
      final model = ZendScope.of(context);
      final apiClient = model.walletService.apiClient;

      final prepare = await apiClient.prepareContribution(
        poolId: widget.pool.id,
        amountUsdc: _parsedAmount,
      );

      final String signedTx;
      if (keypairBytes != null) {
        signedTx = await model.walletService.buildAndSignTransactionFromCache(
          keypairBytes: keypairBytes,
          amountUsdc: _parsedAmount,
          recipientAddress: prepare.recipientWalletAddress,
          blockhash: prepare.blockhash,
          feePayerAddress: prepare.feePayer,
        );
      } else {
        signedTx = await model.walletService.buildAndSignTransaction(
          pin: pin!,
          amountUsdc: _parsedAmount,
          recipientAddress: prepare.recipientWalletAddress,
          blockhash: prepare.blockhash,
          feePayerAddress: prepare.feePayer,
        );
      }

      await apiClient.submitContribution(
        poolId: widget.pool.id,
        amountUsdc: _parsedAmount,
        partiallySignedTx: signedTx,
      );

      // Do not optimistically deduct balance — fetchBalance() is the source of truth
      unawaited(model.fetchBalance());

      if (!mounted) return;
      setState(() => _stage = _ContributeStage.success);
      HapticFeedback.mediumImpact();
    } on PinDecryptionException {
      rethrow;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = _ContributeStage.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = _ContributeStage.error;
      });
    }
  }


  double get _heightFactor => switch (_stage) {
        _ContributeStage.amount => 0.80,
        _ContributeStage.pin => 0.70,
        _ContributeStage.processing => 0.45,
        _ContributeStage.success => 0.50,
        _ContributeStage.error => 0.55,
      };

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenHeight = mq.size.height;

    return PopScope(
      canPop: _stage != _ContributeStage.processing,
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
      _ContributeStage.amount => _AmountStage(
          pool: widget.pool,
          amountInput: _amountInput,
          amountError: _amountError,
          userBalance: _userBalance,
          remainingAmount: _remainingAmount,
          hasSufficientBalance: _hasSufficientBalance,
          onKey: _onAmountKey,
          onConfirm: _onAmountConfirm,
        ),
      _ContributeStage.pin => _PinStage(
          pool: widget.pool,
          amount: _parsedAmount,
          pinDigits: _pinDigits,
          pinError: _pinError,
          onKey: _onPinKey,
          onBack: () => setState(() {
            _pinDigits = '';
            _pinError = null;
            _stage = _ContributeStage.amount;
          }),
        ),
      _ContributeStage.processing => _ProcessingStage(
          pool: widget.pool,
          amount: _parsedAmount,
        ),
      _ContributeStage.success => _SuccessStage(
          pool: widget.pool,
          amount: _parsedAmount,
          onDone: () => Navigator.of(context).pop(),
        ),
      _ContributeStage.error => _ErrorStage(
          message: _errorMessage ?? 'Something went wrong.',
          onRetry: () {
            setState(() {
              _pinDigits = '';
              _pinError = null;
              _errorMessage = null;
            });
            _proceedFromAmount();
          },
          onCancel: () => Navigator.of(context).pop(),
        ),
    };
  }
}

class _AmountStage extends StatelessWidget {
  const _AmountStage({
    required this.pool,
    required this.amountInput,
    required this.amountError,
    required this.userBalance,
    required this.remainingAmount,
    required this.hasSufficientBalance,
    required this.onKey,
    required this.onConfirm,
  });

  final Pool pool;
  final String amountInput;
  final String? amountError;
  final double userBalance;
  final double remainingAmount;
  final bool hasSufficientBalance;
  final ValueChanged<String> onKey;
  final VoidCallback onConfirm;

  String get _displayAmount =>
      amountInput.isEmpty ? '\$0' : '\$$amountInput';

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final parsedAmount = double.tryParse(amountInput) ?? 0.0;
    final isValid = parsedAmount >= 0.01 &&
        hasSufficientBalance &&
        (remainingAmount <= 0 ? false : parsedAmount <= remainingAmount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pool.name,
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xs),
          PoolProgressBar(progress: pool.progress, style: PoolProgressBarStyle.circle, circleSize: 90, strokeWidth: 8),
          const SizedBox(height: ZendSpacing.xxs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${pool.formattedGathered} of ${pool.formattedTarget}',
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 12,
                  color: zt.textSecondary,
                ),
              ),
              if (remainingAmount > 0)
                Text(
                  '\$${remainingAmount.toStringAsFixed(2)} left',
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 12,
                    color: zt.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: ZendSpacing.lg),

          Center(
            child: Text(
              _displayAmount,
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 48,
                fontWeight: FontWeight.w700,
                color: zt.textPrimary,
              ),
            ),
          ),

          Center(
            child: Text(
              amountError ??
                  'Balance: \$${userBalance.toStringAsFixed(2)}',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: amountError != null
                    ? ZendColors.destructive
                    : zt.textSecondary,
              ),
            ),
          ),
          const Spacer(),

          _NumericKeypad(onKey: onKey),
          const SizedBox(height: ZendSpacing.md),

          PrimaryButton(
            label: 'Contribute $_displayAmount',
            onPressed: isValid ? onConfirm : null,
          ),
        ],
      ),
    );
  }
}

class _PinStage extends StatelessWidget {
  const _PinStage({
    required this.pool,
    required this.amount,
    required this.pinDigits,
    required this.pinError,
    required this.onKey,
    required this.onBack,
  });

  final Pool pool;
  final double amount;
  final String pinDigits;
  final String? pinError;
  final ValueChanged<String> onKey;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Contribute \$${amount.toStringAsFixed(2)} to ${pool.name}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              final filled = i < pinDigits.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? zt.accent : Colors.transparent,
                  border: Border.all(color: filled ? zt.accent : zt.border),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            pinError ?? 'Enter your PIN',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: pinError != null ? ZendColors.destructive : zt.textSecondary,
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

class _ProcessingStage extends StatelessWidget {
  const _ProcessingStage({required this.pool, required this.amount});
  final Pool pool;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZendLoader(color: zt.accentBright),
          const SizedBox(height: 20),
          Text(
            'Contributing \$${amount.toStringAsFixed(2)} to ${pool.name}...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: zt.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessStage extends StatelessWidget {
  const _SuccessStage({
    required this.pool,
    required this.amount,
    required this.onDone,
  });
  final Pool pool;
  final double amount;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
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
              child: const Icon(SolarIconsBold.checkCircle, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'Contributed! 🔥',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 32,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${amount.toStringAsFixed(2)} added to ${pool.name}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: zt.textSecondary,
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
    final zt = ZendTheme.of(context);
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
              child: const Icon(SolarIconsBold.closeCircle, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: zt.textSecondary,
                      side: BorderSide(color: zt.border),
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
    final zt = ZendTheme.of(context);
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
                      ? ZendBackspaceIcon(color: zt.textPrimary, size: 20)
                      : Text(
                          key,
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: zt.textPrimary,
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
