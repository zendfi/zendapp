import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import '../shell/zend_shell.dart';
import 'pin_setup_screen.dart';

class PinRestoreScreen extends StatefulWidget {
  const PinRestoreScreen({super.key});

  @override
  State<PinRestoreScreen> createState() => _PinRestoreScreenState();
}

class _PinRestoreScreenState extends State<PinRestoreScreen>
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
      await model.walletService.restoreFromBackup(pin);

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
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.errorCode == 'BACKUP_NOT_FOUND') {
        // No backup on server — generate new keypair and go to PIN setup
        try {
          final model = ZendScope.of(context);
          await model.walletService.generateKeypair();
          if (!mounted) return;
          pushReplacementZendSlide(context, const PinSetupScreen());
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _errorMessage = 'Something went wrong. Please try again.';
            _digits = '';
          });
        }
      } else {
        setState(() {
          _loading = false;
          _errorMessage = e.userMessage;
          _digits = '';
        });
      }
    } catch (e) {
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
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  SizedBox(height: compact ? 40 : 64),
                  Text(
                    'Enter your PIN',
                    style: const TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 28,
                      color: ZendColors.textOnDeep,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your transfer PIN to restore your wallet',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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
