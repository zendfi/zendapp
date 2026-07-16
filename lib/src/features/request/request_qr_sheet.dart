import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'payment_request.dart';

/// Full-screen modal sheet showing the QR code for a payment request.
///
/// Presented when the user taps "Show QR" on the request success stage.
/// Contains the QR, Download, Copy Link, and Share actions.
Future<void> showRequestQrSheet(
  BuildContext context, {
  required PaymentRequest request,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RequestQrSheet(request: request),
  );
}

class RequestQrSheet extends StatefulWidget {
  const RequestQrSheet({super.key, required this.request});

  final PaymentRequest request;

  @override
  State<RequestQrSheet> createState() => _RequestQrSheetState();
}

class _RequestQrSheetState extends State<RequestQrSheet> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _saving = false;

  String get _link => widget.request.link;

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return '\$${amount.toStringAsFixed(0)}';
    }
    return '\$${amount.toStringAsFixed(2)}';
  }

  Future<Uint8List> _captureQr() async {
    await Future<void>.delayed(Duration.zero);
    final boundary = _repaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) throw Exception('Could not find QR render object');
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Failed to encode QR as PNG');
    return byteData.buffer.asUint8List();
  }

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _captureQr();
      await Gal.putImageBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR saved to gallery'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save QR'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _captureQr();
      final xFile = XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: 'zend_request_qr.png',
      );
      await Share.shareXFiles([xFile], text: _link);
    } catch (_) {
      await Share.share(_link);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          const ZendSheetHandle(),
          const SizedBox(height: 20),

          // ── Amount + description ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Builder(
              builder: (context) {
                final zt = ZendTheme.of(context);
                return Column(
                  children: [
                    Text(
                      _formatAmount(widget.request.amount),
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontStyle: FontStyle.italic,
                        fontSize: 40,
                        color: zt.textPrimary,
                        height: 1.0,
                      ),
                    ),
                    if (widget.request.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.request.description,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 14,
                          color: zt.textSecondary,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // ── QR code ───────────────────────────────────────────────────────
          Expanded(
            child: Center(
              child: RepaintBoundary(
                key: _repaintKey,
                child: Builder(builder: (ctx) {
                  final zt = ZendTheme.of(ctx);
                  final moduleColor = zt.isDark ? const Color(0xFFE8F4EC) : const Color(0xFF122018);
                  final eyeColor   = zt.isDark ? const Color(0xFF52B788)  : const Color(0xFF2D6A4F);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      QrImageView(
                        data: _link,
                        version: QrVersions.auto,
                        size: 248,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                        // No backgroundColor — transparent, blends with sheet background.
                        eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.circle,
                          color: eyeColor,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.circle,
                          color: moduleColor,
                        ),
                      ),
                      // Centre logo sits on the sheet's own background color
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: zt.bgPrimary,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Image.asset('assets/logo/Zend.png'),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Actions ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Primary: Show QR full-screen (download)
                PrimaryButton(
                  label: _saving ? 'Saving…' : 'Download QR',
                  onPressed: _saving ? null : _download,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlineActionButton(
                        label: 'Copy link',
                        onPressed: _copyLink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlineActionButton(
                        label: 'Share',
                        onPressed: _saving ? () {} : _share,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
