import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/zend_tokens.dart';

// ─── QR Style model ───────────────────────────────────────────────────────────

/// A named color palette for the branded QR card.
///
/// [dotColor]  — color of the QR data modules and finder eyes.
/// [cardBg]    — background color of the card face.
/// [textColor] — color for the @username and url text on the card.
/// [isDark]    — whether to use a dark card bg (affects logo rendering).
class QrStyle {
  final String id;
  final String label;
  final Color dotColor;
  final Color cardBg;
  final Color textColor;
  final Color textMuted;
  final bool isDark;

  const QrStyle({
    required this.id,
    required this.label,
    required this.dotColor,
    required this.cardBg,
    required this.textColor,
    required this.textMuted,
    required this.isDark,
  });
}

/// The five built-in QR palettes.
const List<QrStyle> kQrPresets = [
  // Forest — current brand default
  QrStyle(
    id: 'forest',
    label: 'Forest',
    dotColor: Color(0xFF52B787),
    cardBg: Color(0xFF1C2B1E),
    textColor: Color(0xFFE8F4EC),
    textMuted: Color(0x99E8F4EC),
    isDark: true,
  ),
  // Midnight — pure white on black
  QrStyle(
    id: 'midnight',
    label: 'Midnight',
    dotColor: Color(0xFFFFFFFF),
    cardBg: Color(0xFF0A0A0A),
    textColor: Color(0xFFFFFFFF),
    textMuted: Color(0x99FFFFFF),
    isDark: true,
  ),
  // Ember — warm amber on deep brown-black
  QrStyle(
    id: 'ember',
    label: 'Ember',
    dotColor: Color(0xFFE8A045),
    cardBg: Color(0xFF1A1208),
    textColor: Color(0xFFF5E8D0),
    textMuted: Color(0x99F5E8D0),
    isDark: true,
  ),
  // Sky — ocean blue on white
  QrStyle(
    id: 'sky',
    label: 'Sky',
    dotColor: Color(0xFF3B82F6),
    cardBg: Color(0xFFFFFFFF),
    textColor: Color(0xFF1E293B),
    textMuted: Color(0xFF64748B),
    isDark: false,
  ),
  // Mono — classic black on white
  QrStyle(
    id: 'mono',
    label: 'Mono',
    dotColor: Color(0xFF111111),
    cardBg: Color(0xFFFFFFFF),
    textColor: Color(0xFF111111),
    textMuted: Color(0xFF6B7280),
    isDark: false,
  ),
];

const String _kPrefKey = 'qr_style_id';

// ─── ZendQrCard ───────────────────────────────────────────────────────────────

/// The branded Zend! QR card with live color-preset customisation.
///
/// Layout:
///   ┌─────────────────────────┐
///   │   [card face — varies]  │
///   └─────────────────────────┘
///   [ ● ● ● ● ●  ]  ← swatch row
///   [Share]  [Download]
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
  QrStyle _style = kQrPresets.first;

  @override
  void initState() {
    super.initState();
    _loadSavedStyle();
  }

  Future<void> _loadSavedStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kPrefKey);
    if (id == null) return;
    final match = kQrPresets.where((s) => s.id == id).firstOrNull;
    if (match != null && mounted) setState(() => _style = match);
  }

  Future<void> _selectStyle(QrStyle style) async {
    setState(() => _style = style);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, style.id);
  }

  // ── Capture + export ──────────────────────────────────────────────────────

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
        // ── Card face ────────────────────────────────────────────────────
        RepaintBoundary(
          key: _repaintKey,
          child: _CardFace(
            username: widget.username,
            paymentUrl: widget.paymentUrl,
            style: _style,
          ),
        ),
        const SizedBox(height: 16),

        // ── Style swatch row ─────────────────────────────────────────────
        _SwatchRow(
          presets: kQrPresets,
          selected: _style,
          onSelect: _selectStyle,
        ),
        const SizedBox(height: 14),

        // ── Action buttons ───────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _CardButton(
                icon: Icons.share_outlined,
                label: 'Share card',
                loading: _saving,
                onTap: shareCard,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CardButton(
                icon: Icons.download_outlined,
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

// ─── Swatch row ────────────────────────────────────────────────────────────

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.presets,
    required this.selected,
    required this.onSelect,
  });

  final List<QrStyle> presets;
  final QrStyle selected;
  final ValueChanged<QrStyle> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: presets.map((style) {
        final isSelected = style.id == selected.id;
        return GestureDetector(
          onTap: () => onSelect(style),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: isSelected ? 34 : 28,
            height: isSelected ? 34 : 28,
            decoration: BoxDecoration(
              color: style.dotColor,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                      color: style.dotColor.withValues(alpha: 0.3),
                      width: 3,
                    )
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: style.dotColor.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

// ─── Card face ─────────────────────────────────────────────────────────────

/// Static layout — rendered identically on-screen and via RepaintBoundary export.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.username,
    required this.paymentUrl,
    required this.style,
  });

  final String username;
  final String paymentUrl;
  final QrStyle style;

  static const double _cardWidth = 360.0;
  static const double _cardPadding = 28.0;
  static const double _qrSize = 228.0;
  static const double _borderRadius = 20.0;

  @override
  Widget build(BuildContext context) {
    final borderColor = style.isDark
        ? style.dotColor.withValues(alpha: 0.2)
        : style.dotColor.withValues(alpha: 0.15);

    return Center(
      child: Container(
        width: _cardWidth,
        decoration: BoxDecoration(
          color: style.cardBg,
          borderRadius: BorderRadius.circular(_borderRadius),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: _cardPadding,
          vertical: 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Wordmark ────────────────────────────────────────────────
            Image.asset(
              'assets/logo/Zend.png',
              height: 32,
            ),
            const SizedBox(height: 28),

            // ── Branded QR with logo overlay ─────────────────────────────
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
                    backgroundColor: style.cardBg,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.circle,
                      color: style.dotColor,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: style.isDark
                          ? const Color(0xFFE8F4EC)
                          : style.dotColor,
                    ),
                  ),
                  // Center logo badge
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: style.cardBg,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(9),
                    child: Image.asset('assets/logo/Zend.png'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── URL ──────────────────────────────────────────────────────
            Text(
              'zdfi.me/@$username',
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 13,
                color: style.textMuted,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),

            // ── @username ────────────────────────────────────────────────
            Text(
              '@$username',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 26,
                fontStyle: FontStyle.italic,
                color: style.textColor,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 16),

            // ── Divider ──────────────────────────────────────────────────
            Container(
              height: 1,
              color: style.isDark
                  ? const Color(0x26E8F4EC)
                  : style.dotColor.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 16),

            // ── Tagline ──────────────────────────────────────────────────
            Text(
              'Scan to pay instantly',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: style.textMuted,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Action button ─────────────────────────────────────────────────────────

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
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0x99E8F4EC)),
                ),
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
