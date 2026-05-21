import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/qr_payment_intent.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key, required this.username});

  final String username;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _fixedAmountUrl = '';
  bool _downloadingQr = false;

  String get _paymentLink => 'https://zdfi.me/${widget.username}';

  @override
  void initState() {
    super.initState();
    _buildFixedAmountUrl();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _buildFixedAmountUrl() {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);
    if (amount != null && amount > 0) {
      final note = _noteController.text.trim();
      setState(() {
        _fixedAmountUrl = QrPaymentIntent.buildFixedAmountUrl(
          widget.username,
          amount,
          note.isNotEmpty ? note : null,
        );
      });
    } else {
      setState(() {
        _fixedAmountUrl = '';
      });
    }
  }

  Future<void> _downloadQr(String url, String filename) async {
    if (_downloadingQr) return;
    setState(() => _downloadingQr = true);
    try {
      final painter = QrPainter(
        data: url,
        version: QrVersions.auto,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF000000),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF000000),
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
    } finally {
      if (mounted) setState(() => _downloadingQr = false);
    }
  }

  Future<void> _shareLink() async {
    await Share.share(
      'Pay me with Zend! App 💸\n$_paymentLink',
      subject: 'My Zend! payment link',
    );
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _paymentLink));
    if (mounted) {
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
    final zt = ZendTheme.of(context);
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
                              'zdfi.me/${widget.username}',
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
                                borderRadius:
                                    BorderRadius.circular(ZendRadii.lg),
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
                              'Scan to pay @${widget.username}',
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
                              onTap: _copyLink,
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
                        onPressed: _shareLink,
                      ),
                      const SizedBox(height: 12),

                      // ── Download QR button ──
                      OutlineActionButton(
                        label: _downloadingQr ? 'Saving…' : 'Download QR',
                        onPressed: _downloadingQr
                            ? () {}
                            : () => _downloadQr(_paymentLink, 'zend_qr'),
                      ),
                      const SizedBox(height: 12),

                      // ── Create payment request button ──
                      OutlineActionButton(
                        label: 'Create payment request',
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                      const SizedBox(height: 16),

                      // ── Fixed-amount QR card ──
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: zt.bgSecondary,
                          borderRadius: BorderRadius.circular(ZendRadii.xl),
                          border: Border.all(color: zt.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Fixed amount QR',
                              style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 13,
                                color: zt.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Amount input
                            TextField(
                              controller: _amountController,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              style: TextStyle(
                                fontFamily: 'DMMono',
                                fontSize: 15,
                                color: zt.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: r'$0.00',
                                hintStyle: TextStyle(
                                  fontFamily: 'DMMono',
                                  fontSize: 15,
                                  color: zt.textSecondary,
                                ),
                                filled: true,
                                fillColor: zt.bgPrimary,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(ZendRadii.md),
                                  borderSide: BorderSide(color: zt.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(ZendRadii.md),
                                  borderSide: BorderSide(color: zt.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(ZendRadii.md),
                                  borderSide: BorderSide(color: zt.accent),
                                ),
                              ),
                              onChanged: (_) => _buildFixedAmountUrl(),
                            ),
                            const SizedBox(height: 8),
                            // Note input
                            TextField(
                              controller: _noteController,
                              style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 15,
                                color: zt.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: "What's it for? (optional)",
                                hintStyle: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 15,
                                  color: zt.textSecondary,
                                ),
                                filled: true,
                                fillColor: zt.bgPrimary,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(ZendRadii.md),
                                  borderSide: BorderSide(color: zt.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(ZendRadii.md),
                                  borderSide: BorderSide(color: zt.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(ZendRadii.md),
                                  borderSide: BorderSide(color: zt.accent),
                                ),
                              ),
                              onChanged: (_) => _buildFixedAmountUrl(),
                            ),
                            if (_fixedAmountUrl.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              // QR preview
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(ZendRadii.lg),
                                  ),
                                  child: QrImageView(
                                    data: _fixedAmountUrl,
                                    version: QrVersions.auto,
                                    size: 160,
                                    backgroundColor: Colors.white,
                                    eyeStyle: const QrEyeStyle(
                                      eyeShape: QrEyeShape.square,
                                      color: Colors.black,
                                    ),
                                    dataModuleStyle: const QrDataModuleStyle(
                                      dataModuleShape:
                                          QrDataModuleShape.square,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Share + Download row
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlineActionButton(
                                      label: 'Share',
                                      onPressed: () =>
                                          Share.share(_fixedAmountUrl),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlineActionButton(
                                      label: 'Download',
                                      onPressed: () => _downloadQr(
                                          _fixedAmountUrl, 'zend_fixed_qr'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
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
