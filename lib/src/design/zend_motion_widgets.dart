import 'dart:async';

import 'package:flutter/material.dart';

import '../core/zend_format.dart';
import 'zend_link_card.dart' show ZendTicketBorder;
import 'zend_mark.dart';
import 'zend_money.dart';
import 'zend_tokens.dart';

/// Pull-to-refresh: the stock spinner in ink.
class ZendRefresh extends StatelessWidget {
  const ZendRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: zt.textPrimary,
      backgroundColor: zt.bgElevated,
      child: child,
    );
  }
}

/// The send-confirmed moment: amount lifts off, the Z sweeps across, the
/// check lands. Shown as a brief overlay over whatever is on screen, then
/// removes itself. Under Reduce Motion it is a short fade.
Future<void> showSendCelebration(
  BuildContext context, {
  required double amount,
  String? emoji,
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SendCelebration(
      amount: amount,
      emoji: emoji,
      onDone: () {
        entry.remove();
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  overlay.insert(entry);
  unawaited(ZendFeel.sendConfirmed());
  return done.future;
}

class _SendCelebration extends StatefulWidget {
  const _SendCelebration({
    required this.amount,
    required this.onDone,
    this.emoji,
  });

  final double amount;
  final String? emoji;
  final VoidCallback onDone;

  @override
  State<_SendCelebration> createState() => _SendCelebrationState();
}

class _SendCelebrationState extends State<_SendCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final reduced = ZendMotion.reduced(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // 0–0.15 fade in, 0.85–1 fade out.
          final opacity = t < 0.15
              ? t / 0.15
              : t > 0.85
              ? (1 - t) / 0.15
              : 1.0;
          final lift = reduced
              ? 0.0
              : Curves.easeInCubic.transform((t / 0.5).clamp(0, 1)) * -120;
          final amountOpacity = reduced ? 1.0 : (1 - (t / 0.5)).clamp(0.0, 1.0);
          final markT = ((t - 0.25) / 0.35).clamp(0.0, 1.0);
          final checkT = ZendMotion.springSoft.transform(
            ((t - 0.5) / 0.3).clamp(0.0, 1.0),
          );
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: ColoredBox(
              color: zt.bgPrimary.withValues(alpha: 0.92),
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(0, lift),
                      child: Opacity(
                        opacity: amountOpacity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.emoji != null)
                              Text(
                                widget.emoji!,
                                style: ZendTextStyles.emoji.copyWith(
                                  fontSize: 48,
                                ),
                              ),
                            ZendLoudAmountText(
                              formatMoney(widget.amount),
                              style: ZendTextStyles.displayL.copyWith(
                                color: zt.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!reduced && markT > 0 && markT < 1)
                      Transform.translate(
                        offset: Offset((markT - 0.5) * 320, 0),
                        child: const ZendMark(size: 64),
                      ),
                    if (checkT > 0)
                      Transform.scale(
                        scale: checkT,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: zt.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 56,
                            color: zt.onAccent,
                            semanticLabel: 'Sent',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Short horizontal shake for errors (design revamp motion table).
class ZendShake extends StatefulWidget {
  const ZendShake({super.key, required this.trigger, required this.child});

  /// Change this value to replay the shake.
  final Object? trigger;
  final Widget child;

  @override
  State<ZendShake> createState() => _ZendShakeState();
}

class _ZendShakeState extends State<ZendShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  @override
  void didUpdateWidget(ZendShake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger != null) {
      unawaited(ZendFeel.error());
      if (!ZendMotion.reduced(context)) _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      final t = _c.value;
      final dx = (1 - t) * 10 * (((t * 8).floor().isEven) ? 1 : -1);
      return Transform.translate(
        offset: Offset(_c.isAnimating ? dx : 0, 0),
        child: child,
      );
    },
    child: widget.child,
  );
}

/// Cards sink slightly under the finger and spring back, so tapping into a
/// payment feels physical (the "card to receipt" moment starts here).
class ZendPressScale extends StatefulWidget {
  const ZendPressScale({super.key, required this.child});

  final Widget child;

  @override
  State<ZendPressScale> createState() => _ZendPressScaleState();
}

class _ZendPressScaleState extends State<ZendPressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (ZendMotion.reduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: ZendMotion.quick,
        curve: ZendMotion.springSnappy,
        child: widget.child,
      ),
    );
  }
}

/// The receive moment: money from a person (a payment or a Link) lands with
/// a felt "ba-dum", the amount springs up and counts into place, two ink
/// rings ripple out, and the sender's emoji or note comes with it.
///
/// Monochrome on purpose: the feeling comes from motion, haptics and the
/// note, not from colour. A Link arrival draws the amount inside the Link
/// silhouette. Tap anywhere to dismiss early. Under Reduce Motion it's a
/// short fade with the haptic.
///
/// Calls within a few seconds of each other show once, since one arrival
/// can reach the app by two routes (the live event and the Link flow).
Future<void> showReceiveMoment(
  BuildContext context, {
  required double amount,
  required String from,
  String? note,
  bool viaLink = false,
}) async {
  final now = DateTime.now();
  final last = _lastReceiveMoment;
  if (last != null && now.difference(last) < const Duration(seconds: 4)) {
    return;
  }
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _lastReceiveMoment = now;
  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ReceiveMoment(
      amount: amount,
      from: from,
      note: note,
      viaLink: viaLink,
      onDone: () {
        entry.remove();
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  overlay.insert(entry);
  unawaited(ZendFeel.received());
  return done.future;
}

DateTime? _lastReceiveMoment;

class _ReceiveMoment extends StatefulWidget {
  const _ReceiveMoment({
    required this.amount,
    required this.from,
    required this.onDone,
    required this.viaLink,
    this.note,
  });

  final double amount;
  final String from;
  final String? note;
  final bool viaLink;
  final VoidCallback onDone;

  @override
  State<_ReceiveMoment> createState() => _ReceiveMomentState();
}

class _ReceiveMomentState extends State<_ReceiveMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_finish);
  }

  void _finish() {
    if (_closing) return;
    _closing = true;
    widget.onDone();
  }

  /// Tap to skip: jump to the fade-out instead of cutting to nothing.
  void _skip() {
    if (_c.value < 0.85) _c.animateTo(1, duration: ZendMotion.quick);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final reduced = ZendMotion.reduced(context);
    final note = widget.note?.trim();
    final emoji = note != null && isEmojiNote(note) ? note : null;
    final textNote =
        note != null && note.isNotEmpty && !isMediaNote(note) ? note : null;
    final label = '${widget.from} sent you ${formatMoney(widget.amount)}';

    return Semantics(
      liveRegion: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final opacity = t < 0.08
                ? t / 0.08
                : t > 0.85
                ? (1 - t) / 0.15
                : 1.0;
            final pop = reduced
                ? 1.0
                : 0.6 + 0.4 * ZendMotion.springSoft.transform(_seg(t, 0, 0.3));
            final counted = reduced
                ? widget.amount
                : widget.amount *
                      Curves.easeOutCubic.transform(_seg(t, 0.06, 0.42));
            final noteIn = reduced ? 1.0 : _seg(t, 0.3, 0.45);

            Widget amount = FittedBox(
              fit: BoxFit.scaleDown,
              child: ZendLoudAmountText(
                formatMoney(counted),
                semanticsLabel: '',
                style: ZendTextStyles.displayXl.copyWith(
                  color: zt.textPrimary,
                ),
              ),
            );
            if (widget.viaLink) {
              amount = DecoratedBox(
                decoration: ShapeDecoration(
                  shape: ZendTicketBorder(
                    side: BorderSide(color: zt.textPrimary, width: 1.5),
                    radius: 24,
                    notchRadius: 12,
                    cut: 26,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: amount,
                ),
              );
            }

            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Material(
                color: zt.bgPrimary.withValues(alpha: 0.96),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!reduced)
                      for (final delay in const [0.0, 0.16])
                        _Ripple(
                          progress: _seg(t, delay, delay + 0.55),
                          color: zt.textPrimary,
                        ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${widget.from} sent you',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZendTextStyles.title.copyWith(
                              color: zt.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Transform.scale(scale: pop, child: amount),
                          if (emoji != null || textNote != null)
                            Opacity(
                              opacity: noteIn,
                              child: Transform.translate(
                                offset: Offset(0, (1 - noteIn) * 12),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 20),
                                  child: emoji != null
                                      ? ZendEmojiTile(
                                          emoji,
                                          size: 64,
                                          burst: !reduced,
                                        )
                                      : Text(
                                          '“$textNote”',
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: ZendTextStyles.body.copyWith(
                                            fontSize: 18,
                                            color: zt.textPrimary,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One expanding ink ring behind the receive moment.
class _Ripple extends StatelessWidget {
  const _Ripple({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
    final eased = Curves.easeOutCubic.transform(progress);
    final d = 120 + 260 * eased;
    return IgnorePointer(
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.28 * (1 - progress)),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
