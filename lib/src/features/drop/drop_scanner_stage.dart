import 'package:flutter/material.dart';
import '../../design/zend_tokens.dart';

class DropScannerStage extends StatefulWidget {
  const DropScannerStage({super.key, required this.amount});
  final double amount;

  @override
  State<DropScannerStage> createState() => _DropScannerStageState();
}

class _DropScannerStageState extends State<DropScannerStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
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
            fontSize: 48,
            fontStyle: FontStyle.italic,
            color: zt.textPrimary,
          ),
        ),
        const SizedBox(height: 32),
        // Radar animation
        SizedBox(
          width: 120,
          height: 120,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer pulse ring
                  Opacity(
                    opacity: (1 - _pulse.value).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.4 + _pulse.value * 0.6,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: zt.accentBright,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Inner static circle
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: zt.accentBright.withValues(alpha: 0.15),
                      border: Border.all(
                        color: zt.accentBright.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.bluetooth_searching,
                      color: zt.accentBright,
                      size: 24,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Scanning for nearby Zend users\u2026',
          style: TextStyle(
            fontFamily: 'DMMono',
            fontSize: 13,
            color: zt.textSecondary,
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
