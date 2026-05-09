import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key, required this.username});

  final String username;

  String get _paymentLink => 'https://zdfi.me/$username';

  Future<void> _shareLink(BuildContext context) async {
    await Share.share(
      'Pay me with Zend! App 💸\n$_paymentLink',
      subject: 'My Zend! payment link',
    );
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _paymentLink));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link copied to clipboard'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZendColors.bgPrimary,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: ZendColors.textPrimary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'Receive',
                    style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: ZendColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ZendScrollPage(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── QR card ──
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: ZendColors.bgDeep,
                          borderRadius: BorderRadius.circular(ZendRadii.xl),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'zdfi.me/$username',
                              style: const TextStyle(
                                fontFamily: 'DMMono',
                                color: Color(0x99E8F4EC),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Real QR code pointing to zdfi.me/username
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(ZendRadii.lg),
                              ),
                              child: QrImageView(
                                data: _paymentLink,
                                version: QrVersions.auto,
                                size: 160,
                                backgroundColor: Colors.white,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Colors.black,
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Scan to pay @$username',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'DMSans',
                                color: Color(0x99E8F4EC),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Copy link row
                            GestureDetector(
                              onTap: () => _copyLink(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0x1AE8F4EC),
                                  borderRadius:
                                      BorderRadius.circular(ZendRadii.pill),
                                  border: Border.all(
                                      color: const Color(0x26E8F4EC)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.copy_outlined,
                                        size: 14,
                                        color: Color(0x99E8F4EC)),
                                    const SizedBox(width: 6),
                                    Text(
                                      _paymentLink,
                                      style: const TextStyle(
                                        fontFamily: 'DMMono',
                                        color: Color(0x99E8F4EC),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Share button — opens native share sheet ──
                      PrimaryButton(
                        label: 'Share payment link',
                        onPressed: () => _shareLink(context),
                      ),
                      const SizedBox(height: 12),
                      OutlineActionButton(
                        label: 'Create payment request',
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: const Text(
                          'Customise your page',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            color: ZendColors.accent,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
