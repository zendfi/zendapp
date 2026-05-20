import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'payment_request.dart';
import 'request_utils.dart';

/// Full-screen confirmation — used when navigating to a standalone screen.
class RequestConfirmationScreen extends StatelessWidget {
  const RequestConfirmationScreen({
    super.key,
    required this.paymentRequest,
  });

  final PaymentRequest paymentRequest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: RequestConfirmationContent(paymentRequest: paymentRequest),
      ),
    );
  }
}

/// Embeddable confirmation content — used when morphing the request drawer
/// sheet in-place after successful creation.
class RequestConfirmationContent extends StatelessWidget {
  const RequestConfirmationContent({
    super.key,
    required this.paymentRequest,
  });

  final PaymentRequest paymentRequest;

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: paymentRequest.link)).then((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link copied!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
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
              paymentRequest.recipientZendtag != null
                  ? 'Request sent to @${paymentRequest.recipientZendtag}!'
                  : paymentRequest.recipientEmail != null
                      ? 'Request emailed!'
                      : 'Link created!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: ZendColors.textOnDeep,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),

            if (paymentRequest.recipientZendtag != null)
              const Text(
                "They'll get a notification to pay you.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: Color(0x99E8F4EC),
                ),
              )
            else if (paymentRequest.recipientEmail != null)
              Text(
                "Sent to ${paymentRequest.recipientEmail}",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: Color(0x99E8F4EC),
                ),
              ),
            const SizedBox(height: 16),

            Text(
              paymentRequest.link,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'DMMono',
                fontSize: 16,
                color: Color(0x99E8F4EC),
              ),
            ),
            const SizedBox(height: 8),

            Text(
              formatRequestAmount(paymentRequest.amount),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 16,
                color: Color(0x99E8F4EC),
              ),
            ),
            const SizedBox(height: 48),

            PrimaryButton(
              label: 'Copy link',
              backgroundColor: ZendColors.accentBright,
              foregroundColor: ZendColors.textPrimary,
              onPressed: () => _copyLink(context),
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 48,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _copyLink(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ZendColors.textOnDeep,
                  side: const BorderSide(color: Color(0x33E8F4EC)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZendRadii.pill)),
                ),
                child: const Text(
                  'Share',
                  style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),

            TextButton(
              onPressed: () {
                Navigator.of(context, rootNavigator: true).pop();
              },
              child: const Text(
                'Done',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ZendColors.textOnDeep,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
