import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: RequestConfirmationContent(paymentRequest: paymentRequest),
      ),
    );
  }
}

/// Embeddable confirmation content — used when morphing the request drawer
/// sheet in-place after successful creation.
class RequestConfirmationContent extends StatefulWidget {
  const RequestConfirmationContent({
    super.key,
    required this.paymentRequest,
  });

  final PaymentRequest paymentRequest;

  @override
  State<RequestConfirmationContent> createState() =>
      _RequestConfirmationContentState();
}

class _RequestConfirmationContentState
    extends State<RequestConfirmationContent> {
  void _copyLink() {
    Clipboard.setData(ClipboardData(text: widget.paymentRequest.link))
        .then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link copied!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Future<void> _downloadRequestQr() async {
    try {
      final painter = QrPainter(
        data: widget.paymentRequest.link,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.circle,
          color: Color(0xFF52B787),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.circle,
          color: Color(0xFFE8F4EC),
        ),
      );
      final imageData = await painter.toImageData(512);
      if (imageData == null) throw Exception('Failed to generate QR image');
      await Gal.putImageBytes(imageData.buffer.asUint8List());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR saved to gallery'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().contains('permission')
                ? 'Storage permission required to save QR'
                : 'Failed to save QR — please try again'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),

            CircleAvatar(
              radius: 48,
              backgroundColor: ZendColors.positive.withValues(alpha: 0.12),
              child: const Icon(Icons.check_rounded,
                  size: 48, color: ZendColors.positive),
            ),
            const SizedBox(height: 32),

            Text(
              widget.paymentRequest.recipientZendtag != null
                  ? 'Request sent to @${widget.paymentRequest.recipientZendtag}!'
                  : widget.paymentRequest.recipientEmail != null
                      ? 'Request emailed!'
                      : 'Link created!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: zt.textPrimary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),

            if (widget.paymentRequest.recipientZendtag != null)
              Text(
                "They'll get a notification to pay you.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: zt.textSecondary,
                ),
              )
            else if (widget.paymentRequest.recipientEmail != null)
              Text(
                "Sent to ${widget.paymentRequest.recipientEmail}",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: zt.textSecondary,
                ),
              ),
            const SizedBox(height: 16),

            Text(
              widget.paymentRequest.link,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 13,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: 6),

            Text(
              formatRequestAmount(widget.paymentRequest.amount),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 40),

            // QR code for the request link — branded dark treatment
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrImageView(
                    data: widget.paymentRequest.link,
                    version: QrVersions.auto,
                    size: 180,
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                    backgroundColor: const Color(0xFF1C2B1E),
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.circle,
                      color: Color(0xFF52B787),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: Color(0xFFE8F4EC),
                    ),
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1C2B1E),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Image.asset('assets/logo/Zend.png'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlineActionButton(
              label: 'Download QR',
              onPressed: _downloadRequestQr,
            ),
            const SizedBox(height: 16),

            PrimaryButton(
              label: 'Copy link',
              backgroundColor: zt.accent,
              foregroundColor: ZendColors.textOnDeep,
              onPressed: _copyLink,
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 48,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _copyLink,
                style: OutlinedButton.styleFrom(
                  foregroundColor: zt.textPrimary,
                  side: BorderSide(color: zt.border),
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
              child: Text(
                'Done',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: zt.textSecondary,
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
