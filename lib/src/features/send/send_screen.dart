import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../pools/create_pool_drawer.dart';
import '../profile/profile_screen.dart';
import '../request/request_drawer_sheet.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.onOpenRecipients});

  final ValueChanged<double> onOpenRecipients;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  String _digits = '';

  double get _parsedAmount => _digits.isEmpty ? 0 : (double.tryParse(_digits) ?? 0);

  String get _formattedAmount {
    if (_parsedAmount == 0) return r'$0';
    if (_parsedAmount == _parsedAmount.roundToDouble()) {
      return '\$${_parsedAmount.toStringAsFixed(0)}';
    }
    return '\$${_parsedAmount.toStringAsFixed(2)}';
  }

  String get _fxPreview {
    final naira = (_parsedAmount * 1538.3).round();
    return '≈ ₦${_formatThousands(naira)}';
  }

  void _onKey(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      if (value == 'del') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
      } else if (value == '.' && !_digits.contains('.')) {
        _digits = _digits.isEmpty ? '0.' : '$_digits.';
      } else if (value.length == 1 && RegExp(r'[0-9]').hasMatch(value)) {
        _digits += value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 760;

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
                          Row(
                            children: [
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
                    ],
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(height: compact ? 44 : 68),
                        GestureDetector(
                          onTap: () {},
                          child: Text(
                            'USD',
                            style: const TextStyle(
                              fontFamily: 'DMMono',
                              color: Color(0x80E8F4EC),
                              fontSize: 11,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: ZendMotion.amountTick,
                          child: Text(
                            _formattedAmount,
                            key: ValueKey<String>(_formattedAmount),
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
                        if (_digits.isNotEmpty)
                          Text(
                            _fxPreview,
                            style: const TextStyle(
                              fontFamily: 'DMMono',
                              color: Color(0x66E8F4EC),
                              fontSize: 13,
                            ),
                          ),
                        const Spacer(),
                        _Keypad(onTap: _onKey, keyHeight: compact ? 66 : 78),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(child: _GlassPill(label: 'Pool', onTap: _parsedAmount > 0 ? () => showCreatePoolDrawer(context, targetAmount: _parsedAmount) : () {})),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _GlassPill(
                                label: 'Request',
                                onTap: _parsedAmount > 0
                                    ? () => showRequestDrawer(context, initialAmount: _parsedAmount, amountReadOnly: true)
                                    : () {},
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: _PayButton(
                            onTap: () => widget.onOpenRecipients(_parsedAmount),
                          ),
                        ),
                        SizedBox(height: compact ? 0 : 2),
                      ],
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
          style: const TextStyle(fontFamily: 'DMSans', color: ZendColors.textOnDeep, fontSize: 14),
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
        child: Text(
          'Pay',
          style: const TextStyle(
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
  const _Keypad({required this.onTap, required this.keyHeight});

  final ValueChanged<String> onTap;
  final double keyHeight;

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
  const _KeypadKey({required this.label, required this.onTap, required this.keyHeight});

  final String label;
  final VoidCallback onTap;
  final double keyHeight;

  @override
  State<_KeypadKey> createState() => _KeypadKeyState();
}

class _KeypadKeyState extends State<_KeypadKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label == 'del' ? '⌫' : widget.label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _pressed = true);
        // Fire immediately on tap-down for instant response.
        // This eliminates missed taps caused by widget rebuilds
        // interrupting the gesture recognizer before onTapUp fires.
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: ZendMotion.keypadPress,
        curve: Curves.easeOut,
        scale: _pressed ? 0.94 : 1,
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
  return buffer.toString().replaceAll(RegExp(r',$'), '');
}
