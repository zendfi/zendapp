import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';

enum _ChangePinPhase { current, newPin, confirm }

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen>
    with SingleTickerProviderStateMixin {
  _ChangePinPhase _phase = _ChangePinPhase.current;

  String _digits = '';
  String? _errorMessage;
  bool _loading = false;
  int _attempts = 0;

  // Stored across phases
  String _currentPin = '';
  String _newPin = '';

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  static const int _maxAttempts = 5;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  String get _title {
    switch (_phase) {
      case _ChangePinPhase.current:
        return 'Enter current PIN';
      case _ChangePinPhase.newPin:
        return 'Enter new PIN';
      case _ChangePinPhase.confirm:
        return 'Confirm new PIN';
    }
  }

  String get _subtitle {
    switch (_phase) {
      case _ChangePinPhase.current:
        return 'Enter your existing 4-digit PIN';
      case _ChangePinPhase.newPin:
        return 'Choose a new 4-digit PIN';
      case _ChangePinPhase.confirm:
        return 'Re-enter your new PIN to confirm';
    }
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
      _onPinComplete(_digits);
    }
  }

  Future<void> _onPinComplete(String pin) async {
    switch (_phase) {
      case _ChangePinPhase.current:
        await _verifyCurrentPin(pin);
      case _ChangePinPhase.newPin:
        _currentPin = _currentPin; // already stored
        _newPin = pin;
        setState(() {
          _digits = '';
          _phase = _ChangePinPhase.confirm;
        });
      case _ChangePinPhase.confirm:
        await _confirmAndChange(pin);
    }
  }

  Future<void> _verifyCurrentPin(String pin) async {
    setState(() => _loading = true);
    try {
      final model = ZendScope.of(context);
      await model.walletService.verifyLocalPin(pin);
      if (!mounted) return;
      _currentPin = pin;
      setState(() {
        _loading = false;
        _digits = '';
        _phase = _ChangePinPhase.newPin;
        _errorMessage = null;
      });
    } on PinDecryptionException {
      if (!mounted) return;
      _attempts++;
      _shakeController.forward(from: 0);
      if (_attempts >= _maxAttempts) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Incorrect PIN';
        _digits = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Something went wrong. Please try again.';
        _digits = '';
      });
    }
  }

  Future<void> _confirmAndChange(String confirmPin) async {
    if (confirmPin != _newPin) {
      _shakeController.forward(from: 0);
      setState(() {
        _errorMessage = 'PINs don\'t match';
        _digits = '';
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final model = ZendScope.of(context);
      await model.walletService.changePin(_currentPin, _newPin);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN changed successfully')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Failed to change PIN. Please try again.';
        _digits = '';
      });
    }
  }

  void _goBack() {
    if (_phase == _ChangePinPhase.current) {
      Navigator.of(context).pop();
    } else if (_phase == _ChangePinPhase.confirm) {
      setState(() {
        _phase = _ChangePinPhase.newPin;
        _digits = '';
        _errorMessage = null;
        _newPin = '';
      });
    } else {
      setState(() {
        _phase = _ChangePinPhase.current;
        _digits = '';
        _errorMessage = null;
        _currentPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 760;

    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: compact ? 16 : 24),
              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: _goBack,
                  child: const Icon(Icons.arrow_back,
                      color: ZendColors.textOnDeep, size: 24),
                ),
              ),
              SizedBox(height: compact ? 32 : 48),
              // Phase indicator dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final active = i <= _phase.index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: active ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? ZendColors.accentPop
                            : const Color(0x33E8F4EC),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              Text(
                _title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 28,
                  color: ZendColors.textOnDeep,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: Color(0x99E8F4EC),
                ),
              ),
              SizedBox(height: compact ? 32 : 48),
              // PIN dots
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
              SizedBox(
                height: 20,
                child: _errorMessage != null
                    ? Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: ZendColors.destructive,
                        ),
                      )
                    : _loading
                        ? const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: ZendColors.accentPop,
                              ),
                            ),
                          )
                        : null,
              ),
              const Spacer(),
              Opacity(
                opacity: _loading ? 0.3 : 1.0,
                child: IgnorePointer(
                  ignoring: _loading,
                  child: _PinKeypad(
                    onTap: _onKey,
                    keyHeight: compact ? 62 : 72,
                  ),
                ),
              ),
              SizedBox(height: compact ? 24 : 36),
            ],
          ),
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
            duration: const Duration(milliseconds: 100),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? ZendColors.accentPop : Colors.transparent,
              border: Border.all(
                color:
                    filled ? ZendColors.accentPop : const Color(0x66E8F4EC),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var col = 0; col < 3; col++)
                _PinKey(
                  label: keys[row * 3 + col],
                  onTap: onTap,
                  height: keyHeight,
                ),
            ],
          ),
          if (row < 3) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _PinKey extends StatefulWidget {
  const _PinKey({
    required this.label,
    required this.onTap,
    required this.height,
  });

  final String label;
  final ValueChanged<String> onTap;
  final double height;

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty) {
      return SizedBox(width: 80, height: widget.height);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _pressed = true);
        widget.onTap(widget.label);
      },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
        scale: _pressed ? 0.92 : 1.0,
        child: SizedBox(
          width: 80,
          height: widget.height,
          child: Center(
            child: widget.label == 'del'
                ? const Icon(Icons.backspace_outlined,
                    color: ZendColors.textOnDeep, size: 22)
                : Text(
                    widget.label,
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      color: ZendColors.textOnDeep,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
