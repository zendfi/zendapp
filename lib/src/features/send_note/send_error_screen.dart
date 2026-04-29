import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class SendErrorScreen extends StatelessWidget {
  const SendErrorScreen({
    super.key,
    required this.errorMessage,
    required this.onRetry,
  });

  final String errorMessage;
  final VoidCallback onRetry;

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
                CircleAvatar(
                  radius: 48,
                  backgroundColor: ZendColors.destructive.withValues(alpha: 0.2),
                  child: const Icon(Icons.close, size: 48, color: ZendColors.destructive),
                ),
                const SizedBox(height: 32),
                Text(
                  'Oops',
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
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 16,
                    color: Color(0x99E8F4EC),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                PrimaryButton(
                  label: 'Retry',
                  backgroundColor: ZendColors.accentBright,
                  foregroundColor: ZendColors.textPrimary,
                  onPressed: () {
                    Navigator.of(context).pop();
                    onRetry();
                  },
                ),
                const SizedBox(height: 12),
                OutlineActionButton(
                  label: 'Cancel',
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
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
