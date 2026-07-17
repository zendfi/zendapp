import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/drop_models.dart';

/// Tier 1 (≤$50) confirmation stage.
///
/// Displays a 2-second animated countdown ring. When complete, fires a gold
/// particle burst from the ring's position then calls [onExecute].
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
    with TickerProviderStateMixin {
  late final AnimationController _countdownCtrl;

  // GlobalKey so we can find the ring's screen position
  final _ringKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    _countdownCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _countdownCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onExecute();
      }
    });

    _countdownCtrl.forward();
  }

  @override
  void dispose() {
    _countdownCtrl.dispose();
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
    final model = ZendScope.of(context);
    final senderAvatarUrl = model.currentAvatarUrl;
    final senderInitial = model.currentZendtag?.isNotEmpty == true
        ? model.currentZendtag![0].toUpperCase()
        : 'Y';

    return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            // Sender → receiver row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ZendAvatar(radius: 20, photoUrl: senderAvatarUrl, initials: senderInitial),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 16, color: zt.textSecondary),
                const SizedBox(width: 8),
                ZendAvatar(
                  radius: 20,
                  photoUrl: widget.receiver.preview?.avatarUrl,
                  initials: _zendtag.isNotEmpty ? _zendtag[0].toUpperCase() : null,
                ),
              ],
            ),
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
            // Countdown ring with avatar
            SizedBox(
              key: _ringKey,
              width: 80,
              height: 80,
              child: AnimatedBuilder(
                animation: _countdownCtrl,
                builder: (context, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _countdownCtrl.value,
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
            GestureDetector(
              onTap: () {
                _countdownCtrl.stop();
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
