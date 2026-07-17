import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/zend_avatar.dart';
import 'drop_fluid_particles.dart';

const _kDropBackground = Color(0xFF080808);

/// Shows the receiver-side drop confirmation as a full-screen sheet.
///
/// Particles stream downward from the sender's avatar at the top.
/// The amount numeral glows as it materialises — a single crisp text with
/// a luminous bloom behind it, growing as the particles "arrive".
///
/// Both sender and receiver screens are pure black with white particles —
/// two halves of the same choreography.
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
    useSafeArea: false,
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
  // Glow pulse — slowly breathing after full reveal.
  late final AnimationController _glowPulseCtrl;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _triggerHaptics();

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();

    // After reveal completes, amount glow breathes.
    _glowPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _autoDismiss = Timer(const Duration(seconds: 7), () {
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
    _glowPulseCtrl.dispose();
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
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: ColoredBox(
        color: _kDropBackground,
        child: SizedBox(
          height: screenH,
          width: screenW,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              // Avatar (beam source) at 14% — leaves breathing room from top.
              const avatarFraction = 0.14;
              // Amount centred at 54%.
              const amountFraction = 0.54;

              const amountStyle = TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 88,
                fontStyle: FontStyle.italic,
                color: Colors.white,
                height: 1.0,
              );

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── Particle beam — downward from sender avatar ──
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _revealCtrl,
                      builder: (context, child) {
                        final intensity = CurvedAnimation(
                          parent: _revealCtrl,
                          curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
                        ).value;
                        return CustomPaint(
                          painter: DropFluidParticlePainter(
                            animation: _particleCtrl,
                            direction: FluidParticleDirection.down,
                            focalXFraction: 0.5,
                            focalYFraction: avatarFraction + 0.03,
                            count: 300,
                            particleColor: Colors.white,
                            intensityMultiplier: intensity,
                            beamHalfAngle: 0.30,
                          ),
                        );
                      },
                    ),
                  ),

                  // ── Amount glow bloom — blurred version behind crisp text ──
                  Positioned(
                    top: h * amountFraction - 64,
                    left: 0,
                    right: 0,
                    height: 128,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_revealCtrl, _glowPulseCtrl]),
                      builder: (context, child) {
                        // Glow ramps in from 40–100% of reveal, then pulses.
                        final revealT = CurvedAnimation(
                          parent: _revealCtrl,
                          curve: const Interval(0.40, 1.0, curve: Curves.easeOut),
                        ).value;
                        // Pulse: 0.6→1.0 brightness once revealed.
                        final pulse = revealT < 1.0
                            ? 0.0
                            : (0.6 + _glowPulseCtrl.value * 0.4);
                        final glowOpacity = (revealT * 0.55 + pulse * 0.2).clamp(0.0, 0.75);

                        return CustomPaint(
                          painter: DropGlowTextPainter(
                            text: _amountStr,
                            style: amountStyle,
                            glowOpacity: glowOpacity,
                            glowRadius: 28.0 + _glowPulseCtrl.value * 12.0,
                          ),
                        );
                      },
                    ),
                  ),

                  // ── Amount text — crisp, fades in ──
                  Positioned(
                    top: h * amountFraction - 56,
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                      animation: _revealCtrl,
                      builder: (context, child) {
                        final t = CurvedAnimation(
                          parent: _revealCtrl,
                          curve: const Interval(0.35, 0.85, curve: Curves.easeOut),
                        ).value;
                        final dy = (1 - t) * 18.0;
                        return Transform.translate(
                          offset: Offset(0, dy),
                          child: Opacity(
                            opacity: t,
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        _amountStr,
                        textAlign: TextAlign.center,
                        style: amountStyle,
                      ),
                    ),
                  ),

                  // ── Sender avatar — focal point ──
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

                  // ── From tag ──
                  Positioned(
                    top: h * avatarFraction + 30,
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                      animation: _revealCtrl,
                      builder: (context, child) {
                        final t = CurvedAnimation(
                          parent: _revealCtrl,
                          curve: const Interval(0.20, 0.65, curve: Curves.easeOut),
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

                  // ── Note ──
                  if (widget.note != null && widget.note!.isNotEmpty)
                    Positioned(
                      top: h * amountFraction + 50,
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
      ),
    );
  }
}
