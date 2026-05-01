import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'success_screen.dart';

class KycScreen extends StatelessWidget {
  const KycScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final controller = TextEditingController(text: '12345678901');

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
                    const SizedBox(height: 40),
                    Text(
                      'Verify your identity',
                      style: const TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Required to send money. Takes 30 seconds.',
                      style: TextStyle(color: ZendColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontFamily: 'DMMono', fontSize: 18),
                      decoration: const InputDecoration(hintText: 'BVN'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                      child: const Text(
                        'Why we need this ›',
                        style: TextStyle(color: ZendColors.textSecondary),
                      ),
                    ),
                    const Spacer(),
                    PrimaryButton(
                      label: 'Verify',
                      onPressed: () async {
                        model.startLoading('Verifying identity...');
                        await Future.delayed(const Duration(milliseconds: 2000));
                        model.stopLoading();
                        if (!context.mounted) return;
                        pushReplacementZendSlide(
                          context,
                          SuccessScreen(username: model.username),
                        );
                      },
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
