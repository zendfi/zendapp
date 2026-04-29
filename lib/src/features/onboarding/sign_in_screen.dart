import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../shell/zend_shell.dart';
import '../../core/zend_state.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final canContinue = _usernameController.text.trim().isNotEmpty && _passwordController.text.isNotEmpty;

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
                      'Welcome back',
                      style: const TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in with your username and password.',
                      style: TextStyle(fontSize: 14, color: ZendColors.textSecondary),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _usernameController,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: '@blessed',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      onChanged: (_) => setState(() {}),
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ),
                    ),
                    const Spacer(),
                    PrimaryButton(
                      label: 'Sign in',
                      onPressed: canContinue
                          ? () async {
                              model.startLoading('Signing in...');
                              await Future.delayed(const Duration(milliseconds: 1200));
                              model.refreshGreeting();
                              model.stopLoading();
                              if (!context.mounted) return;
                              pushAndRemoveUntilZendSlide(context, const ZendShell());
                            }
                          : () {},
                      backgroundColor: canContinue ? ZendColors.accent : ZendColors.border,
                      foregroundColor: canContinue ? ZendColors.textOnDeep : ZendColors.textSecondary,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Create a new account',
                        style: TextStyle(color: ZendColors.textSecondary),
                      ),
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
