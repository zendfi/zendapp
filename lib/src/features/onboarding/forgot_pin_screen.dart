import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import 'recovery_national_id_screen.dart';
import 'package:solar_icons/solar_icons.dart';

/// "Forgot PIN?" entry screen.
///
/// Step 1: Shows the user's email and prompts them to request an OTP.
/// Step 2: OTP entry (6 digits, auto-submits on completion).
/// On success, navigates to [RecoveryNationalIdScreen] with the recovery_token.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key});

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  _Step _step = _Step.request;
  bool _loading = false;
  String? _error;
  String _otpInput = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(SolarIconsBold.altArrowLeft,
                      color: ZendColors.textOnDeep),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _step == _Step.request
                        ? _RequestView(
                            loading: _loading,
                            error: _error,
                            onRequest: _requestOtp,
                          )
                        : _OtpView(
                            loading: _loading,
                            error: _error,
                            otpInput: _otpInput,
                            onKey: _onOtpKey,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestOtp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final model = ZendScope.of(context);
      await model.walletService.apiClient.recoveryInit();
      if (!mounted) return;
      setState(() => _step = _Step.otp);
    } on ApiException catch (e) {
      if (!mounted) return;
      final isRateLimit = e.statusCode == 429;
      setState(() => _error = isRateLimit
          ? 'Too many attempts. Please try again in a few minutes.'
          : e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not send code. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onOtpKey(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      if (value == 'del') {
        if (_otpInput.isNotEmpty) {
          _otpInput = _otpInput.substring(0, _otpInput.length - 1);
        }
      } else if (_otpInput.length < 6) {
        _otpInput += value;
      }
    });

    if (_otpInput.length == 6) {
      _verifyOtp(_otpInput);
    }
  }

  Future<void> _verifyOtp(String otp) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final model = ZendScope.of(context);
      final result = await model.walletService.apiClient.recoveryVerify(otp);
      if (!mounted) return;
      final recoveryToken = result['recovery_token'] as String;
      pushAndRemoveUntilZendSlide(
        context,
        RecoveryNationalIdScreen(recoveryToken: recoveryToken),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _otpInput = '';
        _error = e.statusCode == 401
            ? 'Incorrect code. Please try again.'
            : e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _otpInput = '';
        _error = 'Verification failed. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

enum _Step { request, otp }

// ── Request view ──────────────────────────────────────────────────────────────

class _RequestView extends StatelessWidget {
  const _RequestView({
    required this.loading,
    required this.error,
    required this.onRequest,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Forgot your PIN?',
          style: TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 28,
            color: ZendColors.textOnDeep,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "We'll send a verification code to your email, then you can recover your wallet using your government ID number.",
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 15,
            height: 1.5,
            color: Color(0x99E8F4EC), // textOnDeepSecondary
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2E22), // bgDeepElevated
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(SolarIconsBold.mailbox, color: ZendColors.accentPop, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Code will be sent to your registered email',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    color: Color(0x99E8F4EC),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: ZendColors.destructive,
            ),
          ),
        ],
        const Spacer(),
        if (loading)
          const Center(
              child: ZendLoader(color: ZendColors.accentPop))
        else
          PrimaryButton(
            label: 'Send verification code',
            onPressed: onRequest,
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── OTP view ──────────────────────────────────────────────────────────────────

class _OtpView extends StatelessWidget {
  const _OtpView({
    required this.loading,
    required this.error,
    required this.otpInput,
    required this.onKey,
  });

  final bool loading;
  final String? error;
  final String otpInput;
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Check your inbox',
          style: TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 28,
            color: ZendColors.textOnDeep,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Enter the 6-digit code we sent to your email.',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 15,
            color: Color(0x99E8F4EC),
          ),
        ),
        const SizedBox(height: 32),
        // OTP digit boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < otpInput.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 42,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF1C2E22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: filled
                      ? ZendColors.accentPop
                      : const Color(0xFF1C2E22),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                filled ? otpInput[i] : '',
                style: const TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 22,
                  color: ZendColors.textOnDeep,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        if (error != null)
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: ZendColors.destructive,
            ),
          ),
        const Spacer(),
        if (!loading)
          _OtpKeypad(onTap: onKey)
        else
          const Center(
            child: ZendLoader(color: ZendColors.accentPop),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _OtpKeypad extends StatelessWidget {
  const _OtpKeypad({required this.onTap});
  final ValueChanged<String> onTap;

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
        for (var row = 0; row < 4; row++)
          Row(
            children: [
              for (var col = 0; col < 3; col++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: row < 3 ? 12 : 0,
                      right: col < 2 ? 8 : 0,
                    ),
                    child: _OtpKey(
                      label: _keys[row * 3 + col],
                      onTap: onTap,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _OtpKey extends StatefulWidget {
  const _OtpKey({required this.label, required this.onTap});
  final String label;
  final ValueChanged<String> onTap;

  @override
  State<_OtpKey> createState() => _OtpKeyState();
}

class _OtpKeyState extends State<_OtpKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty) return const SizedBox(height: 52);
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
        scale: _pressed ? 0.9 : 1,
        child: SizedBox(
          height: 52,
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
