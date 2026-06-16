import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/zend_tokens.dart';
import '../../models/drop_models.dart';

class DropSuccessStage extends StatefulWidget {
  const DropSuccessStage({
    super.key,
    required this.amount,
    required this.receiver,
    required this.note,
    required this.onDone,
  });

  final double amount;
  final DiscoveredReceiver receiver;
  final String? note;
  final VoidCallback onDone;

  @override
  State<DropSuccessStage> createState() => _DropSuccessStageState();
}

class _DropSuccessStageState extends State<DropSuccessStage>
    with TickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final AnimationController _rippleCtrl;
  late final AnimationController _amountCtrl;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();

    // Scale-in the whole card
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();

    // Single expanding ring pulse behind the checkmark
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    // Amount counts down from full → 0 over 900ms with spring
    _amountCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    // Subtle 3-tap haptic (Apple-style: short, precise)
    _triggerHaptics();
  }

  void _triggerHaptics() async {
    // Three light taps, 80ms apart — very restrained
    for (int i = 0; i < 3; i++) {
      await Future.delayed(Duration(milliseconds: i * 80));
      if (mounted) HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _rippleCtrl.dispose();
    _amountCtrl.dispose();
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  String get _amountStr {
    if (widget.amount == widget.amount.roundToDouble()) {
      return '\$${widget.amount.toStringAsFixed(0)}';
    }
    return '\$${widget.amount.toStringAsFixed(2)}';
  }

  String get _zendtag => widget.receiver.gattPayload?.zendtag
      ?? widget.receiver.preview?.zendtag
      ?? '?';

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return ScaleTransition(
      scale: CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutBack),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // Checkmark with ripple pulse behind it
            Center(
              child: SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Expanding ring pulse
                    AnimatedBuilder(
                      animation: _rippleCtrl,
                      builder: (context, _) {
                        final t = CurvedAnimation(
                          parent: _rippleCtrl,
                          curve: Curves.easeOut,
                        ).value;
                        return Opacity(
                          opacity: (1 - t).clamp(0.0, 1.0),
                          child: Container(
                            width: 48 + t * 80,
                            height: 48 + t * 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: zt.accentBright,
                                width: (2 * (1 - t)).clamp(0.5, 2.0),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Check icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: zt.accentBright.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: zt.accentBright, width: 1.5),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: zt.accentBright,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Amount counts down — Apple-style: elegant, not dramatic
            AnimatedBuilder(
              animation: _amountCtrl,
              builder: (context, _) {
                final t = CurvedAnimation(
                  parent: _amountCtrl,
                  curve: Curves.easeInOut,
                ).value;
                // Count down from widget.amount → 0
                final displayed = widget.amount * (1 - t);
                final formatted = displayed == displayed.roundToDouble()
                    ? '\$${displayed.toStringAsFixed(0)}'
                    : '\$${displayed.toStringAsFixed(2)}';
                return Text(
                  t < 0.98 ? formatted : _amountStr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 36,
                    fontStyle: FontStyle.italic,
                    // Transitions from primary → accentBright as it settles
                    color: Color.lerp(zt.textPrimary, zt.accentBright, t),
                  ),
                );
              },
            ),

            const SizedBox(height: 4),

            Text(
              'dropped to @$_zendtag',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: zt.textSecondary,
              ),
            ),

            if (widget.note != null && widget.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '"${widget.note}"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 12,
                  color: zt.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            const SizedBox(height: 32),

            GestureDetector(
              onTap: widget.onDone,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: zt.accentBright,
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
