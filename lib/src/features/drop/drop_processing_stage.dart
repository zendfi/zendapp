import 'package:flutter/material.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/drop_models.dart';
import 'drop_fluid_particles.dart';

/// Sender-side Drop processing screen shown while the transfer is being
/// confirmed on-chain.
///
/// The amount numeral slowly dissolves into hundreds of upward-flowing gold
/// particles — fluid, continuous, physics-based. The receiver's avatar glows
/// faintly at the top of the screen where the particles are heading.
///
/// No spinner. No status text. The motion *is* the feedback.
class DropProcessingStage extends StatefulWidget {
  const DropProcessingStage({
    super.key,
    required this.amount,
    required this.receiver,
    required this.senderAvatarUrl,
    required this.senderInitial,
  });

  final double amount;
  final DiscoveredReceiver receiver;
  final String? senderAvatarUrl;
  final String senderInitial;

  @override
  State<DropProcessingStage> createState() => _DropProcessingStageState();
}

class _DropProcessingStageState extends State<DropProcessingStage>
    with TickerProviderStateMixin {
  // Particle stream — loops continuously while waiting for on-chain confirm.
  late final AnimationController _particleCtrl;
  // Amount dissolve — slowly fades the numeral as particles intensify.
  late final AnimationController _dissolveCtrl;

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    // Amount fades from 1.0 → 0.15 over 3 seconds then holds.
    _dissolveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..forward();
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    _dissolveCtrl.dispose();
    super.dispose();
  }

  String get _amountStr {
    if (widget.amount == widget.amount.roundToDouble()) {
      return '\$${widget.amount.toStringAsFixed(0)}';
    }
    return '\$${widget.amount.toStringAsFixed(2)}';
  }

  String get _receiverZendtag =>
      widget.receiver.gattPayload?.zendtag ??
      widget.receiver.preview?.zendtag ??
      '?';

  String get _receiverInitial =>
      _receiverZendtag.isNotEmpty ? _receiverZendtag[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // Amount sits at ~58% from the top of the available area.
        const amountFraction = 0.58;

        return Stack(
          children: [
            // ── Fluid particle stream — upward from amount position ──
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _dissolveCtrl,
                builder: (context, child) {
                  // Particles intensify as amount dissolves.
                  // Intensity: 0→1 over the first 2s, then holds at 1.
                  final intensity = CurvedAnimation(
                    parent: _dissolveCtrl,
                    curve: Curves.easeOut,
                  ).value;
                  return CustomPaint(
                    painter: DropFluidParticlePainter(
                      animation: _particleCtrl,
                      direction: FluidParticleDirection.up,
                      originFraction: amountFraction,
                      count: 160,
                      intensityMultiplier: intensity,
                    ),
                  );
                },
              ),
            ),

            // ── Receiver avatar — glows at top as particles arrive ──
            Positioned(
              top: h * 0.06,
              left: w / 2 - 28,
              child: AnimatedBuilder(
                animation: _dissolveCtrl,
                builder: (context, child) {
                  final glow = CurvedAnimation(
                    parent: _dissolveCtrl,
                    curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
                  ).value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Expanding glow ring
                      if (glow > 0)
                        Container(
                          width: 56 + glow * 32,
                          height: 56 + glow * 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFFD166)
                                .withValues(alpha: glow * 0.08),
                          ),
                        ),
                      Opacity(
                        opacity: 0.35 + glow * 0.65,
                        child: ZendAvatar(
                          radius: 26,
                          photoUrl: widget.receiver.preview?.avatarUrl,
                          initials: _receiverInitial,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // ── Amount numeral — dissolves as particles take over ──
            Positioned(
              top: h * amountFraction - 36,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _dissolveCtrl,
                builder: (context, child) {
                  // Fade from 1.0 → 0.12 as particles intensify.
                  final t = CurvedAnimation(
                    parent: _dissolveCtrl,
                    curve: Curves.easeIn,
                  ).value;
                  final opacity = (1.0 - t * 0.88).clamp(0.12, 1.0);
                  // Slight upward drift as it dissolves.
                  final dy = t * -12.0;
                  return Transform.translate(
                    offset: Offset(0, dy),
                    child: Opacity(
                      opacity: opacity,
                      child: Text(
                        _amountStr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'InstrumentSerif',
                          fontSize: 52,
                          fontStyle: FontStyle.italic,
                          color: zt.textPrimary,
                          height: 1.0,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Receiver tag — fades in below the amount ──
            Positioned(
              top: h * amountFraction + 28,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _dissolveCtrl,
                builder: (context, child) {
                  final opacity = CurvedAnimation(
                    parent: _dissolveCtrl,
                    curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
                  ).value;
                  return Opacity(
                    opacity: opacity,
                    child: Text(
                      '→ @$_receiverZendtag',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 14,
                        color: zt.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
