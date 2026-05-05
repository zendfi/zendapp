import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../pools/create_pool_drawer.dart';
import '../profile/profile_screen.dart';
import '../request/request_drawer_sheet.dart';

/// Which currency the keypad is currently accepting.
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

  /// Live PAJ rate: NGN per 1 USD. Null until first fetch.
  double? _ngnPerUsd;

  _InputMode _inputMode = _InputMode.usd;

  /// Animation controller for the mode-swap transition.
  late final AnimationController _swapCtrl;

  // ── Derived values ────────────────────────────────────────────────────────

  double get _parsedRaw => _digits.isEmpty ? 0 : (double.tryParse(_digits) ?? 0);

  /// The USD amount that will actually be sent — always in USD regardless of mode.
  double get _usdAmount {
    if (_inputMode == _InputMode.usd) return _parsedRaw;
    if (_ngnPerUsd == null || _ngnPerUsd! <= 0) return 0;
    return _parsedRaw / _ngnPerUsd!;
  }

  String get _primaryDisplay {
    if (_parsedRaw == 0) {
      return _inputMode == _InputMode.usd ? r'$0' : '₦0';
    }
    if (_inputMode == _InputMode.usd) {
      return _parsedRaw == _parsedRaw.roundToDouble()
          ? '\$${_parsedRaw.toStringAsFixed(0)}'
          : '\$${_parsedRaw.toStringAsFixed(2)}';
    } else {
      // NGN mode — show with thousands separator, no decimals
      return '₦${_formatThousands(_parsedRaw.round())}';
    }
  }

  String? get _secondaryDisplay {
    if (_parsedRaw <= 0) return null;
    if (_inputMode == _InputMode.usd) {
      // USD mode: show NGN equivalent
      if (_ngnPerUsd == null) return null;
      final ngn = (_parsedRaw * _ngnPerUsd!).round();
      return '≈ ₦${_formatThousands(ngn)}';
    } else {
      // NGN mode: show exact USD equivalent with up to 6 decimal places
      // so the user sees the precise amount that will be sent.
      if (_ngnPerUsd == null || _ngnPerUsd! <= 0) return null;
      final usd = _parsedRaw / _ngnPerUsd!;
      // Show enough precision — strip trailing zeros but keep at least 2 dp
      final s6 = usd.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '');
      final display = s6.endsWith('.') ? '${s6}00' : s6;
      return '≈ \$$display';
    }
  }

  String get _currencyLabel =>
      _inputMode == _InputMode.usd ? 'USD' : 'NGN';

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _swapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // Fetch the rate eagerly so it's ready when the user starts typing.
    _fetchRate();
  }

  @override
  void dispose() {
    _fxDebounce?.cancel();
    _swapCtrl.dispose();
    super.dispose();
  }

  // ── Rate fetching ─────────────────────────────────────────────────────────

  Future<void> _fetchRate() async {
    try {
      final model = ZendScope.of(context);
      // Use amount=1 to get the rate itself.
      final preview = await model.fxService.getPreview(1.0);
      if (!mounted) return;
      setState(() => _ngnPerUsd = preview.rate);
    } catch (_) {
      // Rate unavailable — NGN mode will show no secondary display.
    }
  }

  void _scheduleFetchRate() {
    _fxDebounce?.cancel();
    _fxDebounce = Timer(const Duration(milliseconds: 400), _fetchRate);
  }

  // ── Input handling ────────────────────────────────────────────────────────

  void _onKey(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      if (value == 'del') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
      } else if (value == '.') {
        // NGN mode: no decimals — ignore the decimal key
        if (_inputMode == _InputMode.ngn) return;
        if (!_digits.contains('.')) {
          _digits = _digits.isEmpty ? '0.' : '$_digits.';
        }
      } else if (value.length == 1 && RegExp(r'[0-9]').hasMatch(value)) {
        _digits += value;
      }
    });
    // Refresh rate if we don't have one yet
    if (_ngnPerUsd == null) _scheduleFetchRate();
  }

  void _toggleMode() {
    HapticFeedback.selectionClick();
    // If we don't have a rate yet, fetch it now
    if (_ngnPerUsd == null) _fetchRate();

    setState(() {
      // Convert the current digits to the new mode so the display stays consistent
      if (_digits.isNotEmpty && _parsedRaw > 0 && _ngnPerUsd != null && _ngnPerUsd! > 0) {
        if (_inputMode == _InputMode.usd) {
          // Switching USD → NGN: convert current USD amount to NGN
          final ngn = (_parsedRaw * _ngnPerUsd!).round();
          _digits = ngn.toString();
        } else {
          // Switching NGN → USD: convert current NGN amount to USD
          final usd = _parsedRaw / _ngnPerUsd!;
          // Round to 2 decimal places, strip trailing zeros
          final usdStr = usd.toStringAsFixed(2);
          _digits = usdStr.endsWith('.00')
              ? usd.toStringAsFixed(0)
              : usdStr.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
        }
      } else {
        _digits = '';
      }
      _inputMode = _inputMode == _InputMode.usd ? _InputMode.ngn : _InputMode.usd;
    });

    _swapCtrl.forward(from: 0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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

                              // ── Currency label ──
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

                              // ── Primary amount ──
                              AnimatedSwitcher(
                                duration: ZendMotion.amountTick,
                                child: Text(
                                  _primaryDisplay,
                                  key: ValueKey<String>(_primaryDisplay),
                                  style: TextStyle(
                                    fontFamily: 'InstrumentSerif',
                                    color: ZendColors.textOnDeep,
                                    fontSize: compact ? 64 : 72,
                                    fontStyle: FontStyle.italic,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),

                              // ── Secondary (FX preview) — tappable to toggle mode ──
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
                                // Show the toggle hint even when amount is 0
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
                                // In NGN mode, disable the decimal key
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
                                    // Always pass the USD amount downstream
                                    final amount = _usdAmount;
                                    await widget.onOpenRecipients(amount);
                                    if (mounted) {
                                      setState(() {
                                        _digits = '';
                                        // Reset to USD mode after send
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

// ── Supporting widgets ────────────────────────────────────────────────────────

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
                      // Dim the decimal key in NGN mode
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
    final label = widget.label == 'del' ? '⌫' : widget.label;
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
              child: Text(
                label,
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
