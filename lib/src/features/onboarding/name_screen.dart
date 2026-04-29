import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'username_screen.dart';

class NameScreen extends StatelessWidget {
  const NameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firstName = TextEditingController(text: 'Blessed');
    final lastName = TextEditingController(text: 'Oyinbo');

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
                      "What's your name?",
                      style: const TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: firstName,
                      decoration: const InputDecoration(
                        hintText: 'First name',
                        filled: false,
                        border: UnderlineInputBorder(borderSide: BorderSide(color: ZendColors.border)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: lastName,
                      decoration: const InputDecoration(
                        hintText: 'Last name',
                        filled: false,
                        border: UnderlineInputBorder(borderSide: BorderSide(color: ZendColors.border)),
                      ),
                    ),
                    const Spacer(),
                    PrimaryButton(
                      label: 'Continue',
                      onPressed: () {
                        pushZendSlide(context, const UsernameScreen());
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
