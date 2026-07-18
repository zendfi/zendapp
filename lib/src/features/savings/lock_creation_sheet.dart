import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/pocket_models.dart';
import 'package:solar_icons/solar_icons.dart';

enum _LockStage { amountDate, confirm }

class LockCreationSheet extends StatefulWidget {
  const LockCreationSheet({super.key, required this.freePocketBalance});

  final double freePocketBalance;

  @override
  State<LockCreationSheet> createState() => _LockCreationSheetState();
}

class _LockCreationSheetState extends State<LockCreationSheet> {
  _LockStage _stage = _LockStage.amountDate;

  String _amountInput = '';
  String? _amountError;
  DateTime? _unlockDate;
  String? _dateError;

  String _pinDigits = '';
  String? _pinError;
  String? _errorMessage;
  bool _processing = false;

  double get _parsedAmount {
    if (_amountInput.isEmpty) return 0.0;
    return double.tryParse(_amountInput) ?? 0.0;
  }

  bool get _amountValid =>
      _parsedAmount >= 1.0 && _parsedAmount <= widget.freePocketBalance;

  bool get _dateValid {
    final d = _unlockDate;
    if (d == null) return false;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return d.isAfter(tomorrow) ||
        (d.year == tomorrow.year &&
            d.month == tomorrow.month &&
            d.day == tomorrow.day);
  }

  bool get _canContinue => _amountValid && _dateValid;

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
      _submitLock();
    }
  }

  Future<void> _pickUnlockDate() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _unlockDate ?? tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() {
        _unlockDate = picked;
        _dateError = null;
      });
    }
  }

  Future<void> _submitLock() async {
    setState(() => _processing = true);

    try {
      final model = ZendScope.of(context);

      // Verify PIN before creating lock
      await model.walletService.verifyLocalPin(_pinDigits);

      final req = CreateLockRequest(
        amountUsd: _parsedAmount,
        unlockDate: _unlockDate!.toIso8601String().split('T').first,
      );

      final pocket = await model.pocketService.createLock(req);

      if (!mounted) return;
      Navigator.of(context).pop(pocket);
    } on PinDecryptionException {
      if (!mounted) return;
      setState(() {
        _pinDigits = '';
        _pinError = 'Incorrect PIN';
        _processing = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _processing = false;
        _pinDigits = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _processing = false;
        _pinDigits = '';
      });
    }
  }

  double get _heightFactor => switch (_stage) {
        _LockStage.amountDate => 0.82,
        _LockStage.confirm => 0.70,
      };

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: !_processing,
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
    if (_processing) {
      return const Center(
        child: ZendLoader(color: ZendColors.accentBright),
      );
    }

    return switch (_stage) {
      _LockStage.amountDate => _AmountDateStage(
          amountInput: _amountInput,
          amountError: _amountError,
          unlockDate: _unlockDate,
          dateError: _dateError,
          freePocketBalance: widget.freePocketBalance,
          canContinue: _canContinue,
          onKey: _onAmountKey,
          onPickDate: _pickUnlockDate,
          onContinue: () {
            if (!_amountValid) {
              setState(() {
                if (_parsedAmount <= 0) {
                  _amountError = 'Enter an amount to lock';
                } else if (_parsedAmount > widget.freePocketBalance) {
                  _amountError =
                      'Not enough in Stash (\$${widget.freePocketBalance.toStringAsFixed(2)})';
                }
              });
              return;
            }
            if (!_dateValid) {
              setState(() => _dateError = 'Pick an unlock date (minimum tomorrow)');
              return;
            }
            setState(() => _stage = _LockStage.confirm);
          },
        ),
      _LockStage.confirm => _ConfirmStage(
          amountUsd: _parsedAmount,
          unlockDate: _unlockDate!,
          pinDigits: _pinDigits,
          pinError: _pinError,
          errorMessage: _errorMessage,
          onKey: _onPinKey,
          onBack: () => setState(() {
            _pinDigits = '';
            _pinError = null;
            _errorMessage = null;
            _stage = _LockStage.amountDate;
          }),
        ),
    };
  }
}

