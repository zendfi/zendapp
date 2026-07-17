import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/zend_avatar.dart';
import 'drop_fluid_particles.dart';

const _kDropBackground = Color(0xFF080808);

/// Shows the receiver-side drop confirmation as a full-screen sheet.
///
/// Mirrors the sender's screen in reverse: particles stream downward from the
/// top (where the sender "is"), the amount fades in as they arrive.
///
/// Both screens are black, white particles, same comet-trail physics — they
/// feel like two halves of the same animation even on different devices.
Future<void> showDropReceiverSheet({
  required BuildContext context,
  required double amount,
  required String senderZendtag,
  required String? senderAvatarUrl,
  String? note,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: false, // we want full screen including status bar area
    backgroundColor: Colors.transparent,
    isDismissible: true,
    builder: (_) => _DropReceiverSheet(
      amount: amount,
      senderZendtag: senderZendtag,
      senderAvatarUrl: senderAvatarUrl,
      note: note,
    ),
  );
}

class _DropReceiverSheet extends StatefulWidget {
  const _DropReceiverSheet({
    required this.amount,
    required this.senderZendtag,
    required this.senderAvatarUrl,
    this.note,
  });

  final double amount;
  final String senderZendtag;
  final String? senderAvatarUrl;
  final String? note;

  @override
  State<_DropReceiverSheet> createState() => _DropReceiverSheetState();
}

class _DropReceiverSheetState extends State<_DropReceiverSheet>
    with TickerProviderStateMixin {
  late final AnimationController _particleCtrl;
  late final AnimationController _revealCtrl;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _triggerHaptics();

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // Amount and labels fade in over 1.8s.
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();

    _autoDismiss = Timer(const Duration(seconds: 6), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _triggerHaptics() async {
    for (int i = 0; i < 3; i++) {
      await Future.delayed(Duration(milliseconds: i * 100));
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _particleCtrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  String get _amountStr {
    if (widget.amount == widget.amount.roundToDouble()) {
      return '\$${widget.amount.toStringAsFixed(0)}';
    }
    return '\$${widget.amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        // Full-screen — matches sender's sheet height.
        height: screenHeight,
        width: screenWidth,
        color: _kDropBackground,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;

            // Sender avatar at ~12% from top — beam focal point.
            const avatarFraction = 0.12;
            // Amount centred at ~52%.
            const amountFraction = 0.52;

            return Stack(
              children: [
                // ── Amount — ghosted, fades in as particles "arrive" ──
                Positioned(
                  top: h * amountFraction - 56,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: _revealCtrl,
                    builder: (context, child) {
                      final t = CurvedAnimation(
                        parent: _revealCtrl,
                        curve: const Interval(0.1, 0.8, curve: Curves.easeOut),
                      ).value;
                      return Opacity(
                        opacity: (t * 0.25).clamp(0.0, 0.25), // ghosted like sender
                        child: child,
                      );
                    },
                    child: Text(
                      _amountStr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 80,
                        fontStyle: FontStyle.italic,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),

                // ── Particle stream — flowing downward from sender avatar ──
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _revealCtrl,
                    builder: (context, child) {
                      // Slight ramp-up in intensity at start.
                      final intensity = CurvedAnimation(
                        parent: _revealCtrl,
                        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
                      ).value;
                      return CustomPaint(
                        painter: DropFluidParticlePainter(
                          animation: _particleCtrl,
                          direction: FluidParticleDirection.down,
                          focalXFraction: 0.5,
                          focalYFraction: avatarFraction + 0.04,
                          count: 220,
                          particleColor: Colors.white,
                          intensityMultiplier: intensity,
                        ),
                      );
                    },
                  ),
                ),

                // ── Sender avatar — focal point of the beam ──
                Positioned(
                  top: h * avatarFraction - 26,
                  left: w / 2 - 26,
                  child: ZendAvatar(
                    radius: 26,
                    photoUrl: widget.senderAvatarUrl,
                    initials: widget.senderZendtag.isNotEmpty
                        ? widget.senderZendtag[0].toUpperCase()
                        : '?',
                  ),
                ),

                // ── Sender tag ──
                Positioned(
                  top: h * avatarFraction + 30,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: _revealCtrl,
                    builder: (context, child) {
                      final t = CurvedAnimation(
                        parent: _revealCtrl,
                        curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
                      ).value;
                      return Opacity(opacity: t, child: child);
                    },
                    child: Text(
                      'from @${widget.senderZendtag}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 13,
                        color: Color(0x66FFFFFF),
                      ),
                    ),
                  ),
                ),

                // ── Amount — full-brightness reveal after ghosted phase ──
                Positioned(
                  top: h * amountFraction - 56,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: _revealCtrl,
                    builder: (context, child) {
                      // Bright amount fades in from 50–100% of reveal.
                      final t = CurvedAnimation(
                        parent: _revealCtrl,
                        curve: const Interval(0.50, 1.0, curve: Curves.easeOut),
                      ).value;
                      // Slide up slightly as it appears.
                      final dy = (1 - t) * 20.0;
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: Opacity(
                          opacity: t,
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      '+$_amountStr',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 80,
                        fontStyle: FontStyle.italic,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),

                // ── Note ──
                if (widget.note != null && widget.note!.isNotEmpty)
                  Positioned(
                    top: h * amountFraction + 44,
                    left: 32,
                    right: 32,
                    child: AnimatedBuilder(
                      animation: _revealCtrl,
                      builder: (context, child) {
                        final t = CurvedAnimation(
                          parent: _revealCtrl,
                          curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
                        ).value;
                        return Opacity(opacity: t, child: child);
                      },
                      child: Text(
                        '"${widget.note}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 14,
                          color: Color(0x80FFFFFF),
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // ── Tap hint ──
                Positioned(
                  bottom: 48,
                  left: 0,
                  right: 0,
                  child: Text(
                    'Tap to close',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
