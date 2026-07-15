import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/savings_models.dart';
import '../../services/signing_policy_service.dart';
import '../../services/wallet_session_cache.dart';

enum _WithdrawStage { confirm, amount, pin, processing, success, error }

class SavingsWithdrawSheet extends StatefulWidget {
  const SavingsWithdrawSheet({
    super.key,
    // Legacy constructor param — kept for backward compatibility
    this.position,
    // New pocket-aware params
    this.pocketId,
    this.availableAmount,
    this.pocketType,
    this.lockUnlockDate,
    this.isGoalLocked = false,
  });

  /// Legacy: full position for old-style full withdrawal.
  final SavingsPosition? position;

  /// Pocket ID to withdraw from.
  final String? pocketId;

  /// Maximum withdrawable amount.
  final double? availableAmount;

  /// "free" | "goal" | "lock"
  final String? pocketType;

  /// For lock pockets — the unlock date string.
  final String? lockUnlockDate;

  /// For strict goals — whether withdrawal is currently blocked.
  final bool isGoalLocked;

  @override
  State<SavingsWithdrawSheet> createState() => _SavingsWithdrawSheetState();
}

class _SavingsWithdrawSheetState extends State<SavingsWithdrawSheet> {
  _WithdrawStage _stage = _WithdrawStage.confirm;

  // For free pocket partial withdrawal
  String _amountInput = '';
  String? _amountError;

  String _pinDigits = '';
  String? _pinError;
  String? _errorMessage;

  bool get _isFree => widget.pocketType == 'free';
  bool get _isGoal => widget.pocketType == 'goal';
  bool get _isLock => widget.pocketType == 'lock';
  bool get _isLegacy => widget.position != null && widget.pocketId == null;

  double get _availableAmount =>
      widget.availableAmount ?? widget.position?.currentValueUsd ?? 0.0;

  double get _parsedAmount {
    if (_isFree) {
      if (_amountInput.isEmpty) return 0.0;
      return double.tryParse(_amountInput) ?? 0.0;
    }
    return _availableAmount;
  }

  bool get _amountValid =>
      _parsedAmount > 0 && _parsedAmount <= _availableAmount;

