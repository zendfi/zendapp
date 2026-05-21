import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../design/zend_primitives.dart';
import '../../navigation/zend_routes.dart';
import '../pools/create_pool_drawer.dart';
import '../profile/profile_screen.dart';
import '../request/request_drawer_sheet.dart';

enum _InputMode { usd, ngn }

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.onOpenRecipients, this.onTransferComplete});

  final Future<void> Function(double) onOpenRecipients;
  final VoidCallback? onTransferComplete;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen>
    with SingleTickerProviderStateMixin {
  String _digits = '';
  Timer? _fxDebounce;

  double? _ngnPerUsd;

  _InputMode _inputMode = _InputMode.usd;

  late final AnimationController _swapCtrl;

  double get _parsedRaw => _digits.isEmpty ? 0 : (double.tryParse(_digits) ?? 0);

  /// The USDC amount that will actually be sent on-chain.
  /// PAJ only honors 2dp precision — we floor to 2dp to avoid overpaying.
  /// e.g. ₦300 → $0.221414 → floor to $0.22 → user sends $0.22, receives ₦298
  double get _usdAmount {
    if (_inputMode == _InputMode.usd) return _parsedRaw;
    if (_ngnPerUsd == null || _ngnPerUsd! <= 0) return 0;
    final rawUsd = _parsedRaw / _ngnPerUsd!;
    // Floor to 2dp — PAJ truncates, so we match exactly what they'll honor
    return (rawUsd * 100).floor() / 100.0;
  }

  /// The NGN amount the user will actually receive — based on the 2dp-floored USDC.
  double get _quantizedNgn {
    if (_ngnPerUsd == null || _ngnPerUsd! <= 0) return _parsedRaw;
    return _usdAmount * _ngnPerUsd!;
  }

  String get _primaryDisplay {
    if (_parsedRaw == 0) {
      return _inputMode == _InputMode.usd ? r'$0' : '₦0';
    }
    if (_inputMode == _InputMode.usd) {
      // We'll render whole and decimal parts separately in the widget,
      // so just return the full string here for the secondary display logic.
      return _parsedRaw == _parsedRaw.roundToDouble()
          ? '\$${_parsedRaw.toStringAsFixed(0)}'
          : '\$${_parsedRaw.toStringAsFixed(2)}';
    } else {
      // Show the quantized NGN (what they'll actually receive)
      final ngn = _quantizedNgn;
      return ngn > 0
          ? '₦${_formatThousands(ngn.round())}'
          : '₦${_formatThousands(_parsedRaw.round())}';
    }
  }

  /// Whole-number part of the USD amount for split rendering.
  String get _wholePart {
    if (_digits.isEmpty) return '0';
    if (_digits.contains('.')) return _digits.split('.')[0];
    return _digits;
  }

  /// Decimal part (after the dot), or null if no decimal entered yet.
  String? get _decimalPart {
    if (_inputMode != _InputMode.usd) return null;
    if (!_digits.contains('.')) return null;
    final parts = _digits.split('.');
    return parts.length > 1 ? parts[1] : '';
  }

  bool get _hasDecimal => _digits.contains('.');

  String? get _secondaryDisplay {
    if (_parsedRaw <= 0) return null;
    if (_inputMode == _InputMode.usd) {
      if (_ngnPerUsd == null) return null;
      final ngn = (_parsedRaw * _ngnPerUsd!).round();
      return '≈ ₦${_formatThousands(ngn)}';
    } else {
      if (_ngnPerUsd == null || _ngnPerUsd! <= 0) return null;
      // Show the exact 2dp USDC that will be sent — no surprises
      final usd = _usdAmount;
      if (usd <= 0) return null;
      return '= \$${usd.toStringAsFixed(2)}';
    }
  }

  String get _currencyLabel =>
      _inputMode == _InputMode.usd ? 'USD' : 'NGN';

  @override
  void initState() {
    super.initState();
    _swapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fetchRate();
  }

  @override
  void dispose() {
    _fxDebounce?.cancel();
    _swapCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRate() async {
    try {
      final model = ZendScope.of(context);
      final preview = await model.fxService.getPreview(1.0);
      if (!mounted) return;
      setState(() => _ngnPerUsd = preview.rate);
    } catch (_) {}
  }

  void _scheduleFetchRate() {
    _fxDebounce?.cancel();
    _fxDebounce = Timer(const Duration(milliseconds: 400), _fetchRate);
  }

  void _onKey(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      if (value == 'del') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
      } else if (value == '.') {
        if (_inputMode == _InputMode.ngn) return;
        if (!_digits.contains('.')) {
          _digits = _digits.isEmpty ? '0.' : '$_digits.';
        }
      } else if (value.length == 1 && RegExp(r'[0-9]').hasMatch(value)) {
        // In USD mode, enforce max 2 decimal places
        if (_inputMode == _InputMode.usd && _digits.contains('.')) {
          final parts = _digits.split('.');
          if (parts.length == 2 && parts[1].length >= 2) return; // already at 2dp
        }
        // Prevent leading zeros: "0" + "0" → stay "0"; "0" + "5" → replace with "5"
        if (_digits == '0') {
          if (value == '0') return; // block 00, 000, etc.
          _digits = value;          // replace lone zero with non-zero digit
        } else {
          _digits += value;
        }
      }
    });
    if (_ngnPerUsd == null) _scheduleFetchRate();
  }

  void _toggleMode() {
    HapticFeedback.selectionClick();
    if (_ngnPerUsd == null) _fetchRate();

    setState(() {
      if (_digits.isNotEmpty && _parsedRaw > 0 && _ngnPerUsd != null && _ngnPerUsd! > 0) {
        if (_inputMode == _InputMode.usd) {
          // USD → NGN: show the NGN equivalent of the 2dp-floored USD
          final usd2dp = (_parsedRaw * 100).floor() / 100.0;
          final ngn = (usd2dp * _ngnPerUsd!).round();
          _digits = ngn.toString();
        } else {
          // NGN → USD: convert back to the 2dp-floored USD string
          final usd = _usdAmount;
          _digits = usd > 0 ? usd.toStringAsFixed(2) : '0';
        }
      } else {
        _digits = '';
      }
      _inputMode = _inputMode == _InputMode.usd ? _InputMode.ngn : _InputMode.usd;
    });

    _swapCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 760;
    final veryCompact = MediaQuery.of(context).size.height < 600;
    final isNgn = _inputMode == _InputMode.ngn;

    return Container(
      color: ZendColors.bgDeep,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _IconPill(icon: Icons.qr_code_2, onTap: () {}),
                          GestureDetector(
                            onTap: () => pushZendSlide(context, const ProfileScreen()),
                            child: const CircleAvatar(
                              radius: 18,
                              backgroundColor: Color(0x332D6A4F),
                              child: Icon(Icons.person, color: ZendColors.textOnDeep, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight - 60),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              SizedBox(height: veryCompact ? 16 : compact ? 44 : 68),

                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Text(
                                  _currencyLabel,
                                  key: ValueKey(_currencyLabel),
                                  style: TextStyle(
                                    fontFamily: 'DMMono',
                                    color: isNgn
                                        ? const Color(0xCCE8F4EC)
                                        : const Color(0x80E8F4EC),
                                    fontSize: 11,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              AnimatedSwitcher(
                                duration: ZendMotion.amountTick,
                                child: _inputMode == _InputMode.usd
                                    ? _UsdAmountDisplay(
                                        key: ValueKey('$_digits$_inputMode'),
                                        wholePart: _wholePart,
                                        decimalPart: _decimalPart,
                                        hasDecimal: _hasDecimal,
                                        compact: compact,
                                      )
                                    : Text(
                                        _primaryDisplay,
                                        key: ValueKey<String>(_primaryDisplay),
                                        style: TextStyle(
                                          fontFamily: 'InstrumentSerif',
                                          color: ZendColors.textOnDeep,
                                          fontSize: compact ? 72 : 84,
                                          fontStyle: FontStyle.italic,
                                          height: 1.0,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 6),

                              if (_parsedRaw > 0 && _secondaryDisplay != null)
                                GestureDetector(
                                  onTap: _toggleMode,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: Container(
                                      key: ValueKey(_secondaryDisplay),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isNgn
                                            ? const Color(0x22E8F4EC)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                                        border: isNgn
                                            ? Border.all(color: const Color(0x33E8F4EC))
                                            : null,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _secondaryDisplay!,
                                            style: const TextStyle(
                                              fontFamily: 'DMMono',
                                              color: Color(0x99E8F4EC),
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.swap_vert_rounded,
                                            color: Color(0x66E8F4EC),
                                            size: 14,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              else if (_parsedRaw <= 0 && _ngnPerUsd != null)
                                GestureDetector(
                                  onTap: _toggleMode,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isNgn ? 'Switch to USD' : 'Switch to NGN',
                                        style: const TextStyle(
                                          fontFamily: 'DMMono',
                                          color: Color(0x44E8F4EC),
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.swap_vert_rounded,
                                        color: Color(0x44E8F4EC),
                                        size: 12,
                                      ),
                                    ],
                                  ),
                                ),

                              const Spacer(),
                              _Keypad(
                                onTap: _onKey,
                                keyHeight: veryCompact ? 48 : compact ? 56 : 78,
                                decimalEnabled: _inputMode == _InputMode.usd,
                              ),
                              SizedBox(height: veryCompact ? 6 : 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _GlassPill(
                                      label: 'Pool',
                                      onTap: _usdAmount > 0
                                          ? () => showCreatePoolDrawer(context, targetAmount: _usdAmount)
                                          : () {},
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _GlassPill(
                                      label: 'Request',
                                      onTap: _usdAmount > 0
                                          ? () => showRequestDrawer(
                                                context,
                                                initialAmount: _usdAmount,
                                                amountReadOnly: true,
                                              )
                                          : () {},
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: _PayButton(
                                  onTap: () async {
                                    final amount = _usdAmount;
                                    await widget.onOpenRecipients(amount);
                                    if (mounted) {
                                      setState(() {
                                        _digits = '';
                                        _inputMode = _InputMode.usd;
                                      });
                                    }
                                  },
                                ),
                              ),
                              SizedBox(height: compact ? 0 : 2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0x1AE8F4EC),
          borderRadius: BorderRadius.circular(ZendRadii.pill),
          border: Border.all(color: const Color(0x26E8F4EC)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
              fontFamily: 'DMSans', color: ZendColors.textOnDeep, fontSize: 14),
        ),
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  const _PayButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F4EC),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Pay',
          style: TextStyle(
            fontFamily: 'DMSans',
            color: ZendColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0x1AE8F4EC),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x26E8F4EC)),
        ),
        child: Icon(icon, color: const Color(0x99E8F4EC), size: 20),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onTap,
    required this.keyHeight,
    this.decimalEnabled = true,
  });

  final ValueChanged<String> onTap;
  final double keyHeight;
  final bool decimalEnabled;

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '.', '0', 'del',
    ];

    return Column(
      children: [
        for (var row = 0; row < 4; row++) ...[
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: col == 2 ? 0 : 10,
                      bottom: row == 3 ? 0 : 12,
                    ),
                    child: _KeypadKey(
                      label: keys[row * 3 + col],
                      keyHeight: keyHeight,
                      onTap: () => onTap(keys[row * 3 + col]),
                      enabled: keys[row * 3 + col] == '.'
                          ? decimalEnabled
                          : true,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _KeypadKey extends StatefulWidget {
  const _KeypadKey({
    required this.label,
    required this.onTap,
    required this.keyHeight,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final double keyHeight;
  final bool enabled;

  @override
  State<_KeypadKey> createState() => _KeypadKeyState();
}

class _KeypadKeyState extends State<_KeypadKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDel = widget.label == 'del';
    final opacity = widget.enabled ? 1.0 : 0.25;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled
          ? (_) {
              setState(() => _pressed = true);
              widget.onTap();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: ZendMotion.keypadPress,
        curve: Curves.easeOut,
        scale: _pressed ? 0.94 : 1,
        child: Opacity(
          opacity: opacity,
          child: SizedBox(
            height: widget.keyHeight,
            child: Center(
              child: isDel
                  ? const ZendBackspaceIcon(color: ZendColors.textOnDeep, size: 24)
                  : Text(
                      widget.label,
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 24,
                        color: ZendColors.textOnDeep,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UsdAmountDisplay extends StatelessWidget {
  const _UsdAmountDisplay({
    super.key,
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
    final wholeSize = compact ? 72.0 : 84.0;
    final decSize = compact ? 28.0 : 32.0;

    final wholeStyle = TextStyle(
      fontFamily: 'InstrumentSerif',
      color: ZendColors.textOnDeep,
      fontSize: wholeSize,
      fontStyle: FontStyle.italic,
      height: 1.0,
    );

    final decStyle = TextStyle(
      fontFamily: 'InstrumentSerif',
      color: const Color(0xCCE8F4EC),
      fontSize: decSize,
      fontStyle: FontStyle.italic,
      height: 1.0,
    );

    final currencyStyle = TextStyle(
      fontFamily: 'InstrumentSerif',
      color: const Color(0x80E8F4EC),
      fontSize: wholeSize * 0.5,
      fontStyle: FontStyle.italic,
      height: 1.0,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Currency symbol
        Padding(
          padding: EdgeInsets.only(top: wholeSize * 0.08),
          child: Text('\$', style: currencyStyle),
        ),
        // Whole part
        Text(wholePart.isEmpty ? '0' : wholePart, style: wholeStyle),
        // Decimal part — shown top-right when decimal is active
        if (hasDecimal) ...[
          const SizedBox(width: 2),
          // Dot + decimal digits, both top-aligned next to the whole number
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '.',
                    style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      color: const Color(0xCCE8F4EC),
                      fontSize: decSize,
                      fontStyle: FontStyle.italic,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    decimalPart == null || decimalPart!.isEmpty ? '—' : decimalPart!,
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

String _formatThousands(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final indexFromEnd = text.length - i;
    buffer.write(text[i]);
    if (indexFromEnd > 1 && indexFromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}
