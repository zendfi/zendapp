import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'bank_send_sheet.dart';
import 'crypto_send_sheet.dart';
import 'package:solar_icons/solar_icons.dart';

Future<void> showWithdrawSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => const WithdrawSheet(),
  );
}

enum _WithdrawStage { amount, destination }

class WithdrawSheet extends StatefulWidget {
  const WithdrawSheet({super.key});

  @override
  State<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<WithdrawSheet> {
  _WithdrawStage _stage = _WithdrawStage.amount;
  String _digits = '';

  static const Duration _sheetResize = Duration(milliseconds: 220);

  static const double _minWithdrawUsdc = 5.0;

  double get _parsedAmount =>
      _digits.isEmpty ? 0 : (double.tryParse(_digits) ?? 0);

  bool get _insufficientBalance {
    final model = ZendScope.of(context);
    return _parsedAmount > 0 && _parsedAmount > model.balance;
  }

  bool get _belowMinimum => _parsedAmount > 0 && _parsedAmount < _minWithdrawUsdc;

  bool get _canContinue {
    final model = ZendScope.of(context);
    return _parsedAmount >= _minWithdrawUsdc && _parsedAmount <= model.balance;
  }

  String get _amountFormatted {
    if (_parsedAmount == _parsedAmount.roundToDouble()) {
      return '\$${_parsedAmount.toStringAsFixed(0)}';
    }
    return '\$${_parsedAmount.toStringAsFixed(2)}';
  }

  void _onKey(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      if (value == 'del') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
      } else if (value == '.') {
        if (!_digits.contains('.')) {
          _digits = _digits.isEmpty ? '0.' : '$_digits.';
        }
      } else if (RegExp(r'[0-9]').hasMatch(value)) {
        if (_digits.contains('.')) {
          final parts = _digits.split('.');
          if (parts.length == 2 && parts[1].length >= 2) return;
        }
        if (_digits == '0') {
          if (value == '0') return;
          _digits = value;
        } else {
          _digits += value;
        }
      }
    });
  }

  double get _sheetHeightFraction =>
      _stage == _WithdrawStage.amount ? 1.0 : 0.55;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return AnimatedContainer(
      duration: _sheetResize,
      curve: Curves.easeOutCubic,
      height: screenHeight * _sheetHeightFraction,
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
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _stage == _WithdrawStage.amount
                  ? _AmountStage(
                      key: const ValueKey('amount'),
                      digits: _digits,
                      parsedAmount: _parsedAmount,
                      amountFormatted: _amountFormatted,
                      insufficientBalance: _insufficientBalance,
                      belowMinimum: _belowMinimum,
                      canContinue: _canContinue,
                      onKey: _onKey,
                      onContinue: () =>
                          setState(() => _stage = _WithdrawStage.destination),
                    )
                  : _DestinationStage(
                      key: const ValueKey('destination'),
                      amount: _parsedAmount,
                      amountFormatted: _amountFormatted,
                      onBack: () =>
                          setState(() => _stage = _WithdrawStage.amount),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Amount stage ──────────────────────────────────────────────────────────────

class _AmountStage extends StatelessWidget {
  const _AmountStage({
    super.key,
    required this.digits,
    required this.parsedAmount,
    required this.amountFormatted,
    required this.insufficientBalance,
    required this.belowMinimum,
    required this.canContinue,
    required this.onKey,
    required this.onContinue,
  });

  final String digits;
  final double parsedAmount;
  final String amountFormatted;
  final bool insufficientBalance;
  final bool belowMinimum;
  final bool canContinue;
  final ValueChanged<String> onKey;
  final VoidCallback onContinue;

  String get _wholePart {
    if (digits.isEmpty) return '0';
    if (digits.contains('.')) return digits.split('.')[0];
    return digits;
  }

  String? get _decimalPart {
    if (!digits.contains('.')) return null;
    final parts = digits.split('.');
    return parts.length > 1 ? parts[1] : '';
  }

  bool get _hasDecimal => digits.contains('.');

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final zt = ZendTheme.of(context);
    final compact = MediaQuery.of(context).size.height < 760;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'Withdraw',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Balance: \$${model.balance.toStringAsFixed(2)}',
            style: TextStyle(
              fontFamily: 'DMMono',
              fontSize: 12,
              color: insufficientBalance
                  ? ZendColors.destructive
                  : zt.textSecondary,
            ),
          ),
          // Fixed-height status row — never shifts the layout regardless of
          // whether an error is shown or not.
          SizedBox(
            height: 20,
            child: insufficientBalance
                ? Text(
                    'Amount exceeds your balance',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 11,
                      color: ZendColors.destructive,
                    ),
                  )
                : belowMinimum
                    ? Text(
                        'Minimum withdrawal is \$5.00',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 11,
                          color: ZendColors.destructive,
                        ),
                      )
                    : null,
          ),
          const Spacer(),

          // ── Amount display ──────────────────────────────────────────
          _WithdrawAmountDisplay(
            wholePart: _wholePart,
            decimalPart: _decimalPart,
            hasDecimal: _hasDecimal,
            compact: compact,
          ),

          const Spacer(),

          // ── Keypad ──────────────────────────────────────────────────
          _WithdrawKeypad(
            onTap: onKey,
            keyHeight: compact ? 60 : 72,
          ),

          const SizedBox(height: 20),

          // ── Continue button ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: canContinue
                  ? 'Continue'
                  : belowMinimum
                      ? 'Minimum \$5.00'
                      : 'Enter amount',
              onPressed: canContinue ? onContinue : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Destination stage ─────────────────────────────────────────────────────────

