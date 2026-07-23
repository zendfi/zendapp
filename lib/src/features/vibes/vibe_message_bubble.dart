import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/zend_tokens.dart';

// ── Vibe message bubble ───────────────────────────────────────────────────────
//
// Two states:
//   Hidden  — glassmorphic frosted pill with shimmer + "?" badge
//   Revealed — full-screen particle explosion then settle to emoji + amount
//
// The reveal is a deliberate "micro-moment": the screen dims, particles
// explode from center, the sticker grows, the amount fades in.

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
  final bool isDelivering;

  @override
  State<VibeMessageBubble> createState() => _VibeMessageBubbleState();
}

class _VibeMessageBubbleState extends State<VibeMessageBubble>
    with TickerProviderStateMixin {
  bool _revealed = false;
  bool _exploding = false;

  // Shimmer on the hidden pill
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;

  // Explosion phase
  late final AnimationController _explodeCtrl;
  late final Animation<double> _explode;   // 0→1, drives everything
  late final Animation<double> _bgFade;    // screen dim
  late final Animation<double> _emojiScale;
  late final Animation<double> _amountFade;

  // Progressive haptic timer
  Timer? _hapticTimer;

  @override
  void initState() {
    super.initState();

    _shimmerCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _shimmer = CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut);

    _explodeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600),
    );

    _explode = CurvedAnimation(parent: _explodeCtrl, curve: Curves.easeOut);

    _bgFade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.72), weight: 15),
      TweenSequenceItem(tween: ConstantTween(0.72), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.72, end: 0.0), weight: 45),
    ]).animate(CurvedAnimation(parent: _explodeCtrl, curve: Curves.easeInOut));

    _emojiScale = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 20),
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.4)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 45),
      TweenSequenceItem(
          tween: Tween(begin: 1.4, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 35),
    ]).animate(_explodeCtrl);

    _amountFade = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 65),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 35),
    ]).animate(_explodeCtrl);
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _explodeCtrl.dispose();
    _hapticTimer?.cancel();
    super.dispose();
  }

  void _onTap() {
    if (_revealed || widget.isMine) return;
    setState(() { _exploding = true; _revealed = true; });
    _shimmerCtrl.stop();

    // Progressive haptic crescendo
    _fireProgressiveHaptics();

    _explodeCtrl.forward().then((_) {
      if (mounted) setState(() => _exploding = false);
    });
  }

  void _fireProgressiveHaptics() {
    // Rapid light clicks building up, then heavy thud at the peak
    const pattern = [
      (delay: 0,   style: HapticFeedback.lightImpact),
      (delay: 80,  style: HapticFeedback.lightImpact),
      (delay: 150, style: HapticFeedback.lightImpact),
      (delay: 210, style: HapticFeedback.mediumImpact),
      (delay: 260, style: HapticFeedback.mediumImpact),
      (delay: 300, style: HapticFeedback.heavyImpact),  // the thud
      (delay: 900, style: HapticFeedback.lightImpact),  // settle
    ];
    for (final p in pattern) {
      Future.delayed(Duration(milliseconds: p.delay), p.style);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final screenSize = MediaQuery.of(context).size;

    Widget body;
    if (!_revealed && !_exploding) {
      body = _HiddenVibe(
        emoji: widget.emoji,
        isMine: widget.isMine,
        isDelivering: widget.isDelivering,
        shimmer: _shimmer,
        createdAt: widget.createdAt,
        onTap: _onTap,
        zt: zt,
      );
    } else if (_exploding) {
      body = _ExplodingVibe(
        emoji: widget.emoji,
        amountUsdc: widget.amountUsdc,
        isMine: widget.isMine,
        explode: _explode,
        bgFade: _bgFade,
        emojiScale: _emojiScale,
        amountFade: _amountFade,
        screenSize: screenSize,
        zt: zt,
        createdAt: widget.createdAt,
      );
    } else {
      body = _RevealedVibe(
        emoji: widget.emoji,
        amountUsdc: widget.amountUsdc,
        isMine: widget.isMine,
        zt: zt,
        createdAt: widget.createdAt,
      );
    }

    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: widget.isMine ? 60 : 8,
          right: widget.isMine ? 8 : 60,
          top: 4,
          bottom: 4,
        ),
        child: body,
      ),
    );
  }
}

