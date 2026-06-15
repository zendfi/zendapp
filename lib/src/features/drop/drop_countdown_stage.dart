import 'package:flutter/material.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/drop_models.dart';

/// Tier 1 (≤$50) confirmation stage.
///
/// Displays a 2-second animated countdown ring that auto-executes when
/// complete. Provides a cancel affordance that stops the countdown and
/// invokes [onCancel].
class DropCountdownStage extends StatefulWidget {
  const DropCountdownStage({
    super.key,
    required this.amount,
    required this.receiver,
    required this.note,
    required this.onExecute,
    required this.onCancel,
  });

  final double amount;
  final DiscoveredReceiver receiver;
  final String? note;
  final VoidCallback onExecute;
  final VoidCallback onCancel;

  @override
  State<DropCountdownStage> createState() => _DropCountdownStageState();
}

class _DropCountdownStageState extends State<DropCountdownStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) widget.onExecute();
      }
    });

    // Start the countdown immediately.
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _amountFormatted {
    if (widget.amount == widget.amount.roundToDouble()) {
      return '\$${widget.amount.toStringAsFixed(0)}';
    }
    return '\$${widget.amount.toStringAsFixed(2)}';
  }

  String get _zendtag =>
      widget.receiver.gattPayload?.zendtag ??
      widget.receiver.preview?.zendtag ??
      '?';

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        Text(
          'Sending $_amountFormatted',
          style: TextStyle(
            fontFamily: 'InstrumentSerif',
            fontSize: 28,
            fontStyle: FontStyle.italic,
            color: zt.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'to @$_zendtag',
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 16,
            color: zt.textSecondary,
          ),
        ),
        if (widget.note != null && widget.note!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            widget.note!,
            style: TextStyle(
              fontFamily: 'DMMono',
              fontSize: 12,
              color: zt.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 28),
        // Countdown ring with receiver avatar.
        SizedBox(
          width: 80,
          height: 80,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _ctrl.value,
                  strokeWidth: 4,
                  color: zt.accentBright,
                  backgroundColor: zt.border,
                ),
                ZendAvatar(
                  radius: 28,
                  photoUrl: widget.receiver.preview?.avatarUrl,
                  initials: _zendtag.isNotEmpty
                      ? _zendtag[0].toUpperCase()
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Cancel affordance.
        GestureDetector(
          onTap: () {
            _ctrl.stop();
            widget.onCancel();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                color: zt.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