class _DestinationStage extends StatelessWidget {
  const _DestinationStage({
    super.key,
    required this.amount,
    required this.amountFormatted,
    required this.onBack,
  });

  final double amount;
  final String amountFormatted;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Withdraw $amountFormatted to',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 24),

          // ── Bank option ─────────────────────────────────────────────
          _DestinationTile(
            icon: SolarIconsBold.banknote,
            title: 'Bank account',
            subtitle: 'Nigeria, UK, USA, Europe',
            onTap: () {
              Navigator.of(context).pop();
              showBankSendSheet(context, amount: amount);
            },
          ),
          const SizedBox(height: 12),

          // ── Blockchain option ───────────────────────────────────────
          _DestinationTile(
            icon: SolarIconsBold.dollar,
            title: 'Crypto wallet',
            subtitle: 'Any chain — Tron, Ethereum, BNB...',
            onTap: () {
              Navigator.of(context).pop();
              showCryptoSendSheet(context, amount: amount);
            },
          ),
        ],
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: zt.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: zt.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: zt.textPrimary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: zt.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      color: zt.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(SolarIconsBold.altArrowRight, size: 18, color: zt.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ── Amount display ────────────────────────────────────────────────────────────

class _WithdrawAmountDisplay extends StatelessWidget {
  const _WithdrawAmountDisplay({
    required this.wholePart,
    required this.decimalPart,
    required this.hasDecimal,
    required this.compact,
  });

  final String wholePart;
  final String? decimalPart;
  final bool hasDecimal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final wholeSize = compact ? 64.0 : 76.0;
    final decSize = compact ? 26.0 : 30.0;

    final wholeStyle = TextStyle(
      fontFamily: 'InstrumentSerif',
      color: zt.textPrimary,
      fontSize: wholeSize,
      fontStyle: FontStyle.italic,
      height: 1.0,
    );

    final currencyStyle = TextStyle(
      fontFamily: 'InstrumentSerif',
      color: zt.textSecondary,
      fontSize: wholeSize * 0.5,
      fontStyle: FontStyle.italic,
      height: 1.0,
    );

    final decStyle = TextStyle(
      fontFamily: 'InstrumentSerif',
      color: zt.textSecondary,
      fontSize: decSize,
      fontStyle: FontStyle.italic,
      height: 1.0,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: wholeSize * 0.08),
          child: Text('\$', style: currencyStyle),
        ),
        Text(wholePart.isEmpty ? '0' : wholePart, style: wholeStyle),
        if (hasDecimal) ...[
          const SizedBox(width: 2),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('.', style: decStyle),
                  Text(
                    decimalPart == null || decimalPart!.isEmpty
                        ? '—'
                        : decimalPart!,
                    style: decStyle,
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Keypad ────────────────────────────────────────────────────────────────────

class _WithdrawKeypad extends StatelessWidget {
  const _WithdrawKeypad({required this.onTap, required this.keyHeight});

  final ValueChanged<String> onTap;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    const keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '.', '0', 'del',
    ];

    return Column(
      children: [
        for (var row = 0; row < 4; row++)
          Row(
            children: [
              for (var col = 0; col < 3; col++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: col == 2 ? 0 : 8,
                      bottom: row == 3 ? 0 : 8,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(keys[row * 3 + col]),
                      child: SizedBox(
                        height: keyHeight,
                        child: Center(
                          child: keys[row * 3 + col] == 'del'
                              ? ZendBackspaceIcon(
                                  color: zt.textPrimary,
                                  size: 22,
                                )
                              : Text(
                                  keys[row * 3 + col],
                                  style: TextStyle(
                                    fontFamily: 'DMSans',
                                    fontSize: 22,
                                    color: zt.textPrimary,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
