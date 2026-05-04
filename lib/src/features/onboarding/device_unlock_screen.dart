import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_country_flag.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import '../profile/profile_screen.dart';
import '../shell/zend_shell.dart';
import 'welcome_screen.dart';

class DeviceUnlockScreen extends StatefulWidget {
  const DeviceUnlockScreen({super.key});

  @override
  State<DeviceUnlockScreen> createState() => _DeviceUnlockScreenState();
}

class _DeviceUnlockScreenState extends State<DeviceUnlockScreen>
    with SingleTickerProviderStateMixin {
  String _digits = '';
  int _attempts = 0;
  String? _errorMessage;
  bool _loading = false;
  DateTime? _lockedUntil;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  static const int _maxAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 15);

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

  bool get _isLockedOut {
    if (_lockedUntil == null) return false;
    return DateTime.now().isBefore(_lockedUntil!);
  }

  void _onKey(String value) {
    if (_loading || _isLockedOut) return;
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
      _submitPin(_digits);
    }
  }

  Future<void> _submitPin(String pin) async {
    setState(() => _loading = true);

    try {
      final model = ZendScope.of(context);
      await model.walletService.verifyLocalPin(pin);

      if (!mounted) return;
      pushAndRemoveUntilZendSlide(context, const ZendShell());
    } on PinDecryptionException {
      if (!mounted) return;
      _attempts++;
      _shakeController.forward(from: 0);

      if (_attempts >= _maxAttempts) {
        setState(() {
          _loading = false;
          _lockedUntil = DateTime.now().add(_lockoutDuration);
          _errorMessage = 'Too many attempts. Try again in 15 minutes.';
          _digits = '';
        });
      } else {
        setState(() {
          _loading = false;
          _errorMessage = 'Incorrect PIN';
          _digits = '';
        });
      }
    } on ZendException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.userMessage;
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

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 760;

    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              SizedBox(height: compact ? 40 : 64),
              const Text(
                'Unlock Zend',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 28,
                  color: ZendColors.textOnDeep,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your PIN to unlock this device',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: Color(0x99E8F4EC),
                ),
              ),
              SizedBox(height: compact ? 36 : 52),
              AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_shakeAnimation.value, 0),
                    child: child,
                  );
                },
                child: ZendPinDotsOrSpinner(
                  filledCount: _digits.length,
                  loading: _loading,
                ),
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
                    : null,
              ),
              const Spacer(),
              Opacity(
                opacity: (_isLockedOut || _loading) ? 0.3 : 1.0,
                child: IgnorePointer(
                  ignoring: _isLockedOut || _loading,
                  child: _PinKeypad(
                    onTap: _onKey,
                    keyHeight: compact ? 62 : 72,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  pushZendSlide(
                    context,
                    const ProfileScreen(),
                    rootNavigator: true,
                  );
                },
                child: const Text(
                  'PIN settings',
                  style: TextStyle(color: ZendColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () {
                  pushAndRemoveUntilZendSlide(
                    context,
                    const WelcomeScreen(),
                    rootNavigator: true,
                  );
                },
                child: const Text(
                  'Use phone number instead',
                  style: TextStyle(color: ZendColors.textSecondary),
                ),
              ),
              SizedBox(height: compact ? 12 : 24),
            ],
          ),
        ),
      ),
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
