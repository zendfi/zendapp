import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/wallet_session_cache.dart';
import '../send/send_shared_widgets.dart';

/// Resolves a signing keypair for a Vibe send, prompting for PIN when
/// required.
///
/// Per zendapp-hardening Req 1.2, every signing surface — including Vibes —
/// must honor [SigningPolicyService.requiresPinForAmount] and must never
/// silently fail/skip a send just because [WalletSessionCache] is empty.
/// Vibes still get the lightweight, no-PIN-below-threshold UX when the
/// cache is populated and policy allows it; otherwise this collects a PIN.
///
/// Returns the resolved keypair bytes (caller must zero them after use), or
/// `null` if the user cancelled.
Future<Uint8List?> resolveVibeSigningKeypair(
  BuildContext context,
  double amountUsdc,
) async {
  final model = ZendScope.of(context);
  final cache = WalletSessionCache.instance;
  final needsPin = await model.signingPolicyService.requiresPinForAmount(amountUsdc);

  if (!needsPin && cache.hasKeypair) {
    return cache.keypair;
  }

  if (!context.mounted) return null;
  return showVibePinPrompt(context, amountUsdc: amountUsdc);
}

/// Shows a PIN-entry bottom sheet for a Vibe send and returns the resolved
/// signing keypair, or `null` if the user backs out.
///
/// If the session cache is populated, the entered PIN is verified against
/// it (no server round-trip) and the cached keypair is returned. If the
/// cache is empty, the PIN is used to decrypt the keypair directly.
Future<Uint8List?> showVibePinPrompt(
  BuildContext context, {
  required double amountUsdc,
}) {
  return showModalBottomSheet<Uint8List>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _VibePinSheet(amountUsdc: amountUsdc),
  );
}

class _VibePinSheet extends StatefulWidget {
  const _VibePinSheet({required this.amountUsdc});
  final double amountUsdc;

  @override
  State<_VibePinSheet> createState() => _VibePinSheetState();
}

class _VibePinSheetState extends State<_VibePinSheet>
    with SingleTickerProviderStateMixin {
  String _pinDigits = '';
  int _pinAttempts = 0;
  String? _pinError;

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
    setState(() {
      _pinError = null;
      if (value == 'del') {
        if (_pinDigits.isNotEmpty) {
          _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
        }
        return;
      }
      if (_pinDigits.length >= 6) return;
      _pinDigits += value;
    });
    if (_pinDigits.length == 6) {
      _submit();
    }
  }

  Future<void> _submit() async {
    final pin = _pinDigits;
    final model = ZendScope.of(context);
    final cache = WalletSessionCache.instance;

    try {
      if (cache.hasKeypair) {
        final valid = await model.signingPolicyService
            .verifyPinAgainstCache(pin, model.walletService);
        if (!valid) {
          _onRejected(lockOnMaxAttempts: true);
          return;
        }
        if (!mounted) return;
        Navigator.of(context).pop(cache.keypair);
      } else {
        final decrypted = await model.walletService.decryptLocalKeypair(pin);
        if (!mounted) return;
        Navigator.of(context).pop(decrypted);
      }
    } on PinDecryptionException {
      _onRejected(lockOnMaxAttempts: false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pinDigits = '';
        _pinError = 'Something went wrong. Please try again.';
      });
    }
  }

  void _onRejected({required bool lockOnMaxAttempts}) {
    if (!mounted) return;
    _pinAttempts++;
    if (_pinAttempts >= 5) {
      if (lockOnMaxAttempts) {
        ZendScope.of(context).appLockService.lock();
      }
      // Too many attempts — close the sheet as a cancellation. The user
      // will need to unlock the app (if locked) or simply retry the Vibe.
      Navigator.of(context).pop();
      return;
    }
    _shakeController.forward(from: 0);
    setState(() {
      _pinDigits = '';
      _pinError = 'Incorrect PIN';
    });
  }

  String get _amountFormatted {
    if (widget.amountUsdc == widget.amountUsdc.roundToDouble()) {
      return '\$${widget.amountUsdc.toStringAsFixed(0)}';
    }
    return '\$${widget.amountUsdc.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final compact = screenHeight < 760;

    return Container(
      height: screenHeight * 0.62,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(Icons.close, color: zt.textPrimary, size: 22),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Confirm $_amountFormatted Vibe',
              style: TextStyle(
                fontFamily: 'CircularStd',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: zt.textPrimary,
              ),
            ),
            SizedBox(height: compact ? 20 : 28),
            AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                );
              },
              child: SendPinDots(filledCount: _pinDigits.length),
            ),
            const SizedBox(height: 10),
            Text(
              _pinError ?? 'Enter your PIN',
              style: TextStyle(
                fontFamily: 'CircularStd',
                fontSize: 13,
                color: _pinError != null
                    ? ZendColors.destructive
                    : zt.textSecondary,
              ),
            ),
            const Spacer(),
            SendPinKeypad(onTap: _onKey, keyHeight: compact ? 56 : 64),
            SizedBox(height: compact ? 4 : 12),
          ],
        ),
      ),
    );
  }
}
