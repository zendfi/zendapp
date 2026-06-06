import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_country_flag.dart';
import '../../design/zend_tokens.dart';
import '../../design/zend_primitives.dart';
import '../../models/api_exceptions.dart';
import '../../services/app_lock_service.dart';
import '../../services/biometric_service.dart';
import '../../services/wallet_session_cache.dart';
import '../onboarding/forgot_pin_screen.dart';

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

  final _biometricService = BiometricService();
  bool _biometricAvailable = false;
  int _biometricFailures = 0;
  static const int _maxBiometricFailures = 3;

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
      duration: const Duration(milliseconds: 300),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 4.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeOut,
    ));

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await _biometricService.isAvailable();
    final enabled = available ? await _biometricService.isEnabled() : false;
    if (!mounted) return;
    setState(() => _biometricAvailable = enabled);
    if (enabled) {
      // Small delay to let the overlay finish animating in
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _tryBiometricUnlock();
    }
  }

  Future<void> _tryBiometricUnlock() async {
    if (!_biometricAvailable || _biometricFailures >= _maxBiometricFailures) return;
    if (_loading) return;

    final pin = await _biometricService.authenticateAndGetPin();
    if (pin == null) {
      // Biometric failed or cancelled
      if (mounted) {
        _biometricFailures++;
        if (_biometricFailures >= _maxBiometricFailures) {
          setState(() {
            _biometricAvailable = false;
            _errorMessage = 'Too many biometric failures. Use your PIN.';
          });
        }
      }
      return;
    }

    // PIN retrieved — use it to unlock exactly like manual PIN entry
    await _submitPin(pin);
    // Reset failure counter on successful biometric unlock
    _biometricFailures = 0;
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

      if (_digits.length >= 6) return;
      _digits += value;
    });

    if (_digits.length == 6) {
      _submitPin(_digits);
    }
  }

  Future<void> _submitPin(String pin) async {
    // Disable keys while verifying — no overlay flash
    setState(() => _loading = true);

    try {
      final model = ZendScope.of(context);
      await model.walletService.verifyLocalPin(pin);

      if (!mounted) return;

      // Populate session cache so sends don't need to re-decrypt
      try {
        final keypair = await model.walletService.decryptLocalKeypair(pin);
        WalletSessionCache.instance.store(keypair);
        for (var i = 0; i < keypair.length; i++) { keypair[i] = 0; }
      } catch (_) {}

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
          child: Padding(
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
                // PIN dots / spinner
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
                if (_biometricAvailable && _biometricFailures < _maxBiometricFailures && !_loading && !_isLockedOut) ...[
                  TextButton.icon(
                    onPressed: _tryBiometricUnlock,
                    icon: const Icon(Icons.fingerprint, size: 20),
                    label: const Text('Use biometrics'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0x99E8F4EC),
                      textStyle: const TextStyle(fontFamily: 'DMSans', fontSize: 13),
                    ),
                  ),
                ],
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ForgotPinScreen(),
                      fullscreenDialog: true,
                    ),
                  ),
                  child: const Text(
                    'Forgot PIN?',
                    style: TextStyle(color: Color(0x66E8F4EC)),
                  ),
                ),
                SizedBox(height: compact ? 24 : 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── PIN UI components (self-contained, dark-theme) ──────────────────────────

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
                ? const ZendBackspaceIcon(color: ZendColors.textOnDeep, size: 22)
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
