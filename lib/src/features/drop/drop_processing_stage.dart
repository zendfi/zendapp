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

          // Receiver avatar fraction — beam target at top.
          const avatarFraction = 0.16;
          // Text dissolve zone centred at ~52%.
          const amountFraction = 0.52;

          // The particle widget spans from just above the avatar down through
          // the amount text — so the focal point is within its canvas.
          // widgetTop = avatar top edge with a little headroom
          final widgetTop = h * avatarFraction - 44.0;
          // widgetBottom = bottom of the amount text area
          final widgetBottom = h * amountFraction + 80.0;
          final widgetHeight = widgetBottom - widgetTop;

          // Avatar Y within the widget canvas (normalised 0→1)
          final avatarCanvasY = (h * avatarFraction - widgetTop) / widgetHeight;
          // Amount text centre Y within the widget canvas (normalised 0→1)
          // The painter places text at size.height * textYFraction of its own canvas.
          final textCanvasY = (h * amountFraction - widgetTop) / widgetHeight;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Particle canvas covering avatar → amount zone ──────────────
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
                  focalYFraction: avatarCanvasY,
                  textYFraction: textCanvasY,
                  height: widgetHeight,
                  samplingDensity: 0.28,
                  maxParticles: 2000,
                ),
              ),

              // ── Receiver avatar — focal point particles stream toward ──────
              Positioned(
                top: h * avatarFraction - 28,
                left: w / 2 - 28,
                child: ZendAvatar(
                  radius: 28,
                  photoUrl: widget.receiver.preview?.avatarUrl,
                  initials: _receiverInitial,
                ),
              ),

              // ── Receiver tag ──────────────────────────────────────────────
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
