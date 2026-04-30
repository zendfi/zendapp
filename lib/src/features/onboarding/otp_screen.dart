import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import 'name_screen.dart';
import 'pin_restore_screen.dart';
import '../shell/zend_shell.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  late final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  late final Timer _timer;
  Duration _remaining = const Duration(seconds: 42);
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
    _timer.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
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
            navigator.pushAndRemoveUntil(zendRoute(page: const ZendShell()), (route) => false);
          } else {
            navigator.pushAndRemoveUntil(zendRoute(page: const PinRestoreScreen()), (route) => false);
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
      } else if (e.errorCode == 'OTP_EXPIRED' || e.errorCode == 'OTP_MAX_ATTEMPTS') {
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
                    Text(
                      'Enter the code',
                      style: const TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sent to +234 ••• ••• 4521',
                      style: TextStyle(color: ZendColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: List.generate(6, (index) {
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
                            child: _OtpBox(
                              controller: _controllers[index],
                              focusNode: _focusNodes[index],
                              onChanged: (value) {
                                if (value.isNotEmpty && index < 5) {
                                  _focusNodes[index + 1].requestFocus();
                                }
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorText!,
                        style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: ZendColors.destructive,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Resend in ${_remaining.inMinutes}:${(_remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 13,
                        color: ZendColors.textSecondary,
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
  const _OtpBox({required this.controller, required this.focusNode, required this.onChanged});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        maxLength: 1,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontFamily: 'DMSans', fontSize: 20, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(
          counterText: '',
          filled: true,
          fillColor: ZendColors.bgSecondary,
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(ZendRadii.lg)), borderSide: BorderSide.none),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
