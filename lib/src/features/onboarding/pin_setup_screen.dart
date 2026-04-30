import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../shell/zend_shell.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

enum _PinPhase { create, confirm }

class _PinSetupScreenState extends State<PinSetupScreen>
    with SingleTickerProviderStateMixin {
  _PinPhase _phase = _PinPhase.create;
  String _digits = '';
  String _firstPin = '';
  String? _errorMessage;
  bool _loading = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onKey(String value) {
    if (_loading) return;
    HapticFeedback.lightImpact();

    setState(() {
      _errorMessage = null;

      if (value == 'del') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
        return;
      }

      if (_digits.length >= 4) return;
      _digits += value;
    });

    if (_digits.length == 4) {
      _onFourDigitsEntered();
    }
  }

  void _onFourDigitsEntered() {
    if (_phase == _PinPhase.create) {
      // Store first PIN and move to confirm phase
      setState(() {
        _firstPin = _digits;
        _digits = '';
        _phase = _PinPhase.confirm;
      });
    } else {
      // Confirm phase — check match
      if (_digits == _firstPin) {
        _submitPin(_digits);
      } else {
        // Mismatch — shake, show error, reset to create phase
        _shakeController.forward(from: 0);
        setState(() {
          _errorMessage = 'PINs don\'t match. Try again.';
          _digits = '';
          _firstPin = '';
          _phase = _PinPhase.create;
        });
      }
    }
  }

  Future<void> _submitPin(String pin) async {
    setState(() => _loading = true);

    try {
      final model = ZendScope.of(context);
      await model.walletService.setupPinAndBackup(pin);

      if (!mounted) return;
      pushAndRemoveUntilZendSlide(context, const ZendShell());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Something went wrong. Please try again.';
        _digits = '';
        _firstPin = '';
        _phase = _PinPhase.create;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 760;

    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  SizedBox(height: compact ? 40 : 64),
                  Text(
                    'Set your transfer PIN',
                    style: const TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 28,
                      color: ZendColors.textOnDeep,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This PIN secures your wallet and authorizes transfers',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 14,
                      color: Color(0x99E8F4EC),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _phase == _PinPhase.create
                          ? 'Create your PIN'
                          : 'Confirm your PIN',
                      key: ValueKey(_phase),
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: ZendColors.accentPop,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 28 : 40),
                  AnimatedBuilder(
                    animation: _shakeController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_shakeAnimation.value, 0),
                        child: child,
                      );
                    },
                    child: _PinDots(filledCount: _digits.length),
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null)
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 13,
                        color: ZendColors.destructive,
                      ),
                    ),
                  const Spacer(),
                  _PinKeypad(onTap: _onKey, keyHeight: compact ? 62 : 72),
                  SizedBox(height: compact ? 12 : 24),
                ],
              ),
            ),
            if (_loading)
              Container(
                color: const Color(0xCC1C2B1E),
                child: const Center(child: ZendLoader(size: 32)),
              ),
          ],
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.filledCount});

  final int filledCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final filled = index < filledCount;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? ZendColors.accentPop : Colors.transparent,
              border: Border.all(
                color: filled ? ZendColors.accentPop : const Color(0x66E8F4EC),
                width: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({required this.onTap, required this.keyHeight});

  final ValueChanged<String> onTap;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '', '0', 'del',
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
                    child: keys[row * 3 + col].isEmpty
                        ? SizedBox(height: keyHeight)
                        : _PinKeypadKey(
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

class _PinKeypadKey extends StatefulWidget {
  const _PinKeypadKey({
    required this.label,
    required this.onTap,
    required this.keyHeight,
  });

  final String label;
  final VoidCallback onTap;
  final double keyHeight;

  @override
  State<_PinKeypadKey> createState() => _PinKeypadKeyState();
}

class _PinKeypadKeyState extends State<_PinKeypadKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final display = widget.label == 'del' ? '⌫' : widget.label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _pressed = true);
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
              display,
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