  // Amount the user will receive (legacy mode)
  double get _receiveAmount =>
      widget.position != null
          ? widget.position!.principalUsd + widget.position!.netYieldUsd
          : _availableAmount;

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
      _submitWithdraw();
    }
  }

  Future<void> _proceedFromConfirm() async {
    final policy = SigningPolicyService();
    final cache = WalletSessionCache.instance;
    final needsPin = await policy.requiresPinForAmount(_parsedAmount);

    if (!needsPin && cache.hasKeypair) {
      setState(() => _stage = _WithdrawStage.processing);
      await _executeWithdraw(pin: null, keypairBytes: cache.keypair);
    } else {
      setState(() => _stage = _WithdrawStage.pin);
    }
  }

  Future<void> _submitWithdraw() async {
    final pin = _pinDigits;
    setState(() => _stage = _WithdrawStage.processing);

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
            _stage = _WithdrawStage.pin;
          });
          return;
        }
        await _executeWithdraw(pin: null, keypairBytes: cache.keypair);
      } else {
        await _executeWithdraw(pin: pin, keypairBytes: null);
      }
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

  Future<void> _executeWithdraw({String? pin, dynamic keypairBytes}) async {
    try {
      final model = ZendScope.of(context);
      final walletService = model.walletService;

      Future<String> signTx(String txBytesB64) {
        if (keypairBytes != null) {
          return walletService.signExistingTransactionFromCache(
            keypairBytes: keypairBytes,
            txBytesB64: txBytesB64,
          );
        }
        return walletService.signExistingTransaction(
          pin: pin!,
          txBytesB64: txBytesB64,
        );
      }

      if (_isLegacy) {
        final savingsService = model.savingsService;
        final prepare = await savingsService.prepareWithdraw();
        final signedTx = await signTx(prepare.txBytesB64);
        await savingsService.submitWithdraw(signedTx);
      } else if (_isFree) {
        final pocketService = model.pocketService;
        final prepare = await pocketService.prepareFreeWithdraw(_parsedAmount);
        final signedTx = await signTx(prepare.txBytesB64);
        await pocketService.submitFreeWithdraw(signedTx);
      } else if (_isGoal) {
        final pocketService = model.pocketService;
        final prepare = await pocketService.prepareGoalWithdraw(widget.pocketId!);
        final signedTx = await signTx(prepare.txBytesB64);
        await pocketService.submitGoalWithdraw(widget.pocketId!, signedTx);
      } else if (_isLock) {
        final pocketService = model.pocketService;
        final prepare = await pocketService.prepareLockWithdraw();
        final signedTx = await signTx(prepare.txBytesB64);
        await pocketService.submitLockWithdraw(signedTx);
      }

      // Refresh balance and savings snapshot
      unawaited(model.fetchBalance());
      unawaited(model.fetchSavingsSnapshot());

      if (!mounted) return;
      setState(() => _stage = _WithdrawStage.success);
      HapticFeedback.mediumImpact();
    } on PinDecryptionException {
      rethrow;
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
        _WithdrawStage.amount => 0.82,
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
    // If goal is locked, show explanation instead of PIN
    if (_stage == _WithdrawStage.confirm && _isGoal && widget.isGoalLocked) {
      return _GoalLockedStage(
        onClose: () => Navigator.of(context).pop(),
      );
    }

    return switch (_stage) {
      _WithdrawStage.confirm => _isLegacy
          ? _ConfirmStage(
              position: widget.position!,
              receiveAmount: _receiveAmount,
              onConfirm: _proceedFromConfirm,
            )
          : _isFree
              ? _FreeConfirmStage(
                  availableAmount: _availableAmount,
                  onConfirm: () => setState(() => _stage = _WithdrawStage.amount),
                )
              : _isGoal
                  ? _GoalConfirmStage(
                      availableAmount: _availableAmount,
                      mode: 'flexible',
                      onConfirm: _proceedFromConfirm,
                    )
                  : _LockConfirmStage(
                      availableAmount: _availableAmount,
                      lockUnlockDate: widget.lockUnlockDate,
                      onConfirm: _proceedFromConfirm,
                    ),
      _WithdrawStage.amount => _FreeAmountStage(
          amountInput: _amountInput,
          amountError: _amountError,
          availableAmount: _availableAmount,
          amountValid: _amountValid,
          onKey: _onAmountKey,
          onConfirm: () {
            if (!_amountValid) {
              setState(() {
                if (_parsedAmount <= 0) {
                  _amountError = 'Enter an amount';
                } else {
                  _amountError =
                      'Not enough in Stash (\$${_availableAmount.toStringAsFixed(2)})';
                }
              });
              return;
            }
            _proceedFromConfirm();
          },
          onBack: () => setState(() => _stage = _WithdrawStage.confirm),
        ),
      _WithdrawStage.pin => _PinStage(
          receiveAmount: _parsedAmount > 0 ? _parsedAmount : _receiveAmount,
          pinDigits: _pinDigits,
          pinError: _pinError,
          onKey: _onPinKey,
          onBack: () => setState(() {
            _pinDigits = '';
            _pinError = null;
            _stage = _isFree ? _WithdrawStage.amount : _WithdrawStage.confirm;
          }),
        ),
      _WithdrawStage.processing => const _ProcessingStage(),
      _WithdrawStage.success => _SuccessStage(
          receiveAmount: _parsedAmount > 0 ? _parsedAmount : _receiveAmount,
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

// ── Goal locked stage ─────────────────────────────────────────────────────────

class _GoalLockedStage extends StatelessWidget {
  const _GoalLockedStage({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 48, color: ZendColors.accentBright),
            const SizedBox(height: ZendSpacing.md),
            Text(
              'Goal is locked',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: ZendSpacing.xs),
            Text(
              'This goal is set to Strict mode. Withdrawals are locked until you reach your target.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                height: 1.45,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: ZendSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: 'Got it', onPressed: onClose),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Free confirm stage ────────────────────────────────────────────────────────

class _FreeConfirmStage extends StatelessWidget {
  const _FreeConfirmStage({
    required this.availableAmount,
    required this.onConfirm,
  });
  final double availableAmount;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cash out',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.sm),
          Text(
            'Available: \$${availableAmount.toStringAsFixed(2)}',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              color: zt.textSecondary,
            ),
          ),
          const Spacer(),
          PrimaryButton(label: 'Enter amount', onPressed: onConfirm),
        ],
      ),
    );
  }
}

// ── Free amount stage ─────────────────────────────────────────────────────────

class _FreeAmountStage extends StatelessWidget {
  const _FreeAmountStage({
    required this.amountInput,
    required this.amountError,
    required this.availableAmount,
    required this.amountValid,
    required this.onKey,
    required this.onConfirm,
    required this.onBack,
  });

  final String amountInput;
  final String? amountError;
  final double availableAmount;
  final bool amountValid;
  final ValueChanged<String> onKey;
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  String get _displayAmount =>
      amountInput.isEmpty ? '\$0' : '\$$amountInput';

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: Icon(Icons.arrow_back, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Cash out',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
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
          const SizedBox(height: ZendSpacing.xs),
          Center(
            child: Text(
              amountError ?? 'Available: \$${availableAmount.toStringAsFixed(2)}',
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
            label: 'Cash out $_displayAmount',
            onPressed: amountValid ? onConfirm : null,
          ),
        ],
      ),
    );
  }
}

