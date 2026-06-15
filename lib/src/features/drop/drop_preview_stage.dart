import 'package:flutter/material.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/drop_models.dart';

class DropPreviewStage extends StatefulWidget {
  const DropPreviewStage({
    super.key,
    required this.amount,
    required this.receiver,
    required this.isConfirmed,
  });

  final double amount;
  final DiscoveredReceiver receiver;
  final bool isConfirmed;

  @override
  State<DropPreviewStage> createState() => _DropPreviewStageState();
}

class _DropPreviewStageState extends State<DropPreviewStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  String get _amountFormatted {
    if (widget.amount == widget.amount.roundToDouble()) {
      return '\$${widget.amount.toStringAsFixed(0)}';
    }
    return '\$${widget.amount.toStringAsFixed(2)}';
  }

  String get _displayName {
    return widget.receiver.preview?.displayName.isNotEmpty == true
        ? widget.receiver.preview!.displayName
        : '@${widget.receiver.preview?.zendtag ?? '?'}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        // Amount
        Text(
          _amountFormatted,
          style: TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 44,
            fontStyle: FontStyle.italic,
            color: zt.textPrimary,
          ),
        ),
        const SizedBox(height: 28),
        // Avatar — unconfirmed is dimmed + pulsing; confirmed is full opacity
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            final opacity = widget.isConfirmed
                ? 1.0
                : 0.35 + _pulseCtrl.value * 0.25;
            return AnimatedScale(
              scale: widget.isConfirmed ? 1.0 : 0.95,
              duration: const Duration(milliseconds: 300),
              child: Opacity(
                opacity: opacity,
                child: ZendAvatar(
                  radius: 36,
                  photoUrl: widget.receiver.preview?.avatarUrl,
                  initials: _displayName.isNotEmpty
                      ? _displayName[0].toUpperCase()
                      : null,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // Zendtag
        Text(
          '@${widget.receiver.preview?.zendtag ?? '?'}',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: zt.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.isConfirmed ? 'Verified nearby' : 'Verifying identity…',
          style: TextStyle(
            fontFamily: 'DMMono',
            fontSize: 12,
            color: widget.isConfirmed ? zt.accentBright : zt.textSecondary,
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
