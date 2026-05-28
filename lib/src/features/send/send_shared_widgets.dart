import 'package:flutter/material.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

/// Shared PIN entry stage widget, extracted from SendFlowSheet for reuse
/// in QrPaymentSheet and other payment flows.
class SendPinStage extends StatelessWidget {
  const SendPinStage({
    super.key,
    required this.amountFormatted,
    required this.recipientZendtag,
    required this.note,
    required this.pinDigits,
    required this.pinError,
    required this.shakeAnimation,
    required this.shakeController,
    required this.onKey,
    required this.onBack,
  });

  final String amountFormatted;
  final String recipientZendtag;
  final String note;
  final String pinDigits;
  final String? pinError;
  final Animation<double> shakeAnimation;
  final AnimationController shakeController;
  final ValueChanged<String> onKey;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final compact = MediaQuery.of(context).size.height < 760;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: Icon(Icons.arrow_back, color: zt.textPrimary, size: 22),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$amountFormatted to @$recipientZendtag',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: zt.textPrimary,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: zt.textSecondary,
              ),
            ),
          ],
          SizedBox(height: compact ? 20 : 28),
          // PIN dots with shake
          AnimatedBuilder(
            animation: shakeController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(shakeAnimation.value, 0),
                child: child,
              );
            },
            child: SendPinDots(filledCount: pinDigits.length),
          ),
          const SizedBox(height: 10),
          Text(
            pinError ?? 'Enter your PIN',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              color: pinError != null ? ZendColors.destructive : zt.textSecondary,
            ),
          ),
          const Spacer(),
          SendPinKeypad(onTap: onKey, keyHeight: compact ? 56 : 64),
          SizedBox(height: compact ? 4 : 12),
        ],
      ),
    );
  }
}

/// Four-dot PIN indicator widget.
class SendPinDots extends StatelessWidget {
  const SendPinDots({super.key, required this.filledCount});

  final int filledCount;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final filled = index < filledCount;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? zt.accent : Colors.transparent,
              border: Border.all(
                color: filled ? zt.accent : zt.border,
                width: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// 3×4 PIN keypad widget.
class SendPinKeypad extends StatelessWidget {
  const SendPinKeypad({super.key, required this.onTap, required this.keyHeight});

  final ValueChanged<String> onTap;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '', '0', 'del',
    ];

    return Column(
      children: [
        for (var row = 0; row < 4; row++) ...[
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: col == 2 ? 0 : 10,
                      bottom: row == 3 ? 0 : 12,
                    ),
                    child: keys[row * 3 + col].isEmpty
                        ? SizedBox(height: keyHeight)
                        : SendPinKeypadKey(
                            label: keys[row * 3 + col],
                            keyHeight: keyHeight,
                            onTap: () => onTap(keys[row * 3 + col]),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Individual key in the PIN keypad.
class SendPinKeypadKey extends StatefulWidget {
  const SendPinKeypadKey({
    super.key,
    required this.label,
    required this.onTap,
    required this.keyHeight,
  });

  final String label;
  final VoidCallback onTap;
  final double keyHeight;

  @override
  State<SendPinKeypadKey> createState() => _SendPinKeypadKeyState();
}

class _SendPinKeypadKeyState extends State<SendPinKeypadKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _pressed = true);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: ZendMotion.keypadPress,
        curve: Curves.easeOut,
        scale: _pressed ? 0.94 : 1,
        child: SizedBox(
          height: widget.keyHeight,
          child: Center(
            child: widget.label == 'del'
                ? ZendBackspaceIcon(color: zt.textPrimary, size: 24)
                : Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 24,
                      color: zt.textPrimary,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Processing stage shown while a transfer is in flight.
class SendProcessingStage extends StatelessWidget {
  const SendProcessingStage({
    super.key,
    required this.amountFormatted,
    required this.recipientZendtag,
  });

  final String amountFormatted;
  final String recipientZendtag;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ZendLoader(size: 32),
          const SizedBox(height: 20),
          Text(
            'Sending $amountFormatted to @$recipientZendtag...',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: zt.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Success stage shown after a transfer completes.
class SendSuccessStage extends StatefulWidget {
  const SendSuccessStage({
    super.key,
    required this.amountFormattedExact,
    required this.recipientZendtag,
    required this.onDone,
  });

  final String amountFormattedExact;
  final String recipientZendtag;
  final VoidCallback onDone;

  @override
  State<SendSuccessStage> createState() => _SendSuccessStageState();
}

class _SendSuccessStageState extends State<SendSuccessStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkScale = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );
    _checkController.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _checkScale,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: ZendColors.positive,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Zent It!',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 40,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.amountFormattedExact} to @${widget.recipientZendtag}',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Done',
                onPressed: widget.onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error stage shown when a transfer fails.
class SendErrorStage extends StatelessWidget {
  const SendErrorStage({
    super.key,
    required this.errorMessage,
    required this.onRetry,
    required this.onCancel,
  });

  final String errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: ZendColors.destructive,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'Oops',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontSize: 32,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 15,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Retry',
                onPressed: onRetry,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlineActionButton(
                label: 'Cancel',
                onPressed: onCancel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
