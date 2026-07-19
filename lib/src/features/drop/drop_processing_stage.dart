import 'package:flutter/material.dart';
import '../../design/zend_avatar.dart';
import '../../models/drop_models.dart';
import 'drop_glow_effect.dart';

const _kDropBackground = Color(0xFF080808);

const _kAmountStyle = TextStyle(
  fontFamily: 'InstrumentSerif',
  fontSize: 88,
  fontStyle: FontStyle.italic,
  color: Colors.white,
  height: 1.0,
);

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
      duration: const Duration(milliseconds: 4000),
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

  String get _receiverInitial =>
      _receiverZendtag.isNotEmpty ? _receiverZendtag[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _kDropBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          const avatarFraction = 0.16;
          const amountFraction = 0.52;
          const widgetHeight = 160.0;
          final widgetTop = h * amountFraction - 80.0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: widgetTop,
                left: 0,
                right: 0,
                height: widgetHeight,
                child: DropGlowEffect(
                  text: _amountStr,
                  style: _kAmountStyle,
                  direction: DropGlowDirection.dissolve,
                  controller: _ctrl,
                  height: widgetHeight,
                ),
              ),
              Positioned(
                top: h * avatarFraction - 28,
                left: w / 2 - 28,
                child: ZendAvatar(
                  radius: 28,
                  photoUrl: widget.receiver.preview?.avatarUrl,
                  initials: _receiverInitial,
                ),
              ),
              Positioned(
                top: h * avatarFraction + 34,
                left: 0,
                right: 0,
                child: Text(
                  '@$_receiverZendtag',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 13,
                    color: Color(0x55FFFFFF),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
