import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_country_flag.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../features/shell/zend_shell.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import '../../services/recovery_service.dart';

/// Final step in the PIN recovery flow.
///
/// Accepts the recovered keypair + recovery_token.
/// On PIN confirmation:
///   1. Delegates all crypto + backend call to WalletService.resetPinWithRecoveredKeypair
///   2. That method re-encrypts the keypair, submits to backend, persists locally,
///      and populates WalletSessionCache
///   3. Navigates home with success message
class RecoveryNewPinScreen extends StatefulWidget {
  const RecoveryNewPinScreen({
    super.key,
    required this.recoveryToken,
    required this.recoveredKeypair,
  });

  final String recoveryToken;

  /// The decrypted 64-byte keypair from the recovery packet.
  /// This screen zeroes these bytes on all exit paths.
  final Uint8List recoveredKeypair;

  @override
  State<RecoveryNewPinScreen> createState() => _RecoveryNewPinScreenState();
}

class _RecoveryNewPinScreenState extends State<RecoveryNewPinScreen>
    with SingleTickerProviderStateMixin {
  _PinPhase _phase = _PinPhase.create;
  String _firstPin = '';
  String _pinDigits = '';
  String? _error;
  bool _loading = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

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
  }

  @override
  void dispose() {
    // Zero the keypair on any exit path
    for (var i = 0; i < widget.recoveredKeypair.length; i++) {
      widget.recoveredKeypair[i] = 0;
    }
    _shakeController.dispose();
    super.dispose();
  }

  void _onKey(String value) {
    setState(() {
      _error = null;
      if (value == 'del') {
        if (_pinDigits.isNotEmpty) {
          _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
        }
        return;
      }
      if (_pinDigits.length < 6) { _pinDigits += value; }
    });

    if (_pinDigits.length == 6) {
      _onPinComplete(_pinDigits);
    }
  }

  void _onPinComplete(String pin) {
    if (_phase == _PinPhase.create) {
      setState(() {
        _firstPin = pin;
        _pinDigits = '';
        _phase = _PinPhase.confirm;
        _error = null;
      });
      return;
    }

    // Confirm phase
    if (pin != _firstPin) {
      _shakeController.forward(from: 0);
      setState(() {
        _error = 'PINs do not match. Try again.';
        _pinDigits = '';
        _firstPin = '';
        _phase = _PinPhase.create;
      });
      return;
    }

    _resetPin(pin);
  }

  Future<void> _resetPin(String newPin) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final model = ZendScope.of(context);

      await model.walletService.resetPinWithRecoveredKeypair(
        newPin: newPin,
        recoveredKeypair: widget.recoveredKeypair,
        recoveryToken: widget.recoveryToken,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN reset successfully! Welcome back.'),
          backgroundColor: ZendColors.positive,
        ),
      );

      pushAndRemoveUntilZendSlide(context, const ZendShell());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'PIN reset failed: ${e.userMessage}';
        _loading = false;
      });
    } on RecoveryDecryptionException {
      if (!mounted) return;
      setState(() {
        _error = 'Recovery verification failed. Please try again.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 760;
    const textOnDeepSecondary = Color(0x99E8F4EC);

    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 48),
              Text(
                _phase == _PinPhase.create
                    ? 'Set a new PIN'
                    : 'Confirm your PIN',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 26,
                  color: ZendColors.textOnDeep,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _phase == _PinPhase.create
                    ? 'Choose a 6-digit PIN to protect your wallet.'
                    : 'Enter the same PIN again to confirm.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: textOnDeepSecondary,
                ),
              ),
              SizedBox(height: compact ? 32 : 48),
              AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) => Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                ),
                child: ZendPinDotsOrSpinner(
                  filledCount: _pinDigits.length,
                  loading: _loading,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 20,
                child: _error != null
                    ? Text(
                        _error!,
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
                opacity: _loading ? 0.3 : 1,
                child: IgnorePointer(
                  ignoring: _loading,
                  child: _PinKeypad(onTap: _onKey, keyHeight: compact ? 62 : 72),
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

enum _PinPhase { create, confirm }

// ── PIN keypad (dark-theme) ───────────────────────────────────────────────────

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({required this.onTap, required this.keyHeight});
  final ValueChanged<String> onTap;
  final double keyHeight;

  static const _keys = [
    '1', '2', '3',
    '4', '5', '6',
    '7', '8', '9',
    '', '0', 'del',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < 4; row++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var col = 0; col < 3; col++)
                _PinKey(
                  label: _keys[row * 3 + col],
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
        scale: _pressed ? 0.92 : 1,
        child: SizedBox(
          width: 80,
          height: widget.height,
          child: Center(
            child: widget.label == 'del'
                ? const ZendBackspaceIcon(
                    color: ZendColors.textOnDeep, size: 22)
                : Text(
                    widget.label,
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 22,
                      color: ZendColors.textOnDeep,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
