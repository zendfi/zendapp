import 'package:flutter/material.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../services/payment_rail_models.dart' show TransferVisibility;
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
              child: Icon(
                PhosphorIconsRegular.caretLeft,
                color: zt.textPrimary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$amountFormatted to @$recipientZendtag',
            style: TextStyle(
              fontFamily: 'Geist',
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
                fontFamily: 'Geist',
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
              fontFamily: 'Geist',
              fontSize: 13,
              color: pinError != null
                  ? ZendColors.destructive
                  : zt.textSecondary,
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

/// Six-dot PIN indicator widget.
class SendPinDots extends StatelessWidget {
  const SendPinDots({super.key, required this.filledCount});

  final int filledCount;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
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
  const SendPinKeypad({
    super.key,
    required this.onTap,
    required this.keyHeight,
  });

  final ValueChanged<String> onTap;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'];

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
                      fontFamily: 'Geist',
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
          ZendLoader(size: 32),
          const SizedBox(height: 20),
          Text(
            'Sending $amountFormatted to @$recipientZendtag...',
            style: TextStyle(
              fontFamily: 'Geist',
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
    this.note,
  });

  final String amountFormattedExact;
  final String recipientZendtag;
  final VoidCallback onDone;
  final String? note;

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
                child: const Icon(
                  PhosphorIconsRegular.checkCircle,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Spec §14 (LOCKED): "Sent / $20 / to @omooba / note" —
            // lightweight, no exclamation flourish (spec §59's microcopy
            // bar: short, human, confident — not decorative).
            Text(
              'Sent',
              style: TextStyle(
                fontFamily: 'Geist',
                fontWeight: FontWeight.w700,
                fontSize: 32,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.amountFormattedExact,
              style: TextStyle(
                fontFamily: 'Geist',
                fontWeight: FontWeight.w700,
                fontSize: 40,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'to @${widget.recipientZendtag}',
              style: TextStyle(
                fontFamily: 'Geist',
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
                  fontFamily: 'Geist',
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: zt.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: 'Done', onPressed: widget.onDone),
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
              child: const Icon(
                PhosphorIconsRegular.xCircle,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            // Spec §60-61: specific, human, recoverable — not decorative
            // filler like "Oops".
            Text(
              "Couldn't complete that",
              style: TextStyle(
                fontFamily: 'Geist',
                fontWeight: FontWeight.w700,
                fontSize: 28,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 15,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: 'Retry', onPressed: onRetry),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlineActionButton(label: 'Cancel', onPressed: onCancel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Network uncertainty after submission — spec §16 (LOCKED): "Do not
/// immediately tell the user Failed if the server hasn't confirmed whether
/// the payment happened... We're checking that now. Don't send again yet."
///
/// Deliberately has no Retry/Cancel buttons — the whole point of this
/// stage is that the user cannot act again until it resolves into
/// [SendStage.success] or [SendStage.error] on its own (enforced by
/// [SendFlowSheet]'s PopScope also blocking dismissal here). Offering a
/// way out would recreate exactly the double-send risk this state exists
/// to prevent.
class SendUncertainStage extends StatelessWidget {
  const SendUncertainStage({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ZendLoader(size: 40, strokeWidth: 3, color: zt.textSecondary),
            const SizedBox(height: 24),
            Text(
              "We're checking that now.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Don't send again yet.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 15,
                color: zt.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Visibility pill ──────────────────────────────────────────────────────────

/// Compact control for who may see a payment in Activity.
///
/// Deliberately a single tappable summary rather than three inline options: the
/// default is right for most payments, so the common path stays readable at a
/// glance and skippable, with the choice one tap away for the minority who want it.
///
/// Shared between the entry sheet's confirm state and the full send sheet so both
/// offer the same three choices with identical wording — a privacy control that
/// says different things in different places is worse than one that is missing.
class VisibilityPill extends StatelessWidget {
  const VisibilityPill({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TransferVisibility value;
  final ValueChanged<TransferVisibility> onChanged;

  static IconData _iconFor(TransferVisibility value) => switch (value) {
    TransferVisibility.private => PhosphorIconsRegular.lockSimple,
    TransferVisibility.publicWithoutAmount => PhosphorIconsRegular.usersThree,
    TransferVisibility.publicWithAmount => PhosphorIconsRegular.globeSimple,
  };

  static String _labelFor(TransferVisibility value) => switch (value) {
    TransferVisibility.private => 'Private',
    TransferVisibility.publicWithoutAmount => 'Shared, no amount',
    TransferVisibility.publicWithAmount => 'Shared',
  };

  /// Phrased as "not shared" rather than "only you". Visibility resolves
  /// most-open-wins across both parties, so the recipient can still surface an edge
  /// the sender kept private — promising secrecy would be a guarantee the model
  /// does not make.
  static String _subtitleFor(TransferVisibility value) => switch (value) {
    TransferVisibility.private => 'Not shared with your mutuals',
    TransferVisibility.publicWithoutAmount =>
      'Mutuals see the payment, not the amount',
    TransferVisibility.publicWithAmount =>
      'Mutuals see the payment and the amount',
  };

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Semantics(
      button: true,
      label: 'Payment visibility: ${_labelFor(value)}. Tap to change.',
      child: GestureDetector(
        onTap: () => _showOptions(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: zt.bgElevated,
            borderRadius: BorderRadius.circular(ZendRadii.pill),
            border: Border.all(color: zt.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Primary text rather than secondary, and weighted: this is a
              // decision about who sees a payment, sitting one tap from an
              // irreversible action. Muted grey read as a passive caption, which
              // meant people scrolled past it without registering there was a
              // choice to make.
              Icon(_iconFor(value), size: 16, color: zt.textPrimary),
              const SizedBox(width: 8),
              Text(
                _labelFor(value),
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              // The caret stays secondary — it signals tappability without
              // competing with the label for attention.
              Icon(
                PhosphorIconsRegular.caretUpDown,
                size: 14,
                color: zt.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    final zt = ZendTheme.of(context);
    final picked = await showModalBottomSheet<TransferVisibility>(
      context: context,
      backgroundColor: zt.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                'Who can see this?',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Applies to this payment only.',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: zt.textSecondary,
                ),
              ),
            ),
            for (final option in TransferVisibility.values)
              _VisibilityOptionRow(
                icon: _iconFor(option),
                title: _labelFor(option),
                subtitle: _subtitleFor(option),
                selected: option == value,
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && picked != value) onChanged(picked);
  }
}

class _VisibilityOptionRow extends StatelessWidget {
  const _VisibilityOptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? zt.accent : zt.textSecondary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: zt.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12,
                      color: zt.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                PhosphorIconsRegular.checkCircle,
                size: 18,
                color: zt.accent,
              ),
          ],
        ),
      ),
    );
  }
}
