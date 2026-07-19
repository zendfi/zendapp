import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/zend_avatar.dart';
import 'drop_glow_effect.dart';

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
  /// Single controller drives the full glow-reform effect.
  late final AnimationController _effectCtrl;
  /// Label fade — "from @sender" and note appear after text solidifies.
  late final AnimationController _labelCtrl;

  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _triggerHaptics();

    _effectCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..forward();

    _labelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Labels fade in when the text has mostly materialised (~60% through).
    Future.delayed(const Duration(milliseconds: 2160), () {
      if (mounted) _labelCtrl.forward();
    });

    _autoDismiss = Timer(const Duration(seconds: 9), () {
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
    _effectCtrl.dispose();
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
              const widgetHeight = 160.0;
              final widgetTop = h * amountFraction - 80.0;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── Glow reform effect ──────────────────────────────────
                  Positioned(
                    top: widgetTop,
                    left: 0,
                    right: 0,
                    height: widgetHeight,
                    child: DropGlowEffect(
                      text: _amountStr,
                      style: _kAmountStyle,
                      direction: DropGlowDirection.reform,
                      controller: _effectCtrl,
                      height: widgetHeight,
                    ),
                  ),

                  // ── Sender avatar ───────────────────────────────────────
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
