import 'package:flutter/material.dart';
import '../../design/zend_avatar.dart';
import '../../models/drop_models.dart';
import 'drop_text_dissolve.dart';

const _kDropBackground = Color(0xFF080808);

const _kAmountStyle = TextStyle(
  fontFamily: 'InstrumentSerif',
  fontSize: 88,
  fontStyle: FontStyle.italic,
  color: Colors.white,
  height: 1.0,
);

/// Sender-side Drop processing screen.
///
/// The amount text dissolves into thousands of particles that stream upward
/// toward the receiver's avatar — each particle emerges from the actual glyph
/// letterforms and follows a depth-bucketed, physically-timed trajectory.
///
/// Text-to-particle sampling is async (one-time at mount, ~30ms).
/// Until it completes the text renders crisp and static, then seamlessly
/// transitions into the dissolve.
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
    with SingleTickerProviderStateMixin {
  // Particle animation loops while we wait for on-chain confirmation.
  late final AnimationController _dissolveCtrl;

  @override
  void initState() {
    super.initState();
    _dissolveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
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
    return ColoredBox(
      color: _kDropBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          // Avatar sits at avatarFraction of the screen height.
          const avatarFraction = 0.16;
          // Amount text centred at amountFraction of the screen height.
          const amountFraction = 0.52;

          // The DropTextDissolve widget is positioned so it covers the amount
          // text area. The focal point (avatar) is ABOVE the widget — that's
          // fine: the painter allows particles to travel off the top edge with
          // a generous clip guard (py < -canvasHeight * 3).
          const widgetHeight = 160.0;
          final widgetTop = h * amountFraction - 80.0;

          // focalYFraction: avatar Y in canvas-relative coordinates.
          // Can be negative — the painter handles it.
          final avatarScreenY = h * avatarFraction;
          final focalYFraction = (avatarScreenY - widgetTop) / widgetHeight;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Particle canvas ────────────────────────────────────────────
              Positioned(
                top: widgetTop,
                left: 0,
                right: 0,
                height: widgetHeight,
                child: DropTextDissolve(
                  text: _amountStr,
                  style: _kAmountStyle,
                  direction: DissolveDirection.dissolve,
                  controller: _dissolveCtrl,
                  focalXFraction: 0.5,
                  focalYFraction: focalYFraction,
                  // textYFraction: text is centred in the widget (0.5)
                  height: widgetHeight,
                  samplingDensity: 0.28,
                  maxParticles: 2000,
                ),
              ),

              // ── Receiver avatar ────────────────────────────────────────────
              Positioned(
                top: h * avatarFraction - 28,
                left: w / 2 - 28,
                child: ZendAvatar(
                  radius: 28,
                  photoUrl: widget.receiver.preview?.avatarUrl,
                  initials: _receiverInitial,
                ),
              ),

              // ── Receiver tag ───────────────────────────────────────────────
              Positioned(
                top: h * avatarFraction + 34,
                left: 0,
                right: 0,
                child: Text(
                  '@$_receiverZendtag',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 13,
                    color: Color(0x55FFFFFF),
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
