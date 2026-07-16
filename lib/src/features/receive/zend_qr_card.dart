import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'package:solar_icons/solar_icons.dart';

/// The branded Zend! QR card — a printable, shareable payment card.
///
/// Layout (on a deep forest green background):
///
///   ┌─────────────────────────┐
///   │   [Zend! wordmark]      │
///   │                         │
///   │      [QR CODE]          │
///   │   (branded dark style)  │
///   │                         │
///   │    zdfi.me/@username    │
///   │    @username            │
///   │                         │
///   │  Scan to pay instantly  │
///   └─────────────────────────┘
///
/// The card is wrapped in a [RepaintBoundary] so it can be captured as a
/// high-resolution PNG via [RenderRepaintBoundary.toImage].
class ZendQrCard extends StatefulWidget {
  const ZendQrCard({
    super.key,
    required this.username,
    required this.paymentUrl,
  });

  final String username;
  final String paymentUrl;

  @override
  State<ZendQrCard> createState() => ZendQrCardState();
}

class ZendQrCardState extends State<ZendQrCard> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _saving = false;

  Future<Uint8List> _captureCard() async {
    await Future<void>.delayed(Duration.zero);
    final boundary = _repaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) throw Exception('Could not find card render object');
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Failed to encode card as PNG');
    return byteData.buffer.asUint8List();
  }

  Future<void> downloadCard() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _captureCard();
      await Gal.putImageBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card saved to gallery'),
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
                ? 'Storage permission required to save card'
                : 'Failed to save card — please try again'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> shareCard() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _captureCard();
      final xFile = XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: 'zend_${widget.username}_qr.png',
      );
      await Share.shareXFiles([xFile], text: 'Pay me with Zend! 💸');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to share card — please try again'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          key: _repaintKey,
          child: _CardFace(
            username: widget.username,
            paymentUrl: widget.paymentUrl,
          ),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: _CardButton(
                icon: SolarIconsBold.share,
                label: 'Share card',
                loading: _saving,
                onTap: shareCard,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CardButton(
                icon: SolarIconsBold.download,
                label: _saving ? 'Saving…' : 'Download card',
                loading: _saving,
                onTap: downloadCard,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Card face ──────────────────────────────────────────────────────────────

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.username,
    required this.paymentUrl,
  });

  final String username;
  final String paymentUrl;

  static const double _cardWidth = 360.0;
  static const double _cardPadding = 28.0;
  static const double _qrSize = 220.0;
  static const double _borderRadius = 20.0;

  static const Color _bg = Color(0xFF1C2B1E);
  static const Color _border = Color(0xFF2D4030);
  static const Color _textOnDeep = Color(0xFFE8F4EC);
  static const Color _textMuted = Color(0x99E8F4EC);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: _cardWidth,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(_borderRadius),
          border: Border.all(color: _border, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: _cardPadding,
          vertical: 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Wordmark
            Image.asset(
              'assets/logo/Zend.png',
              height: 32,
            ),
            const SizedBox(height: 28),

            // Branded QR with center logo overlay
            SizedBox(
              width: _qrSize,
              height: _qrSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrImageView(
                    data: paymentUrl,
                    version: QrVersions.auto,
                    size: _qrSize,
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                    backgroundColor: _bg,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.circle,
                      color: Color(0xFF52B787),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: _textOnDeep,
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: _bg,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(9),
                    child: Image.asset('assets/logo/Zend.png'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // URL
            Text(
              'zdfi.me/@$username',
              style: const TextStyle(
                fontFamily: 'DMMono',
                fontSize: 13,
                color: _textMuted,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),

            // @username
            Text(
              '@$username',
              style: const TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 26,
                fontStyle: FontStyle.italic,
                color: _textOnDeep,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 16),

            Container(height: 1, color: const Color(0x26E8F4EC)),
            const SizedBox(height: 16),

            const Text(
              'Scan to pay instantly',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: _textMuted,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action button ──────────────────────────────────────────────────────────

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0x1AE8F4EC),
          borderRadius: BorderRadius.circular(ZendRadii.pill),
          border: Border.all(color: const Color(0x26E8F4EC)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              ZendLoader(
                size: 16,
                strokeWidth: 1.5,
                color: Color(0x99E8F4EC),
              )
            else
              Icon(icon, size: 16, color: const Color(0x99E8F4EC)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: Color(0xCCE8F4EC),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
