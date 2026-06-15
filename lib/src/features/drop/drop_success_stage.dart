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
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    // 3 short haptic pulses (50ms each, 150ms apart)
    _triggerHaptics();

    // Auto-dismiss after 3 seconds minimum
    _autoDismissTimer = Timer(const Duration(seconds: 3), () {
      // Don't auto-dismiss — let the user tap Done
    });
  }

  void _triggerHaptics() async {
    for (int i = 0; i < 3; i++) {
      await Future.delayed(Duration(milliseconds: i * 150));
      if (mounted) HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  String get _amountFormatted => '\$${widget.amount.toStringAsFixed(2)} USDC';

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
            // Check mark
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              margin: const EdgeInsets.only(bottom: 16),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: zt.accentBright.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: zt.accentBright, width: 2),
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: zt.accentBright,
                  size: 32,
                ),
              ),
            ),
            // "Dropped ✓"
            Text(
              'Dropped ✓',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 32,
                fontStyle: FontStyle.italic,
                color: zt.accentBright,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_amountFormatted to @$_zendtag',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 16,
                color: zt.textPrimary,
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
