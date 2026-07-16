import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../design/zend_tokens.dart';
import '../../models/qr_payment_intent.dart';
import '../../services/qr_scanner_state.dart';
import '../pairing/pairing_approval_sheet.dart';
import 'qr_payment_sheet.dart';
import 'package:solar_icons/solar_icons.dart';

/// Full-screen QR scanner that decodes `zdfi.me` payment URLs.
///
/// Pushed via `pushZendSlide(context, const QrScannerScreen())` from
/// `SendScreen._IconPill.onTap`.
///
/// The [MobileScannerController] is instantiated eagerly in [initState]
/// (not lazily) to hit the 300 ms open target.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _controller;

  /// Debounce flag — prevents duplicate processing when multiple frames
  /// decode the same barcode in quick succession.
  bool _hasScanned = false;

  /// Whether the torch is currently on.
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    QrScannerState.setActive(true);
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      // Return raw barcode values only — do not auto-open URLs.
      // Without this, mobile_scanner on Android may fire an intent for
      // URL-type barcodes, which the OS intercepts via the zdfi.me App Link
      // filter before _onDetect receives the raw string.
      returnImage: false,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    QrScannerState.setActive(false);
    _controller.dispose();
    super.dispose();
  }

  // ── Barcode detection ────────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) {
    // Debounce: ignore subsequent frames once a valid scan is in progress.
    if (_hasScanned) return;

    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;

    Uri uri;
    try {
      uri = Uri.parse(rawValue);
    } catch (_) {
      _showErrorSnackBar('Could not read QR code data.');
      return;
    }

    // https://zdfi.me/cli-auth/{code} — "Pay with Zend" CLI device pairing
    // approval link. Must be checked before QrPaymentIntent.fromUri, since
    // that parser treats any non-empty first path segment as a zendtag and
    // would otherwise misread "cli-auth" as one, sending this down the
    // payment-intent path where it 404s as a nonexistent payment request.
    // Mirrors DeepLinkHandler._parse's cli-auth branch — this is the same
    // link, just scanned via the in-app camera instead of the OS/App Link.
    if (uri.host.toLowerCase() == 'zdfi.me' &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments[0] == 'cli-auth' &&
        uri.pathSegments[1].isNotEmpty) {
      _hasScanned = true;
      HapticFeedback.mediumImpact();
      _controller.stop();
      if (!mounted) return;
      Navigator.of(context).pop();
      showPairingApprovalSheet(context, pairingCode: uri.pathSegments[1]);
      return;
    }

    final intent = QrPaymentIntent.fromUri(uri);

    if (intent == null) {
      // Not a Zend! payment QR — show feedback once and resume scanning.
      // Set _hasScanned temporarily to suppress duplicate frames, then
      // clear it after a short delay so the user can try another code.
      _hasScanned = true;
      _showErrorSnackBar('This QR code is not a Zend! payment code');
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _hasScanned = false);
      });
      return;
    }

    // Valid intent — stop scanning and hand off to the payment sheet.
    _hasScanned = true;
    HapticFeedback.mediumImpact();
    _controller.stop();

    if (!mounted) return;
    Navigator.of(context).pop();

    showQrPaymentSheet(context, intent: intent);
  }

  // ── Torch toggle ─────────────────────────────────────────────────────────

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'DMSans', fontSize: 14),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera feed ──────────────────────────────────────────────────
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              // Handle permission denied and other camera errors.
              if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
                return _PermissionDeniedOverlay(
                  onOpenSettings: () async {
                    // Attempt to restart — on permanently denied the user
                    // must go to Settings manually.
                    try {
                      await _controller.start();
                    } catch (_) {}
                  },
                );
              }
              // Generic camera error.
              return _CameraErrorOverlay(error: error);
            },
          ),

          // ── Scanner framing overlay ──────────────────────────────────────
          CustomPaint(
            painter: _ScannerOverlay(),
            child: const SizedBox.expand(),
          ),

          // ── Top bar ──────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      // Back button
                      IconButton(
                        icon: const Icon(SolarIconsBold.altArrowLeft, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 4),
                      // Title
                      const Text(
                        'Scan QR code',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),

          // ── Bottom torch toggle ──────────────────────────────────────────
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: _TorchButton(
                torchOn: _torchOn,
                onTap: _toggleTorch,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scanner overlay painter ────────────────────────────────────────────────

/// Draws a semi-transparent dark scrim over the full canvas with a clear
/// centered square scan window, plus four corner brackets in [ZendColors.accent].
///
/// Uses [PathFillType.evenOdd] so the scan window "punches through" the scrim.
class _ScannerOverlay extends CustomPainter {
  static const double _maxWindowSize = 280.0;
  static const double _windowFraction = 0.8;
  static const double _bracketLength = 24.0;
  static const double _bracketThickness = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final windowSize = min(
      min(size.width, size.height) * _windowFraction,
      _maxWindowSize,
    );

    final left = (size.width - windowSize) / 2;
    final top = (size.height - windowSize) / 2;
    final right = left + windowSize;
    final bottom = top + windowSize;
    final windowRect = Rect.fromLTRB(left, top, right, bottom);

    // ── Scrim with hole ────────────────────────────────────────────────────
    final scrimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final scrimPath = Path()
      ..fillType = PathFillType.evenOdd
      // Outer rect covers the full canvas
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      // Inner rect is the scan window — evenOdd makes this a "hole"
      ..addRect(windowRect);

    canvas.drawPath(scrimPath, scrimPaint);

    // ── Corner brackets ────────────────────────────────────────────────────
    final bracketPaint = Paint()
      ..color = ZendColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = _bracketThickness
      ..strokeCap = StrokeCap.square;

    const bl = _bracketLength;

    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, top + bl)
        ..lineTo(left, top)
        ..lineTo(left + bl, top),
      bracketPaint,
    );

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(right - bl, top)
        ..lineTo(right, top)
        ..lineTo(right, top + bl),
      bracketPaint,
    );

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - bl)
        ..lineTo(left, bottom)
        ..lineTo(left + bl, bottom),
      bracketPaint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(right - bl, bottom)
        ..lineTo(right, bottom)
        ..lineTo(right, bottom - bl),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(_ScannerOverlay oldDelegate) => false;
}

// ── Permission denied overlay ──────────────────────────────────────────────

/// Shown when camera permission has been denied.
class _PermissionDeniedOverlay extends StatelessWidget {
  const _PermissionDeniedOverlay({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              SolarIconsBold.camera,
              color: Colors.white54,
              size: 64,
            ),
            const SizedBox(height: 20),
            const Text(
              'Camera access required',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'To scan QR codes, Zend! needs access to your camera. '
              'Please enable camera access in your device settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onOpenSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZendColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                  ),
                ),
                child: const Text(
                  'Enable Camera in Settings',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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

// ── Generic camera error overlay ───────────────────────────────────────────

/// Shown for non-permission camera errors (hardware unavailable, unsupported, etc.).
class _CameraErrorOverlay extends StatelessWidget {
  const _CameraErrorOverlay({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              SolarIconsBold.videocamera,
              color: Colors.white54,
              size: 64,
            ),
            const SizedBox(height: 20),
            const Text(
              'Camera unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error.errorCode.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Torch toggle button ────────────────────────────────────────────────────

class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.torchOn, required this.onTap});

  final bool torchOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: torchOn
              ? ZendColors.accent.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: torchOn
                ? ZendColors.accent
                : Colors.white.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Icon(
          torchOn ? SolarIconsBold.flashlightOn : SolarIconsBold.flashlight,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}
