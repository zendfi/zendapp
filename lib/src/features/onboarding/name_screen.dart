import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import 'username_screen.dart';

class NameScreen extends StatefulWidget {
  const NameScreen({super.key});

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  void _onContinue() {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final displayName = [first, last].where((part) => part.isNotEmpty).join(' ');

    final model = ZendScope.of(context);
    model.setDisplayName(displayName);

    pushZendSlide(context, const UsernameScreen());
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
                      controller: _firstName,
                      decoration: const InputDecoration(
                        hintText: 'First name',
                        filled: false,
                        border: UnderlineInputBorder(borderSide: BorderSide(color: ZendColors.border)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _lastName,
                      decoration: const InputDecoration(
                        hintText: 'Last name',
                        filled: false,
                        border: UnderlineInputBorder(borderSide: BorderSide(color: ZendColors.border)),
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
