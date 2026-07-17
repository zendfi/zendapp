import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import 'drop_fluid_particles.dart';

/// Shows the receiver-side "catch" sheet when a Drop transfer is confirmed.
///
/// Mirrors the sender's dissolve animation in reverse: gold particles stream
/// downward from the sender's avatar (at the top) and coalesce into the
/// amount numeral as it fades in — like the money materialising from the air.
///
/// Paired with [DropProcessingStage] on the sender's device, both animations
/// feel choreographed: sender → particles rise and dissolve away; receiver →
/// particles descend and solidify into money.
///
/// Auto-dismisses after 5 seconds. Tapping anywhere closes early.
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
    useSafeArea: true,
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
  // Particle stream — loops while the sheet is visible.
  late final AnimationController _particleCtrl;
  // Coalesce — particles slow and amount fades in.
  late final AnimationController _coalesceCtrl;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _triggerHaptics();

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    // Amount fades in over 2.5s as particles "arrive".
    _coalesceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
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
    _coalesceCtrl.dispose();
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
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: ZendColors.bgDeep,
          borderRadius: BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            // Amount sits at ~60% from the top of the sheet.
            const amountFraction = 0.60;

            return Stack(
              children: [
                // ── Fluid particle stream — downward from sender avatar ──
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _coalesceCtrl,
                    builder: (context, child) {
                      // Particles fade out as amount coalesces (last 40%).
                      final t = CurvedAnimation(
                        parent: _coalesceCtrl,
                        curve: Curves.easeOut,
                      ).value;
                      final intensity = t < 0.6
                          ? 1.0
                          : 1.0 - ((t - 0.6) / 0.4) * 0.7; // fade to 30%
                      return CustomPaint(
                        painter: DropFluidParticlePainter(
                          animation: _particleCtrl,
                          direction: FluidParticleDirection.down,
                          // Particles stream from just below the sender avatar.
                          originFraction: 0.12,
                          count: 140,
                          intensityMultiplier: intensity.clamp(0.0, 1.0),
                        ),
                      );
                    },
                  ),
                ),

                // ── Sender avatar — glows at top ──
                Positioned(
                  top: h * 0.06,
                  left: w / 2 - 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Continuous soft glow ring
                      AnimatedBuilder(
                        animation: _particleCtrl,
                        builder: (context, child) {
                          // Pulsing glow tied to particle cycle
                          final pulse = 0.5 + 0.5 * sin(_particleCtrl.value * 2 * 3.14159);
                          return Container(
                            width: 60 + pulse * 16,
                            height: 60 + pulse * 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFD166)
                                  .withValues(alpha: 0.06 + pulse * 0.06),
                            ),
                          );
                        },
                      ),
                      ZendAvatar(
                        radius: 26,
                        photoUrl: widget.senderAvatarUrl,
                        initials: widget.senderZendtag.isNotEmpty
                            ? widget.senderZendtag[0].toUpperCase()
                            : '?',
                      ),
                    ],
                  ),
                ),

                // ── Drag handle ──
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                    ),
                  ),
                ),

                // ── Amount — materialises as particles coalesce ──
                Positioned(
                  top: h * amountFraction - 40,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: _coalesceCtrl,
                    builder: (context, child) {
                      // Amount fades in: 0→1 over first 70% of coalesce.
                      final t = CurvedAnimation(
                        parent: _coalesceCtrl,
                        curve: const Interval(0.1, 0.7, curve: Curves.easeOut),
                      ).value;
                      // Slight downward settle as it solidifies.
                      final dy = (1.0 - t) * -16.0;
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: Opacity(
                          opacity: t,
                          child: Text(
                            '+$_amountStr',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'InstrumentSerif',
                              fontSize: 56,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFFFFD166),
                              height: 1.0,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── From tag ──
                Positioned(
                  top: h * amountFraction + 28,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: _coalesceCtrl,
                    builder: (context, child) {
                      final opacity = CurvedAnimation(
                        parent: _coalesceCtrl,
                        curve: const Interval(0.35, 0.80, curve: Curves.easeOut),
                      ).value;
                      return Opacity(
                        opacity: opacity,
                        child: Text(
                          'from @${widget.senderZendtag}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 16,
                            color: Color(0xCCF0F0F0),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── Note ──
                if (widget.note != null && widget.note!.isNotEmpty)
                  Positioned(
                    top: h * amountFraction + 68,
                    left: 32,
                    right: 32,
                    child: AnimatedBuilder(
                      animation: _coalesceCtrl,
                      builder: (context, child) {
                        final opacity = CurvedAnimation(
                          parent: _coalesceCtrl,
                          curve: const Interval(0.50, 0.90, curve: Curves.easeOut),
                        ).value;
                        return Opacity(
                          opacity: opacity,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(ZendRadii.pill),
                            ),
                            child: Text(
                              '"${widget.note}"',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'DMMono',
                                fontSize: 13,
                                color: Color(0x99F0F0F0),
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // ── Tap hint ──
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Text(
                    'Tap to close',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.25),
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