// ── Hidden state: glassmorphic frosted pill ───────────────────────────────────

class _HiddenVibe extends StatelessWidget {
  const _HiddenVibe({
    required this.emoji,
    required this.isMine,
    required this.isDelivering,
    required this.shimmer,
    required this.zt,
    required this.onTap,
    this.createdAt,
  });

  final String emoji;
  final bool isMine;
  final bool isDelivering;
  final Animation<double> shimmer;
  final ZendTheme zt;
  final VoidCallback onTap;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    // The pill is dark and frosted to signal "there's something hidden inside"
    const pillBg = Color(0xFF1C1C1E);
    const pillBorder = Color(0xFF3A3A3C);

    return GestureDetector(
      onTap: isMine ? null : onTap,
      child: Opacity(
        opacity: isDelivering ? 0.55 : 1.0,
        child: Container(
          constraints: const BoxConstraints(minWidth: 90, maxWidth: 160),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: pillBorder, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                // Top edge highlight (studio reflection)
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(alpha: 0.18),
                        Colors.white.withValues(alpha: 0.0),
                      ]),
                    ),
                  ),
                ),
                // Shimmer sweep
                AnimatedBuilder(
                  animation: shimmer,
                  // ignore: avoid_annotating_with_dynamic
                  builder: (context, child) => Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1.0 + shimmer.value * 2, 0),
                          end: Alignment(shimmer.value * 2, 0),
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.05),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 36)),
                      const SizedBox(height: 6),
                      if (!isMine) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                          ),
                          child: const Text(
                            'Tap to reveal ✨',
                            style: TextStyle(
                              fontFamily: 'DMMono',
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else ...[
                        Text(
                          'sent a Vibe',
                          style: TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                      if (createdAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _timeLabel(createdAt!),
                          style: TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 9,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Exploding state: full-screen takeover ────────────────────────────────────

class _ExplodingVibe extends StatelessWidget {
  const _ExplodingVibe({
    required this.emoji,
    required this.amountUsdc,
    required this.isMine,
    required this.explode,
    required this.bgFade,
    required this.emojiScale,
    required this.amountFade,
    required this.screenSize,
    required this.zt,
    this.createdAt,
  });

  final String emoji;
  final double amountUsdc;
  final bool isMine;
  final Animation<double> explode;
  final Animation<double> bgFade;
  final Animation<double> emojiScale;
  final Animation<double> amountFade;
  final Size screenSize;
  final ZendTheme zt;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      child: AnimatedBuilder(
        animation: explode,
        builder: (ctx, _) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Full-screen overlay — positioned relative to screen
              Positioned(
                left: isMine ? -(screenSize.width - 98) : -8,
                right: isMine ? -8 : -(screenSize.width - 98),
                top: -(screenSize.height * 0.4),
                bottom: -(screenSize.height * 0.4),
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      // Screen dim
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: bgFade.value),
                        ),
                      ),
                      // Particle explosion
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ExplosionPainter(
                            progress: explode.value,
                            emoji: emoji,
                            accentColor: zt.accent,
                          ),
                        ),
                      ),
                      // Central emoji burst
                      Center(
                        child: Transform.scale(
                          scale: emojiScale.value,
                          child: Text(emoji, style: const TextStyle(fontSize: 80, decoration: TextDecoration.none)),
                        ),
                      ),
                      // Amount reveal
                      Center(
                        child: Transform.translate(
                          offset: const Offset(0, 70),
                          child: Opacity(
                            opacity: amountFade.value.clamp(0.0, 1.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: zt.accent.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Text(
                                '\$${amountUsdc.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontFamily: 'InstrumentSerif',
                                  fontSize: 32,
                                  fontStyle: FontStyle.italic,
                                  color: zt.bgPrimary,
                                  height: 1.0,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // The bubble itself (stays in place during explosion)
              Container(
                width: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 36, decoration: TextDecoration.none)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Revealed state: clean settled view ───────────────────────────────────────

class _RevealedVibe extends StatelessWidget {
  const _RevealedVibe({
    required this.emoji,
    required this.amountUsdc,
    required this.isMine,
    required this.zt,
    this.createdAt,
  });

  final String emoji;
  final double amountUsdc;
  final bool isMine;
  final ZendTheme zt;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 90, maxWidth: 160),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF3A3A3C), width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 6),
          Text(
            '\$${amountUsdc.toStringAsFixed(2)}',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontStyle: FontStyle.italic,
              color: zt.accent,
              height: 1.0,
            ),
          ),
          if (createdAt != null) ...[
            const SizedBox(height: 3),
            Text(
              _timeLabel(createdAt!),
              style: TextStyle(fontFamily: 'DMMono', fontSize: 9, color: Colors.white.withValues(alpha: 0.3)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Explosion particle painter ────────────────────────────────────────────────

class _ExplosionPainter extends CustomPainter {
  _ExplosionPainter({
    required this.progress,
    required this.emoji,
    required this.accentColor,
  });

  final double progress;
  final String emoji;
  final Color accentColor;

  static final _rng = Random(42); // deterministic seed for consistent layout

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.02 || progress >= 0.98) return;
    final center = Offset(size.width / 2, size.height / 2);

    // Phase: 0-0.5 = explosion out, 0.5-1.0 = fade out
    final easeProgress = progress < 0.5 ? progress * 2 : 1.0;
    final fadeOpacity = progress < 0.5 ? 1.0 : 1.0 - ((progress - 0.5) * 2);

    // Particles: stars, circles, lines
    final particlePaint = Paint()..style = PaintingStyle.fill;
    const particleCount = 28;
    const maxRadius = 180.0;

    for (var i = 0; i < particleCount; i++) {
      final angle = (i / particleCount) * 2 * pi + _rng.nextDouble() * 0.3;
      final speed = 0.5 + _rng.nextDouble() * 0.5;
      final dist = maxRadius * easeProgress * speed;
      final x = center.dx + cos(angle) * dist;
      // Gravity effect — particles arc downward
      final gravity = easeProgress * easeProgress * 60.0 * _rng.nextDouble();
      final y = center.dy + sin(angle) * dist + gravity;

      final opacity = (1.0 - easeProgress * 0.3) * fadeOpacity;
      final size_ = (3.0 + _rng.nextDouble() * 5.0) * (1.0 - easeProgress * 0.5);

      // Alternate between accent color and gold/white sparks
      final color = i % 3 == 0
          ? accentColor.withValues(alpha: opacity * 0.9)
          : i % 3 == 1
              ? const Color(0xFFFFD700).withValues(alpha: opacity * 0.85)
              : Colors.white.withValues(alpha: opacity * 0.7);

      particlePaint.color = color;

      // Star shape for variety
      if (i % 4 == 0) {
        _drawStar(canvas, Offset(x, y), size_ * 1.2, particlePaint);
      } else {
        canvas.drawCircle(Offset(x, y), size_, particlePaint);
      }
    }

    // Trailing lines radiating outward
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const lineCount = 12;
    for (var i = 0; i < lineCount; i++) {
      final angle = (i / lineCount) * 2 * pi;
      final near = maxRadius * 0.15 * easeProgress;
      final far = maxRadius * 0.65 * easeProgress;
      linePaint.color = accentColor.withValues(alpha: fadeOpacity * 0.4 * (1.0 - easeProgress));
      canvas.drawLine(
        Offset(center.dx + cos(angle) * near, center.dy + sin(angle) * near),
        Offset(center.dx + cos(angle) * far, center.dy + sin(angle) * far),
        linePaint,
      );
    }

    // Glow ring
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = accentColor.withValues(alpha: fadeOpacity * (1.0 - easeProgress) * 0.6);
    canvas.drawCircle(center, maxRadius * 0.4 * easeProgress, glowPaint);
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    const points = 4;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final angle = (i * pi / points) - pi / 2;
      final r = i.isEven ? radius : radius * 0.45;
      final pt = Offset(center.dx + cos(angle) * r, center.dy + sin(angle) * r);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ExplosionPainter old) => old.progress != progress;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _timeLabel(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
