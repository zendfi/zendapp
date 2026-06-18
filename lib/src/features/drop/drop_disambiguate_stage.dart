import 'package:flutter/material.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_tokens.dart';
import '../../models/drop_models.dart';

/// Shown when 2+ confirmed receivers are within 8 dBm of each other and the
/// scanner cannot safely auto-select. The user picks the correct recipient.
///
/// Design principles:
/// - Sorted strongest-signal first (already sorted by BleScannerService)
/// - Signal strength shown as a discreet bar (3 levels) not raw dBm
/// - "Closest" badge on the top entry as a gentle nudge
/// - Minimal chrome — same restrained aesthetic as the rest of Drop
class DropDisambiguateStage extends StatelessWidget {
  const DropDisambiguateStage({
    super.key,
    required this.amount,
    required this.candidates,
    required this.onSelect,
    required this.onCancel,
  });

  final double amount;
  final List<DiscoveredReceiver> candidates;
  final ValueChanged<DiscoveredReceiver> onSelect;
  final VoidCallback onCancel;

  String get _amountFormatted {
    if (amount == amount.roundToDouble()) {
      return '\$${amount.toStringAsFixed(0)}';
    }
    return '\$${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Drop $_amountFormatted to…',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 24,
                  fontStyle: FontStyle.italic,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${candidates.length} nearby Zend users detected. Tap the right one.',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: zt.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Candidate list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: candidates.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = candidates[i];
              final isClosest = i == 0;
              return _CandidateTile(
                receiver: r,
                isClosest: isClosest,
                onTap: () => onSelect(r),
              );
            },
          ),
        ),
        // Cancel
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: GestureDetector(
            onTap: onCancel,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Cancel',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: zt.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.receiver,
    required this.isClosest,
    required this.onTap,
  });

  final DiscoveredReceiver receiver;
  final bool isClosest;
  final VoidCallback onTap;

  /// Maps RSSI (dBm) to a 1–3 signal bar count.
  /// -50 dBm and above → 3 bars (very close)
  /// -60 to -51 → 2 bars
  /// -61 and below → 1 bar
  int _signalBars(int rssi) {
    if (rssi >= -50) return 3;
    if (rssi >= -60) return 2;
    return 1;
  }

  String get _zendtag =>
      receiver.gattPayload?.zendtag ?? receiver.preview?.zendtag ?? '?';

  String get _displayName {
    final dn = receiver.preview?.displayName ?? '';
    return dn.isNotEmpty ? dn : '@$_zendtag';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final bars = _signalBars(receiver.rssi);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: zt.bgSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isClosest
                ? ZendColors.accentBright.withValues(alpha: 0.4)
                : zt.border,
            width: isClosest ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            ZendAvatar(
              radius: 22,
              photoUrl: receiver.preview?.avatarUrl,
              initials: _zendtag.isNotEmpty ? _zendtag[0].toUpperCase() : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _displayName,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: zt.textPrimary,
                    ),
                  ),
                  Text(
                    '@$_zendtag',
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 12,
                      color: zt.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Signal bars + "Closest" badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isClosest)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: ZendColors.accentBright.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CLOSEST',
                      style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 9,
                        color: ZendColors.accentBright,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                _SignalBars(bars: bars, activeColor: ZendColors.accentBright),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders 3 vertical bars with [bars] of them filled in [activeColor].
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.bars, required this.activeColor});

  final int bars;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        final filled = i < bars;
        final height = 6.0 + i * 4.0; // 6, 10, 14 px
        return Padding(
          padding: const EdgeInsets.only(left: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 4,
            height: height,
            decoration: BoxDecoration(
              color: filled
                  ? activeColor
                  : activeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
