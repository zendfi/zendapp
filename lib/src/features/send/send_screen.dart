import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../design/zend_primitives.dart';
import '../../navigation/zend_routes.dart';
import '../drop/drop_sheet.dart';
import '../profile/profile_screen.dart';
import '../request/request_drawer_sheet.dart';
import 'qr_scanner_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
      // Send screen lives on the intentional deep green brand surface
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
                          _IconPill(icon: PhosphorIconsBold.qrCode, onTap: () => pushZendSlide(context, const QrScannerScreen())),
                          // Profile — balance is now surfaced in the navbar
                          // (see ZendBottomBar's _BalanceNavItem), so it no
                          // longer needs its own pill here.
                          GestureDetector(
                            onTap: () => pushZendSlide(context, const ProfileScreen()),
                            child: ZendAvatar(
                              radius: 18,
                              photoUrl: ZendScope.of(context).currentAvatarUrl,
                              initials: ZendScope.of(context).currentDisplayName?.isNotEmpty == true
                                  ? ZendScope.of(context).currentDisplayName![0].toUpperCase()
                                  : ZendScope.of(context).username.isNotEmpty
                                      ? ZendScope.of(context).username[0].toUpperCase()
                                      : null,
                              backgroundColor: const Color(0x3095D5B2),
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
                                  style: ZendTextStyles.tabularNumeric.copyWith(color: isNgn
                                        ? const Color(0xCCF0F0F0)
                                        : const Color(0x80F0F0F0), fontSize: 11, letterSpacing: 1.4),
                                ),
                              ),
                              const SizedBox(height: 8),

                              AnimatedSwitcher(
                                duration: ZendMotion.amountTick,
                                // Key only on _inputMode (not _digits) so
                                // typing a digit doesn't tear down and
                                // rebuild the whole display via
                                // AnimatedSwitcher's cross-fade — that would
                                // replay the bounce on every already-settled
                                // digit, not just the newly typed one.
                                // _UsdAmountDisplay keeps its identity across
                                // keystrokes and each digit inside animates
                                // independently via keyed _BouncyDigit
                                // children (see _BouncyDigits below).
                                child: _inputMode == _InputMode.usd
                                    ? _UsdAmountDisplay(
                                        key: const ValueKey('usd-amount'),
                                        wholePart: _wholePart,
                                        decimalPart: _decimalPart,
                                        hasDecimal: _hasDecimal,
                                        compact: compact,
                                      )
                                    : _BouncyDigits(
                                        key: const ValueKey('ngn-amount'),
                                        text: _primaryDisplay,
                                        style: TextStyle(
                                          fontFamily: 'Satoshi',
                                          fontWeight: FontWeight.w700,
                                          color: ZendColors.textOnDeep,
                                          fontSize: compact ? 72 : 84,
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
                                            ? const Color(0x22F0F0F0)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                                        border: isNgn
                                            ? Border.all(color: const Color(0x33F0F0F0))
                                            : null,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _secondaryDisplay!,
                                            style: ZendTextStyles.tabularNumeric.copyWith(color: Color(0x99F0F0F0), fontSize: 13),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            PhosphorIconsBold.arrowsDownUp,
                                            color: Color(0x66F0F0F0),
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
                                        style: ZendTextStyles.tabularNumeric.copyWith(color: Color(0x44F0F0F0), fontSize: 11),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        PhosphorIconsBold.arrowsDownUp,
                                        color: Color(0x44F0F0F0),
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
                                    child: _DropHoldButton(
                                      enabled: _usdAmount > 0 && _usdAmount <= ZendScope.of(context).spendableBalance,
                                      onActivated: () => showDropSheet(context, amount: _usdAmount),
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

/// Drop button that requires a 3-second press-and-hold to activate.
///
/// While held:
/// - A fill arc sweeps clockwise over 3 seconds
/// - On completion: light haptic cascade + a brief scale pulse
/// - Releasing early cancels with no action
///
/// When not held the button looks identical to _GlassPill but with a subtle
/// lightning bolt / drop icon hint.
class _DropHoldButton extends StatefulWidget {
  const _DropHoldButton({required this.enabled, required this.onActivated});
  final bool enabled;
  final VoidCallback onActivated;

  @override
  State<_DropHoldButton> createState() => _DropHoldButtonState();
}

class _DropHoldButtonState extends State<_DropHoldButton>
    with TickerProviderStateMixin {
  static const Duration _holdDuration = Duration(seconds: 3);

  late final AnimationController _fillCtrl;
  late final AnimationController _pulseCtrl;
  bool _holding = false;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _fillCtrl = AnimationController(vsync: this, duration: _holdDuration);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fillCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && _holding && !_fired) {
        _onHoldComplete();
      }
    });
  }

  @override
  void dispose() {
    _fillCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onPointerDown() {
    if (!widget.enabled) return;
    setState(() {
      _holding = true;
      _fired = false;
    });
    _fillCtrl.forward(from: 0);
  }

  void _onPointerUp() {
    if (!_holding) return;
    setState(() => _holding = false);
    if (!_fired) _fillCtrl.reverse();
  }

  Future<void> _onHoldComplete() async {
    _fired = true;
    setState(() => _holding = false);

    // Haptic cascade: two light taps + one medium
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.mediumImpact();

    // Pulse animation
    await _pulseCtrl.forward();
    await _pulseCtrl.reverse();

    _fillCtrl.reset();
    if (mounted) widget.onActivated();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _onPointerDown(),
      onPointerUp: (_) => _onPointerUp(),
      onPointerCancel: (_) => _onPointerUp(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_fillCtrl, _pulseCtrl]),
        builder: (context, _) {
          final fill = _fillCtrl.value;
          final pulse = _pulseCtrl.value;
          final scale = 1.0 + pulse * 0.04;

          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: widget.enabled ? 1.0 : 0.4,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0x1AF0F0F0),
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                  border: fill > 0
                      ? Border.all(
                          color: ZendColors.accentBright.withValues(alpha: 0.6),
                          width: 1.5,
                        )
                      : Border.all(color: const Color(0x26F0F0F0)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Fill progress bar
                      if (fill > 0)
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: fill,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: ZendColors.accentBright.withValues(alpha: 0.18),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Label
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsBold.lightning,
                            size: 14,
                            color: fill > 0
                                ? ZendColors.accentBright
                                : ZendColors.textOnDeep.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            fill > 0
                                ? 'Hold… ${(3 - fill * 3).ceil()}s'
                                : 'Drop',
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              fontSize: 14,
                              color: fill > 0
                                  ? ZendColors.accentBright
                                  : ZendColors.textOnDeep,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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
          color: const Color(0x1AF0F0F0),
          borderRadius: BorderRadius.circular(ZendRadii.pill),
          border: Border.all(color: const Color(0x26F0F0F0)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
              fontFamily: 'Satoshi', color: ZendColors.textOnDeep, fontSize: 14),
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
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F4EC),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          'Pay',
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: zt.isDark ? ZendColors.bgDeep : ZendColors.textPrimary,
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
          color: const Color(0x1AF0F0F0),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x26F0F0F0)),
        ),
        child: Icon(icon, color: const Color(0x99F0F0F0), size: 20),
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
                        fontFamily: 'Satoshi',
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
      fontFamily: 'Satoshi',
      fontWeight: FontWeight.w700,
      color: ZendColors.textOnDeep,
      fontSize: wholeSize,
      height: 1.0,
    );

    final decStyle = TextStyle(
      fontFamily: 'Satoshi',
      fontWeight: FontWeight.w700,
      color: const Color(0xCCF0F0F0),
      fontSize: decSize,
      height: 1.0,
    );

    final currencyStyle = TextStyle(
      fontFamily: 'Satoshi',
      fontWeight: FontWeight.w700,
      color: const Color(0x80F0F0F0),
      fontSize: wholeSize * 0.5,
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
        // Whole part — each digit gets its own bouncy pop-in animation
        // rather than the whole string appearing flatly.
        _BouncyDigits(
          text: wholePart.isEmpty ? '0' : wholePart,
          style: wholeStyle,
        ),
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
                      fontFamily: 'Satoshi',
                      fontWeight: FontWeight.w700,
                      color: const Color(0xCCF0F0F0),
                      fontSize: decSize,
                      height: 1.0,
                    ),
                  ),
                  _BouncyDigits(
                    text: decimalPart == null || decimalPart!.isEmpty ? '—' : decimalPart!,
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

/// Renders [text] one character at a time, each in its own [_BouncyDigit]
/// keyed by its position + character so that newly-typed digits play a
/// spring-in animation while already-settled digits stay put instead of
/// replaying the animation on every keystroke.
class _BouncyDigits extends StatelessWidget {
  const _BouncyDigits({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < text.length; i++)
          _BouncyDigit(
            // Keying on index+char means a digit that's replaced (e.g. the
            // leading zero swapped for a typed digit) still re-triggers the
            // bounce, while digits that just shift position because a new
            // one was appended after them do not replay.
            key: ValueKey('$i-${text[i]}'),
            char: text[i],
            style: style,
          ),
      ],
    );
  }
}

/// A single character that pops in with a slight overshoot ("bouncy") scale
/// + fade when it first mounts. Uses Curves.easeOutBack rather than
/// Curves.elasticOut — elasticOut oscillates past 1.0 a few times before
/// settling, which read as too energetic for something that fires on every
/// keystroke; easeOutBack overshoots once, gently, then settles. The scale
/// also starts from 0.7 (not 0.0) so the "pop" is a subtle nudge rather
/// than a full grow-from-nothing.
class _BouncyDigit extends StatefulWidget {
  const _BouncyDigit({super.key, required this.char, required this.style});

  final String char;
  final TextStyle style;

  @override
  State<_BouncyDigit> createState() => _BouncyDigitState();
}

class _BouncyDigitState extends State<_BouncyDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: _controller.drive(CurveTween(curve: Curves.easeOut)),
        child: Text(widget.char, style: widget.style),
      ),
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
