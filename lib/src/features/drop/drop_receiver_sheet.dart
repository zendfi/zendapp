import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/zend_avatar.dart';
import 'drop_text_dissolve.dart';

const _kDropBackground = Color(0xFF080808);

const _kAmountStyle = TextStyle(
  fontFamily: 'InstrumentSerif',
  fontSize: 88,
  fontStyle: FontStyle.italic,
  color: Colors.white,
  height: 1.0,
);

/// Shows the receiver-side Drop confirmation as a full-screen modal.
///
/// Particles descend from the sender's avatar, converge into the amount
/// letterforms (reform direction — mirror image of the sender's dissolve),
/// then the text locks solid while the glow breathes.
///
/// Both screens share the same [DropTextDissolve] widget — the direction
/// parameter reverses the physics automatically. No separately authored
/// receive animation.
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
  /// Reform animation — runs from 0→1 once: particles converge into text.
  late final AnimationController _reformCtrl;
  /// Glow pulse — breathes after reform completes.
  late final AnimationController _glowCtrl;
  /// Label fade — "from @sender" and note slide in.
  late final AnimationController _labelCtrl;

  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _triggerHaptics();

    // Reform runs over 3s — long enough to feel satisfying.
    _reformCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _labelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Start glow breathing after reform settles (~2.2s).
    _reformCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _glowCtrl.repeat(reverse: true);
      }
    });

    // Labels fade in halfway through the reform.
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _labelCtrl.forward();
    });

    _autoDismiss = Timer(const Duration(seconds: 8), () {
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
    _reformCtrl.dispose();
    _glowCtrl.dispose();
    _labelCtrl.dispose();
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

              const avatarFraction = 0.13;
              const amountFraction = 0.51;

              // Widget covers the amount text area. Avatar is above — focalY
              // can be negative; the painter clips at -3× canvas height.
              const widgetHeight = 160.0;
              final widgetTop = h * amountFraction - 80.0;
              final avatarScreenY = h * avatarFraction;
              final focalYFraction = (avatarScreenY - widgetTop) / widgetHeight;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── Text reform — particles descend and lock into amount ──
                  Positioned(
                    top: widgetTop,
                    left: 0,
                    right: 0,
                    height: widgetHeight,
                    child: DropTextDissolve(
                      text: _amountStr,
                      style: _kAmountStyle,
                      direction: DissolveDirection.reform,
                      controller: _reformCtrl,
                      focalXFraction: 0.5,
                      focalYFraction: focalYFraction,
                      height: widgetHeight,
                      samplingDensity: 0.28,
                      maxParticles: 2000,
                    ),
                  ),

                  // ── Glow bloom — brightens after text solidifies ──
                  Positioned(
                    top: widgetTop,
                    left: 0,
                    right: 0,
                    height: widgetHeight,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_reformCtrl, _glowCtrl]),
                      builder: (context, child) {
                        final settled = CurvedAnimation(
                          parent: _reformCtrl,
                          curve: const Interval(0.70, 1.0, curve: Curves.easeOut),
                        ).value;
                        final pulse = settled * (0.7 + _glowCtrl.value * 0.3);
                        return CustomPaint(
                          painter: _GlowTextPainter(
                            text: _amountStr,
                            style: _kAmountStyle,
                            opacity: pulse * 0.5,
                            blurRadius: 24.0 + _glowCtrl.value * 12.0,
                          ),
                        );
                      },
                    ),
                  ),

                  // ── Sender avatar — focal source ──
                  Positioned(
                    top: h * avatarFraction - 28,
                    left: w / 2 - 28,
                    child: ZendAvatar(
                      radius: 28,
                      photoUrl: widget.senderAvatarUrl,
                      initials: widget.senderZendtag.isNotEmpty
                          ? widget.senderZendtag[0].toUpperCase()
                          : '?',
                    ),
                  ),

                  // ── From tag ──
                  Positioned(
                    top: h * amountFraction + 58,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: _labelCtrl,
                      child: Text(
                        'from @${widget.senderZendtag}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 14,
                          color: Color(0x80FFFFFF),
                        ),
                      ),
                    ),
                  ),

                  // ── Note ──
                  if (widget.note != null && widget.note!.isNotEmpty)
                    Positioned(
                      top: h * amountFraction + 90,
                      left: 32,
                      right: 32,
                      child: FadeTransition(
                        opacity: CurvedAnimation(
                          parent: _labelCtrl,
                          curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
                        ),
                        child: Text(
                          '"${widget.note}"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 13,
                            color: Color(0x55FFFFFF),
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                  // ── Tap hint ──
                  Positioned(
                    bottom: 44,
                    left: 0,
                    right: 0,
                    child: Text(
                      'Tap to close',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.15),
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

/// Simple glow behind the solidified amount — blurred duplicate text.
class _GlowTextPainter extends CustomPainter {
  const _GlowTextPainter({
    required this.text,
    required this.style,
    required this.opacity,
    required this.blurRadius,
  });

  final String text;
  final TextStyle style;
  final double opacity;
  final double blurRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          foreground: Paint()
            ..color = Colors.white.withValues(alpha: opacity)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius),
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: size.width);
    painter.paint(canvas, Offset(0, (size.height - painter.height) / 2));
  }

  @override
  bool shouldRepaint(_GlowTextPainter old) =>
      old.opacity != opacity || old.blurRadius != blurRadius;
}
