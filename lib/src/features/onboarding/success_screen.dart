import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../../core/zend_state.dart';
import '../shell/zend_shell.dart';

class SuccessScreen extends StatelessWidget {
  const SuccessScreen({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CircleAvatar(
                    radius: 34,
                    backgroundColor: ZendColors.bgSecondary,
                    child: Icon(Icons.person, color: ZendColors.textPrimary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "You're in, @$username",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 28,
                      height: 1.08,
                      color: ZendColors.textOnDeep,
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'zdfi.me/$username',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      color: Color(0x80E8F4EC),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Your payment link is live. Share it anywhere.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0x99E8F4EC),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    label: 'Go to ZendApp',
                    backgroundColor: ZendColors.accentBright,
                    foregroundColor: ZendColors.textPrimary,
                    onPressed: () {
                      ZendScope.of(context).refreshGreeting();
                      pushAndRemoveUntilZendSlide(context, const ZendShell());
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
