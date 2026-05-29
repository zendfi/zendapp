import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'phone_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: ZendScrollPage(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 96),
                    Text(
                      'Money,\neverywhere.',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 56,
                        height: 1.08,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'One link. Every country. Instantly.',
                      style: TextStyle(fontSize: 16, color: zt.textSecondary, height: 1.35),
                    ),
                    const SizedBox(height: 36),
                    PrimaryButton(
                      label: 'Get started',
                      onPressed: () => pushZendSlide(context, const PhoneScreen()),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => pushZendSlide(context, const PhoneScreen()),
                      child: Text('I already have an account', style: TextStyle(color: zt.textSecondary)),
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