// ── Stage 1: Amount + Date ────────────────────────────────────────────────────

class _AmountDateStage extends StatelessWidget {
  const _AmountDateStage({
    required this.amountInput,
    required this.amountError,
    required this.unlockDate,
    required this.dateError,
    required this.freePocketBalance,
    required this.canContinue,
    required this.onKey,
    required this.onPickDate,
    required this.onContinue,
  });

  final String amountInput;
  final String? amountError;
  final DateTime? unlockDate;
  final String? dateError;
  final double freePocketBalance;
  final bool canContinue;
  final ValueChanged<String> onKey;
  final VoidCallback onPickDate;
  final VoidCallback onContinue;

  String get _displayAmount =>
      amountInput.isEmpty ? '\$0' : '\$$amountInput';

  String _formatDate(DateTime d) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Lock savings',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: ZendSpacing.xxs),
          Text(
            'Moving from Stash · Available: \$${freePocketBalance.toStringAsFixed(2)}',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: zt.textSecondary,
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
          if (amountError != null)
            Center(
              child: Text(
                amountError!,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: ZendColors.destructive,
                ),
              ),
            ),
          const SizedBox(height: ZendSpacing.sm),

          // ── Date picker ───────────────────────────────────────────
          GestureDetector(
            onTap: onPickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: ZendSpacing.md, vertical: ZendSpacing.sm),
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(ZendRadii.md),
                border: dateError != null
                    ? Border.all(color: ZendColors.destructive)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(SolarIconsBold.calendar,
                      size: 16, color: zt.textSecondary),
                  const SizedBox(width: ZendSpacing.xs),
                  Expanded(
                    child: Text(
                      unlockDate != null
                          ? 'Unlock on ${_formatDate(unlockDate!)}'
                          : 'Pick unlock date',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        color: unlockDate != null
                            ? zt.textPrimary
                            : zt.textSecondary,
                      ),
                    ),
                  ),
                  Icon(SolarIconsBold.altArrowRight, size: 18, color: zt.textSecondary),
                ],
              ),
            ),
          ),
          if (dateError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                dateError!,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 12,
                  color: ZendColors.destructive,
                ),
              ),
            ),

          const Spacer(),
          _NumericKeypad(onKey: onKey),
          const SizedBox(height: ZendSpacing.md),
          PrimaryButton(
            label: 'Continue',
            onPressed: canContinue ? onContinue : null,
          ),
        ],
      ),
    );
  }
}

// ── Stage 2: Confirm + PIN ────────────────────────────────────────────────────

class _ConfirmStage extends StatelessWidget {
  const _ConfirmStage({
    required this.amountUsd,
    required this.unlockDate,
    required this.pinDigits,
    required this.pinError,
    required this.errorMessage,
    required this.onKey,
    required this.onBack,
  });

  final double amountUsd;
  final DateTime unlockDate;
  final String pinDigits;
  final String? pinError;
  final String? errorMessage;
  final ValueChanged<String> onKey;
  final VoidCallback onBack;

  String _formatDate(DateTime d) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

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

          // ── Summary ───────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(ZendSpacing.md),
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: BorderRadius.circular(ZendRadii.xl),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(SolarIconsBold.lockKeyhole,
                        size: 18, color: ZendColors.accentBright),
                    const SizedBox(width: ZendSpacing.xs),
                    Text(
                      'Locking \$${amountUsd.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: zt.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZendSpacing.xs),
                Text(
                  'Moving from Stash · Locked until ${_formatDate(unlockDate)}',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZendSpacing.xl),

          // ── PIN dots ──────────────────────────────────────────────
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
            errorMessage ?? pinError ?? 'Confirm with your PIN',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: (pinError != null || errorMessage != null)
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