// ── Goal confirm stage ────────────────────────────────────────────────────────

class _GoalConfirmStage extends StatelessWidget {
  const _GoalConfirmStage({
    required this.availableAmount,
    required this.mode,
    required this.onConfirm,
  });
  final double availableAmount;
  final String mode;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Withdraw from goal',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.lg),
          _BreakdownRow(
            label: "You'll receive",
            value: '\$${availableAmount.toStringAsFixed(2)}',
            bold: true,
          ),
          const SizedBox(height: ZendSpacing.sm),
          Text(
            mode == 'flexible'
                ? 'Flexible goal — you can withdraw anytime.'
                : 'Goal target reached — withdrawal is now available.',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: zt.textSecondary,
            ),
          ),
          const Spacer(),
          PrimaryButton(label: 'Confirm withdrawal', onPressed: onConfirm),
        ],
      ),
    );
  }
}

// ── Lock confirm stage ────────────────────────────────────────────────────────

class _LockConfirmStage extends StatelessWidget {
  const _LockConfirmStage({
    required this.availableAmount,
    required this.lockUnlockDate,
    required this.onConfirm,
  });
  final double availableAmount;
  final String? lockUnlockDate;
  final VoidCallback onConfirm;

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr);
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Withdraw locked savings',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.lg),
          _BreakdownRow(
            label: "You'll receive",
            value: '\$${availableAmount.toStringAsFixed(2)}',
            bold: true,
          ),
          const SizedBox(height: ZendSpacing.sm),
          Text(
            lockUnlockDate != null
                ? 'Locked until ${_formatDate(lockUnlockDate)} — now unlocked.'
                : 'Your lock has expired and is ready to withdraw.',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: zt.textSecondary,
            ),
          ),
          const Spacer(),
          PrimaryButton(label: 'Confirm withdrawal', onPressed: onConfirm),
        ],
      ),
    );
  }
}

// ── Confirm stage (legacy) ────────────────────────────────────────────────────

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
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cash out',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.lg),

          // ── Breakdown rows ─────────────────────────────────────────
          _BreakdownRow(
            label: 'Saved',
            value: _fmt(position.principalUsd),
          ),
          Divider(color: zt.border, height: 24),
          _BreakdownRow(
            label: 'Money earned',
            value: _fmt(position.grossYieldUsd),
            valueColor: ZendColors.accentBright,
          ),
          const SizedBox(height: ZendSpacing.xs),
          _BreakdownRow(
            label: 'ZendFi fee (${(position.feeBps / 100).toStringAsFixed(0)}%)',
            value: '−${_fmt(position.feeUsd)}',
            valueColor: zt.textSecondary,
            labelStyle: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: zt.textSecondary,
            ),
          ),
          Divider(color: zt.border, height: 24),
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
    final zt = ZendTheme.of(context);
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
                color: zt.textPrimary,
              ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'DMMono',
            fontSize: bold ? 15 : 14,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            color: valueColor ?? zt.textPrimary,
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
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: Icon(Icons.arrow_back, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Cash out \$${receiveAmount.toStringAsFixed(2)}',
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
                  color: filled ? zt.textPrimary : zt.bgSecondary,
                  border: Border.all(color: zt.border),
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
                  : zt.textSecondary,
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZendLoader(color: ZendColors.accentBright),
          const SizedBox(height: 20),
          Text(
            'Cashing out...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: ZendTheme.of(context).textSecondary,
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
              child: const Icon(Icons.check, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'Cashed out! 💸',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 32,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You received \$${receiveAmount.toStringAsFixed(2)}',
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
              child: const Icon(Icons.close, color: Colors.white, size: 36),
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
