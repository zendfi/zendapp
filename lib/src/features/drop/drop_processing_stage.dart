import 'package:flutter/material.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/drop_models.dart';

/// A physics-animated "money in flight" processing stage — shown while the
/// Drop transfer is being confirmed on-chain. No spinner, no status text —
/// just a particle of money arcing from the sender's avatar to the receiver's,
/// repeating until the transfer either succeeds or fails.
///
/// The animation intentionally communicates that something real is happening
/// between two specific people on two specific devices, without the clinical
/// "Sending $X to @Y…" text of a generic spinner.
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
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
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

  String get _receiverInitial => _receiverZendtag.isNotEmpty
      ? _receiverZendtag[0].toUpperCase()
      : '?';

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),

        // ── Two avatars with the arc between them ──
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            // Sender on left, receiver on right — horizontal distance between centres
            const avatarRadius = 36.0;
            const horizontalPad = 48.0;
            final senderCx = horizontalPad + avatarRadius;
            final receiverCx = w - horizontalPad - avatarRadius;
            const avatarCy = 40.0; // centre Y within the SizedBox

            return SizedBox(
              height: 120,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── Sender avatar (left) ──
                  Positioned(
                    left: senderCx - avatarRadius,
                    top: 0,
                    child: ZendAvatar(
                      radius: avatarRadius,
                      photoUrl: widget.senderAvatarUrl,
                      initials: widget.senderInitial,
                    ),
                  ),
                  // ── Receiver avatar (right) ──
                  Positioned(
                    left: receiverCx - avatarRadius,
                    top: 0,
                    child: ZendAvatar(
                      radius: avatarRadius,
                      photoUrl: widget.receiver.preview?.avatarUrl,
                      initials: _receiverInitial,
                    ),
                  ),
                  // ── Animated arc particle ──
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      // Ease-in-out along the arc: slow at launch, fast at peak, slow at landing
                      final t = CurvedAnimation(
                        parent: _ctrl,
                        curve: Curves.easeInOut,
                      ).value;

                      // Parabolic arc: lerp X linearly, Y follows a parabola
                      // peaking above the avatars (negative Y = up)
                      final x = senderCx + (receiverCx - senderCx) * t;
                      const peakLift = 60.0; // pixels above avatar centres
                      final y = avatarCy - 4 * peakLift * t * (1 - t);

                      // Particle fades in/out at the endpoints so it feels
                      // like it emerges from and lands into the avatar.
                      final opacity = (t < 0.12)
                          ? t / 0.12
                          : (t > 0.88)
                              ? (1.0 - t) / 0.12
                              : 1.0;

                      return Positioned(
                        left: x - 13,
                        top: y - 13,
                        child: Opacity(
                          opacity: opacity.clamp(0.0, 1.0),
                          child: Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: zt.accent.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '💸',
                              style: const TextStyle(
                                fontSize: 14,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 28),

        // ── Amount ──
        Text(
          _amountStr,
          style: TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 40,
            fontStyle: FontStyle.italic,
            color: zt.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '@$_receiverZendtag',
          style: TextStyle(
            fontFamily: 'DMMono',
            fontSize: 14,
            color: zt.textSecondary,
          ),
        ),

        const Spacer(flex: 3),
      ],
    );
  }
}
