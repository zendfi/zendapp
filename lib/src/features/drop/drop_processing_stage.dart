import 'package:flutter/material.dart';
import '../../design/zend_avatar.dart';
import '../../models/drop_models.dart';
import 'drop_fluid_particles.dart';

// The pure-black background used on both sender and receiver Drop screens.
const _kDropBackground = Color(0xFF080808);

/// Sender-side Drop processing screen shown while the transfer is confirmed.
///
/// The amount sits large in the background. A focused comet-trail particle
/// stream rises from the receiver's avatar (top) toward the top of the screen
/// — as if the money is streaming toward the recipient. Pure black background,
/// white/silver particles, matching the reference design.
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
  late final AnimationController _particleCtrl;
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    _fadeCtrl.dispose();
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
    return ColoredBox(
      color: _kDropBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          // Receiver avatar sits at ~18% from top — gives breathing room from top edge.
          const avatarFraction = 0.18;
          // Amount numeral centred at ~54% from top.
          const amountFraction = 0.54;

          return Stack(
            children: [
              // ── Amount — large, ghosted behind the particle stream ──
              Positioned(
                top: h * amountFraction - 56,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _fadeCtrl,
                  child: Text(
                    _amountStr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 80,
                      fontStyle: FontStyle.italic,
                      // Ghosted white — particles overlay it
                      color: Color(0x33FFFFFF),
                      height: 1.0,
                    ),
                  ),
                ),
              ),

              // ── Particle stream — flowing upward from receiver avatar ──
              Positioned.fill(
                child: CustomPaint(
                  painter: DropFluidParticlePainter(
                    animation: _particleCtrl,
                    direction: FluidParticleDirection.up,
                    focalXFraction: 0.5,
                    focalYFraction: avatarFraction + 0.03,
                    count: 300,
                    particleColor: Colors.white,
                    intensityMultiplier: 1.0,
                    beamHalfAngle: 0.30,
                  ),
                ),
              ),

              // ── Receiver avatar — the "source" focal point of the beam ──
              Positioned(
                top: h * avatarFraction - 26,
                left: w / 2 - 26,
                child: ZendAvatar(
                  radius: 26,
                  photoUrl: widget.receiver.preview?.avatarUrl,
                  initials: _receiverInitial,
                ),
              ),

              // ── Receiver tag ──
              Positioned(
                top: h * avatarFraction + 30,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _fadeCtrl,
                  child: Text(
                    '@$_receiverZendtag',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 13,
                      color: Color(0x66FFFFFF),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
