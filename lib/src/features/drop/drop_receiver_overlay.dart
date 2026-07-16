import 'dart:async';
import 'package:flutter/material.dart';
import '../../design/zend_tokens.dart';
import 'drop_particle_painter.dart';
import 'package:solar_icons/solar_icons.dart';

/// Shows the receiver-side Drop animation as an app-level overlay.
///
/// Triggered when the SSE `DropConfirmed` event arrives with `role: "receiver"`.
///
/// Components (Apple Tap to Pay aesthetic — precise and quiet):
/// 1. Ultra-subtle white wash (3% opacity flash, 400ms total)
/// 2. Gold particle shower from top (~1.5s)
/// 3. Floating amount card slides up from bottom — interactive, taps to activity
void showDropReceivedOverlay({
  required BuildContext context,
  required double amount,
  required String senderZendtag,
  String? note,
  VoidCallback? onTap,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (_) => _DropReceivedOverlay(
      amount: amount,
      senderZendtag: senderZendtag,
      note: note,
      onTap: () {
        entry.remove();
        onTap?.call();
      },
      onDismiss: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _DropReceivedOverlay extends StatefulWidget {
  const _DropReceivedOverlay({
    required this.amount,
    required this.senderZendtag,
    this.note,
    this.onTap,
    required this.onDismiss,
  });

  final double amount;
  final String senderZendtag;
  final String? note;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  @override
  State<_DropReceivedOverlay> createState() => _DropReceivedOverlayState();
}

class _DropReceivedOverlayState extends State<_DropReceivedOverlay>
    with TickerProviderStateMixin {
  // Flash: fade in → hold → fade out
  late final AnimationController _flashCtrl;
  // Particle shower
  late final AnimationController _showerCtrl;
  // Card: slide up → hold → slide down on dismiss
  late final AnimationController _cardCtrl;
  // Auto-dismiss timer
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _showerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _start();
  }

  Future<void> _start() async {
    // Flash (subtle)
    _flashCtrl.forward();

    // Shower starts slightly after flash
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    _showerCtrl.forward();

    // Card slides up
    _cardCtrl.forward();

    // Auto-dismiss after 4 seconds
    _dismissTimer = Timer(const Duration(seconds: 4), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _cardCtrl.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _flashCtrl.dispose();
    _showerCtrl.dispose();
    _cardCtrl.dispose();
    _dismissTimer?.cancel();
    super.dispose();
  }

  String get _amountStr {
    if (widget.amount == widget.amount.roundToDouble()) {
      return '+\$${widget.amount.toStringAsFixed(0)}';
    }
    return '+\$${widget.amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        // ── 1. Ultra-subtle flash ──────────────────────────────────────────
        AnimatedBuilder(
          animation: _flashCtrl,
          builder: (context, _) {
            // Fade in then out: 0→1 in first 25%, 1→0 in last 75%
            final t = _flashCtrl.value;
            final opacity = t < 0.25 ? (t / 0.25) * 0.06 : (1 - t) * 0.06;
            return Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.white.withValues(alpha: opacity),
                ),
              ),
            );
          },
        ),

        // ── 2. Gold particle shower from top ──────────────────────────────
        AnimatedBuilder(
          animation: _showerCtrl,
          builder: (context, _) {
            if (_showerCtrl.value == 0) return const SizedBox.shrink();
            return Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: DropParticleShowerPainter(
                    animation: _showerCtrl,
                    screenSize: screenSize,
                    particleColor: const Color(0xFFFFD166),
                  ),
                ),
              ),
            );
          },
        ),

        // ── 3. Floating card ──────────────────────────────────────────────
        Positioned(
          left: 20,
          right: 20,
          bottom: safeBottom + 24,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1.5),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _cardCtrl,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            )),
            child: GestureDetector(
              onTap: () {
                _dismissTimer?.cancel();
                _cardCtrl.reverse().then((_) {
                  if (mounted) {
                    widget.onDismiss();
                    widget.onTap?.call();
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  // Dark surface consistent with Zend's deep green palette
                  color: ZendColors.bgDeep,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFFFD166).withValues(alpha: 0.25),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Gold dot indicator
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFD166),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Amount — large, gold, InstrumentSerif
                          Text(
                            _amountStr,
                            style: const TextStyle(
                              fontFamily: 'InstrumentSerif',
                              fontSize: 28,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFFFFD166),
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'from @${widget.senderZendtag}',
                            style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 13,
                              color: Color(0xCCF0F0F0),
                            ),
                          ),
                          if (widget.note != null && widget.note!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '"${widget.note}"',
                              style: const TextStyle(
                                fontFamily: 'DMMono',
                                fontSize: 11,
                                color: Color(0x99F0F0F0),
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Subtle chevron — signals tappability
                    const Icon(
                      SolarIconsBold.altArrowRight,
                      color: Color(0x66F0F0F0),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
