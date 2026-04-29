import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../navigation/zend_routes.dart';
import '../shell/zend_shell.dart';

class SendSuccessScreen extends StatelessWidget {
  const SendSuccessScreen({
    super.key,
    required this.recipientName,
    required this.amount,
  });

  final String recipientName;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const CircleAvatar(
                  radius: 48,
                  backgroundColor: ZendColors.accentPop,
                  child: Icon(Icons.check, size: 48, color: ZendColors.textPrimary),
                ),
                const SizedBox(height: 32),
                Text(
                  'Zent It!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: ZendColors.textOnDeep,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '\$${amount.toStringAsFixed(2)} to @$recipientName',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 16,
                    color: Color(0x99E8F4EC),
                  ),
                ),
                const SizedBox(height: 48),
                PrimaryButton(
                  label: 'Done',
                  backgroundColor: ZendColors.accentBright,
                  foregroundColor: ZendColors.textPrimary,
                  onPressed: () {
                    pushAndRemoveUntilZendSlide(context, const ZendShell(), rootNavigator: true);
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
