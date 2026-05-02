import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/app_lock_service.dart';

/// Full-screen PIN overlay shown when the app is locked due to inactivity.
///
/// Sits above the entire widget tree (injected via MaterialApp.builder).
/// Animates in/out with a fade so the transition feels intentional.
class AppLockOverlay extends StatelessWidget {
  const AppLockOverlay({
    super.key,
    required this.lockService,
    required this.child,
  });

  final AppLockService lockService;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lockService,
      builder: (context, _) {
        return Stack(
          children: [
            child,
            if (lockService.isLocked)
              _LockScreen(lockService: lockService),
          ],
        );
      },
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.lockService});

  final AppLockService lockService;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen>
    with TickerProviderStateMixin {
  String _digits = '';
  int _attempts = 0;
  String? _errorMessage;
  bool _loading = false;
  DateTime? _lockedUntil;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  static const int _maxAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticOut,
    ));

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _fadeController.dispose();
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

      // Fade out before unlocking so the transition is smooth
      await _fadeController.reverse();
      if (!mounted) return;

      widget.lockService.unlock();
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

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Scaffold(
        backgroundColor: ZendColors.bgDeep,
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SizedBox(height: compact ? 40 : 64),
                    // Lock icon
                    const Icon(
                      Icons.lock_outline_rounded,
                      color: ZendColors.accentPop,
                      size: 36,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'App locked',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 28,
                        color: ZendColors.textOnDeep,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your PIN to continue',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        color: Color(0x99E8F4EC),
                      ),
                    ),
                    SizedBox(height: compact ? 36 : 52),
                    // PIN dots with shake animation
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
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: ZendColors.destructive,
                        ),
                      ),
                    const Spacer(),
                    Opacity(
                      opacity: _isLockedOut ? 0.3 : 1.0,
                      child: IgnorePointer(
                        ignoring: _isLockedOut,
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
              if (_loading)
                Container(
                  color: const Color(0xCC1C2B1E),
                  child: const Center(child: ZendLoader(size: 32)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── PIN UI components (self-contained, dark-theme) ──────────────────────────

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
      '',  '0', 'del',
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

class _PinKey extends StatelessWidget {
  const _PinKey({
    required this.label,
    required this.onTap,
    required this.height,
  });

  final String label;
  final ValueChanged<String> onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) {
      return SizedBox(width: 80, height: height);
    }

    return SizedBox(
      width: 80,
      height: height,
      child: TextButton(
        onPressed: () => onTap(label),
        style: TextButton.styleFrom(
          foregroundColor: ZendColors.textOnDeep,
          textStyle: const TextStyle(
            fontFamily: 'DMMono',
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: label == 'del'
            ? const Icon(Icons.backspace_outlined, color: ZendColors.textOnDeep)
            : Text(label),
      ),
    );
  }
}
