import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/zend_tokens.dart';

/// A Vibe message bubble: just the sticker emoji until tapped.
///
/// On first tap, a burst + glow animation plays and the amount is revealed.
/// The amount stays visible after reveal — the "magic" only plays once.
///
/// Alignment:
///   isMine: right side (sender)
///   !isMine: left side (recipient)
class VibeMessageBubble extends StatefulWidget {
  const VibeMessageBubble({
    super.key,
    required this.emoji,
    required this.amountUsdc,
    required this.isMine,
    this.createdAt,
    this.isDelivering = false,
  });

  final String emoji;
  final double amountUsdc;
  final bool isMine;
  final DateTime? createdAt;

  /// True while the transfer is still in-flight (optimistic state).
  /// The sticker renders at reduced opacity to signal sending.
  final bool isDelivering;

  @override
  State<VibeMessageBubble> createState() => _VibeMessageBubbleState();
}

class _VibeMessageBubbleState extends State<VibeMessageBubble>
    with TickerProviderStateMixin {
  bool _revealed = false;

  // Burst animation controllers
  late final AnimationController _burstCtrl;
  late final AnimationController _scaleCtrl;
  late final AnimationController _amountFadeCtrl;

  late final Animation<double> _burstAnim;   // drives particle spread
  late final Animation<double> _scaleAnim;   // emoji pop
  late final Animation<double> _amountFade;  // amount fade-in

  @override
  void initState() {
    super.initState();

    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _amountFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _burstAnim = CurvedAnimation(parent: _burstCtrl, curve: Curves.easeOut);
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 1.35, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 60),
    ]).animate(_scaleCtrl);
    _amountFade = CurvedAnimation(
        parent: _amountFadeCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _burstCtrl.dispose();
    _scaleCtrl.dispose();
    _amountFadeCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    if (_revealed) return;
    HapticFeedback.mediumImpact();
    setState(() => _revealed = true);
    _burstCtrl.forward();
    _scaleCtrl.forward();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _amountFadeCtrl.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Align(
      alignment:
          widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: widget.isMine ? 60 : 12,
          right: widget.isMine ? 12 : 60,
          top: 4,
          bottom: 4,
        ),
        child: GestureDetector(
          onTap: _onTap,
          child: Column(
            crossAxisAlignment: widget.isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sticker + burst overlay
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Burst particles — only visible after tap
                    if (_revealed)
                      AnimatedBuilder(
                        animation: _burstAnim,
                        builder: (ctx, _) => CustomPaint(
                          size: const Size(80, 80),
                          painter: _BurstPainter(
                            progress: _burstAnim.value,
                            color: zt.accent,
                          ),
                        ),
                      ),

                    // Glow ring — expands outward on reveal
                    if (_revealed)
                      AnimatedBuilder(
                        animation: _burstAnim,
                        builder: (ctx, _) {
                          final opacity =
                              (1.0 - _burstAnim.value).clamp(0.0, 1.0);
                          final radius =
                              20.0 + _burstAnim.value * 30.0;
                          return Opacity(
                            opacity: opacity * 0.5,
                            child: Container(
                              width: radius * 2,
                              height: radius * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: zt.accent.withValues(alpha: 0.25),
                              ),
                            ),
                          );
                        },
                      ),

                    // The emoji itself — scales on tap
                    AnimatedBuilder(
                      animation: _scaleCtrl,
                      builder: (ctx, child) => Transform.scale(
                        scale: _revealed ? _scaleAnim.value : 1.0,
                        child: child,
                      ),
                      child: Opacity(
                        opacity: widget.isDelivering ? 0.55 : 1.0,
                        child: Text(
                          widget.emoji,
                          style: const TextStyle(fontSize: 52),
                        ),
                      ),
                    ),

                    // Tap hint — small "?" badge when not yet revealed
                    if (!_revealed && !widget.isMine)
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: zt.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              '?',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Amount — revealed after tap, fades in
              if (_revealed)
                FadeTransition(
                  opacity: _amountFade,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.isMine
                            ? zt.accent.withValues(alpha: 0.15)
                            : zt.bgSecondary,
                        borderRadius:
                            BorderRadius.circular(ZendRadii.pill),
                        border: Border.all(
                          color: widget.isMine
                              ? zt.accent.withValues(alpha: 0.4)
                              : zt.border,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '\$${widget.amountUsdc.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: widget.isMine
                              ? zt.accent
                              : zt.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),

              // Timestamp
              if (widget.createdAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _timeLabel(widget.createdAt!),
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 10,
                      color: zt.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeLabel(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Burst particle painter ─────────────────────────────────────────────────────

class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.55;
    const particleCount = 10;

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < particleCount; i++) {
      final angle = (i / particleCount) * 2 * pi;
      final dist = maxRadius * progress;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final radius = 3.5 * (1.0 - progress * 0.6);

      final x = center.dx + cos(angle) * dist;
      final y = center.dy + sin(angle) * dist;

      paint.color = color.withValues(alpha: opacity * 0.85);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    // Small secondary ring of sparkles at half-count, offset angle
    for (var i = 0; i < particleCount ~/ 2; i++) {
      final angle = ((i / (particleCount / 2)) * 2 * pi) + (pi / particleCount);
      final dist = maxRadius * progress * 0.65;
      final opacity = (1.0 - progress * 1.2).clamp(0.0, 1.0);
      final radius = 2.5 * (1.0 - progress * 0.7);

      final x = center.dx + cos(angle) * dist;
      final y = center.dy + sin(angle) * dist;

      paint.color = Colors.white.withValues(alpha: opacity * 0.6);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.color != color;
}
