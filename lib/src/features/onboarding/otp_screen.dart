import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import 'name_screen.dart';
import 'pin_restore_screen.dart';
import '../shell/zend_shell.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    this.contactHint,
    this.isEmail = false,
  });

  /// The phone number or email the code was sent to (for display only).
  final String? contactHint;

  /// Whether the OTP was sent to an email address (vs phone).
  final bool isEmail;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  late final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  late Timer _countdownTimer;
  Duration _remaining = const Duration(seconds: 42);
  String? _errorText;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remaining.inSeconds == 0) {
        timer.cancel();
        return;
      }
      setState(() {
        _remaining -= const Duration(seconds: 1);
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _focusPrevious(int index) {
    if (index <= 0) return;
    _controllers[index - 1].clear();
    _focusNodes[index - 1].requestFocus();
  }

  void _focusNext(int index) {
    if (index >= _controllers.length - 1) return;
    _focusNodes[index + 1].requestFocus();
  }

  void _handleBackspace(int index) {
    final current = _controllers[index];
    if (current.text.isNotEmpty) {
      current.clear();
      return;
    }
    _focusPrevious(index);
  }

  String get _subtitleText {
    if (widget.contactHint != null && widget.contactHint!.isNotEmpty) {
      return 'Sent to ${widget.contactHint}';
    }
    return widget.isEmail ? 'Sent to your email' : 'Sent to your phone number';
  }

  Future<void> _resend() async {
    if (_resending || widget.contactHint == null) return;
    setState(() {
      _resending = true;
      _errorText = null;
    });

    final model = ZendScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (widget.isEmail) {
        await model.authService.requestOtpByEmail(widget.contactHint!);
      } else {
        await model.authService.requestOtp(widget.contactHint!);
      }

      if (!mounted) return;

      // Clear all OTP boxes and refocus the first
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();

      // Reset and restart the countdown
      _countdownTimer.cancel();
      setState(() {
        _remaining = const Duration(seconds: 42);
        _resending = false;
      });
      _startCountdown();

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Code resent!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _resending = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to resend. Please try again.')),
      );
    }
  }

  Future<void> _onContinue() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length < 6) return;

    setState(() => _errorText = null);

    final model = ZendScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    model.startLoading('Verifying code...');

    try {
      final response = await model.authService.verifyOtp(code);
      model.stopLoading();
      if (!mounted) return;

      if (!response.userExists) {
        navigator.push(zendRoute(page: const NameScreen()));
      } else {
        model.startLoading('Signing in...');
        try {
          final authResponse = await model.authService.signIn();
          model.stopLoading();
          if (!mounted) return;

          model.setAuthenticated(
            userId: authResponse.userId,
            zendtag: authResponse.zendtag,
            displayName: authResponse.zendtag,
          );

          final hasKeypair = await model.walletService.hasLocalKeypair();
          if (!mounted) return;

          if (hasKeypair) {
            navigator.pushAndRemoveUntil(
                zendRoute(page: const ZendShell()), (route) => false);
          } else {
            navigator.pushAndRemoveUntil(
                zendRoute(page: const PinRestoreScreen()), (route) => false);
          }
        } catch (e) {
          model.stopLoading();
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(content: Text('Sign in failed. Please try again.')),
          );
        }
      }
    } on ApiException catch (e) {
      model.stopLoading();
      if (!mounted) return;

      if (e.errorCode == 'INVALID_OTP_CODE') {
        setState(() => _errorText = e.userMessage);
      } else if (e.errorCode == 'OTP_EXPIRED' ||
          e.errorCode == 'OTP_MAX_ATTEMPTS') {
        messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
        navigator.pop();
      } else {
        setState(() => _errorText = e.userMessage);
      }
    } catch (e) {
      model.stopLoading();
      if (!mounted) return;
      setState(() => _errorText = 'Something went wrong. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ZendScrollPage(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 44),
                    const Text(
                      'Enter the code',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _subtitleText,
                      style: const TextStyle(
                          color: ZendColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: List.generate(6, (index) {
                        return Expanded(
                          child: Padding(
                            padding:
                                EdgeInsets.only(right: index == 5 ? 0 : 6),
                            child: _OtpBox(
                              controller: _controllers[index],
                              focusNode: _focusNodes[index],
                              onChanged: (value) {
                                if (value.isNotEmpty) {
                                  if (value.length > 1) {
                                    _controllers[index].text =
                                        value.characters.last.toString();
                                    _controllers[index].selection =
                                        const TextSelection.collapsed(
                                            offset: 1);
                                  }
                                  _focusNext(index);
                                }
                              },
                              onBackspace: () => _handleBackspace(index),
                            ),
                          ),
                        );
                      }),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errorText!,
                        style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: ZendColors.destructive,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_remaining.inSeconds > 0)
                      Text(
                        'Resend in ${_remaining.inMinutes}:${(_remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 13,
                          color: ZendColors.textSecondary,
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _resending ? null : _resend,
                        child: _resending
                            ? const Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ZendColors.textSecondary,
                                  ),
                                ),
                              )
                            : const Text(
                                'Resend code',
                                style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: ZendColors.accentPop,
                                  decoration: TextDecoration.underline,
                                  decorationColor: ZendColors.accentPop,
                                ),
                              ),
                      ),
                    const Spacer(),
                    PrimaryButton(
                      label: 'Continue',
                      onPressed: _onContinue,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          if (controller.text.isEmpty) {
            onBackspace();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        height: 56,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          maxLength: 1,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: ZendColors.textPrimary,
          ),
          decoration: const InputDecoration(
            counterText: '',
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 0, vertical: 12),
            filled: true,
            fillColor: ZendColors.bgSecondary,
            border: OutlineInputBorder(
              borderRadius:
                  BorderRadius.all(Radius.circular(ZendRadii.lg)),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
