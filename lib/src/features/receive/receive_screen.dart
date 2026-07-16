import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'nfc_write_screen.dart';
import 'zend_qr_card.dart';
import 'package:solar_icons/solar_icons.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key, required this.username});

  final String username;

  String get _paymentLink => 'https://zdfi.me/@$username';

  Future<void> _shareLink() async {
    await Share.share(
      'Pay me with Zend! App 💸\n$_paymentLink',
      subject: 'My Zend! payment link',
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(SolarIconsBold.altArrowLeft, color: zt.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    'Receive',
                    style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary,
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
                      ZendQrCard(
                        username: username,
                        paymentUrl: _paymentLink,
                      ),
                      const SizedBox(height: 12),

                      PrimaryButton(
                        label: 'Share payment link',
                        onPressed: _shareLink,
                      ),
                      const SizedBox(height: 12),

                      OutlineActionButton(
                        label: 'Write NFC tag',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NfcWriteScreen(
                              paymentUrl: _paymentLink,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      OutlineActionButton(
                        label: 'Create payment request',
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                      const SizedBox(height: 22),

                      Center(
                        child: Text(
                          'Customise your page',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            color: zt.accent,
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
