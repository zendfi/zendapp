import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import '../../services/wallet_session_cache.dart';
import 'device_unlock_screen.dart';

/// One-time PIN upgrade screen shown when the user has a legacy 4-digit PIN.
///
/// Flow:
/// 1. Enter current 4-digit PIN (verify locally)
/// 2. Enter new 6-digit PIN
/// 3. Confirm new 6-digit PIN
/// 4. Re-encrypt + re-upload backup → mark migration complete → DeviceUnlockScreen
class PinMigrationScreen extends StatefulWidget {
  const PinMigrationScreen({super.key});

  @override
  State<PinMigrationScreen> createState() => _PinMigrationScreenState();
}

enum _MigrationPhase {
  verifyOld,   // Step 1: enter 4-digit current PIN
  createNew,   // Step 2: enter new 6-digit PIN
  confirmNew,  // Step 3: confirm new 6-digit PIN
}

class _PinMigrationScreenState extends State<PinMigrationScreen>
    with SingleTickerProviderStateMixin {
  _MigrationPhase _phase = _MigrationPhase.verifyOld;
  String _digits = '';
  String _oldPin = '';
  String _newPin = '';
  String? _errorMessage;
  bool _loading = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  // Allow up to 6 digits when verifying old PIN (users who already had 6-digit)
  static const int _maxOldDigits = 6;

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

  // Max digits accepted at each phase
  int get _maxDigits => _phase == _MigrationPhase.verifyOld ? _maxOldDigits : 6;

  // Whether the current digit count triggers submission
  bool get _shouldSubmit {
    if (_phase == _MigrationPhase.verifyOld) {
      // Accept both 4-digit and 6-digit old PINs
      return _digits.length == 4 || _digits.length == 6;
    }
    return _digits.length == 6;
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

      if (_digits.length >= _maxDigits) return;
      _digits += value;
    });

    if (_shouldSubmit) {
      // Small delay so the last dot fills before processing
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _advance();
      });
    }
  }

  Future<void> _advance() async {
    switch (_phase) {
      case _MigrationPhase.verifyOld:
        await _verifyOldPin(_digits);
      case _MigrationPhase.createNew:
        _captureNewPin(_digits);
      case _MigrationPhase.confirmNew:
        await _confirmAndMigrate(_digits);
    }
  }

  Future<void> _verifyOldPin(String pin) async {
    setState(() => _loading = true);
    try {
      final model = ZendScope.of(context);
      // Verify by attempting local decrypt — throws PinDecryptionException if wrong
      await model.walletService.verifyLocalPin(pin);
      if (!mounted) return;
      setState(() {
        _oldPin = pin;
        _digits = '';
        _loading = false;
        _phase = _MigrationPhase.createNew;
        _errorMessage = null;
      });
    } on PinDecryptionException {
      if (!mounted) return;
      _shakeController.forward(from: 0);
      setState(() {
        _loading = false;
        _errorMessage = 'Incorrect PIN. Please try again.';
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

  void _captureNewPin(String pin) {
    setState(() {
      _newPin = pin;
      _digits = '';
      _phase = _MigrationPhase.confirmNew;
      _errorMessage = null;
    });
  }

  Future<void> _confirmAndMigrate(String confirmPin) async {
    if (confirmPin != _newPin) {
      _shakeController.forward(from: 0);
      setState(() {
        _errorMessage = 'PINs don\'t match. Try again.';
        _digits = '';
        _newPin = '';
        _phase = _MigrationPhase.createNew;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final model = ZendScope.of(context);
      // changePin re-encrypts with new PIN + fresh salt and uploads new backup
      await model.walletService.changePin(_oldPin, _newPin);
      if (!mounted) return;

      // The session cache can be safely cleared; user will be asked to unlock
      WalletSessionCache.instance.clear();

      if (!mounted) return;
      // Replace the migration screen with the unlock screen — migration is done
      pushAndRemoveUntilZendSlide(context, const DeviceUnlockScreen());
    } on PinDecryptionException {
      if (!mounted) return;
      _shakeController.forward(from: 0);
      setState(() {
        _loading = false;
        _errorMessage = 'Original PIN verification failed. Please restart.';
        _digits = '';
        _oldPin = '';
        _newPin = '';
        _phase = _MigrationPhase.verifyOld;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.userMessage;
        _digits = '';
        _newPin = '';
        _phase = _MigrationPhase.createNew;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Something went wrong. Please try again.';
        _digits = '';
        _newPin = '';
        _phase = _MigrationPhase.createNew;
      });
    }
  }

  String get _heading => switch (_phase) {
        _MigrationPhase.verifyOld => 'Upgrade your PIN',
        _MigrationPhase.createNew => 'Set a new 6-digit PIN',
        _MigrationPhase.confirmNew => 'Confirm your new PIN',
      };

  String get _subtitle => switch (_phase) {
        _MigrationPhase.verifyOld =>
            'Enter your current PIN to confirm it\'s you.',
        _MigrationPhase.createNew =>
            'Your new PIN will protect your wallet with 1,000,000 possible combinations.',
        _MigrationPhase.confirmNew => 'Enter your new PIN again to confirm.',
      };

  // Phase progress: 0=verify, 1=create, 2=confirm — show as 3-step dots
  int get _phaseIndex => _phase.index;

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
              SizedBox(height: compact ? 32 : 48),

              // Phase progress dots (3 steps)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final active = i <= _phaseIndex;
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

              // Security upgrade badge on verify step
              if (_phase == _MigrationPhase.verifyOld) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: ZendColors.accentPop.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: ZendColors.accentPop.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.security, color: ZendColors.accentPop, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Security upgrade',
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 11,
                          color: ZendColors.accentPop,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Text(
                _heading,
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
              SizedBox(height: compact ? 28 : 44),

              // PIN dots (adapts to 4 or 6 based on phase)
              AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_shakeAnimation.value, 0),
                    child: child,
                  );
                },
                child: _phase == _MigrationPhase.verifyOld
                    ? _OldPinDots(filledCount: _digits.length)
                    : _NewPinDots(filledCount: _digits.length),
              ),
              const SizedBox(height: 16),

              // Status row
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
                            child: ZendLoader(
                              size: 16,
                              strokeWidth: 1.5,
                              color: ZendColors.accentPop,
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
              SizedBox(height: compact ? 12 : 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── PIN dot widgets ─────────────────────────────────────────────────────────

/// Dots for the old PIN entry (shown as 6 slots to accept both 4 and 6 digit old PINs).
class _OldPinDots extends StatelessWidget {
  const _OldPinDots({required this.filledCount});
  final int filledCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < filledCount;
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

/// Dots for the new PIN entry (always 6).
class _NewPinDots extends StatelessWidget {
  const _NewPinDots({required this.filledCount});
  final int filledCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < filledCount;
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

// ── Keypad ──────────────────────────────────────────────────────────────────

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
  const _PinKey({required this.label, required this.onTap, required this.height});

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
