import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/zend_format.dart';
import 'zend_drawn.dart';
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
          // The amount holds for a beat, then folds down into a paper
          // plane at its own centre, and the plane takes it away: one
          // gesture rather than an amount leaving and a plane arriving.
          final fold = reduced
              ? 0.0
              : Curves.easeInCubic.transform(((t - 0.16) / 0.2).clamp(0, 1));
          final amountOpacity = reduced ? 1.0 : (1 - fold).clamp(0.0, 1.0);
          final markT = ((t - 0.3) / 0.32).clamp(0.0, 1.0);
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
                    Transform.rotate(
                      angle: fold * 0.35,
                      child: Transform.scale(
                        scale: 1 - 0.9 * fold,
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
                    ),
                    // A paper plane takes it away along a dashed trail
                    // (zend-site's final section).
                    if (!reduced && markT > 0 && markT < 1)
                      IgnorePointer(
                        child: CustomPaint(
                          size: const Size(360, 260),
                          painter: _PlaneFlightPainter(
                            progress: ZendMotion.ease.transform(markT),
                            plane: zt.textPrimary,
                            trail: zt.faint,
                          ),
                        ),
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
        duration: _down ? const Duration(milliseconds: 120) : ZendMotion.quick,
        curve: _down ? ZendMotion.ease : ZendMotion.bounce,
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
    final textNote = note != null && note.isNotEmpty && !isMediaNote(note)
        ? note
        : null;
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
            final counted = reduced
                ? widget.amount
                : widget.amount *
                      Curves.easeOutCubic.transform(_seg(t, 0.06, 0.42));
            final noteIn = reduced ? 1.0 : _seg(t, 0.3, 0.45);
            // The money arrives as a Zend note (zend-site's hero), landing
            // with one soft overshoot and settling at its resting tilt.
            final landT = reduced
                ? 1.0
                : ZendMotion.bounce.transform(_seg(t, 0, 0.32));
            final noteWidth = math.min(
              MediaQuery.sizeOf(context).width - 88,
              340.0,
            );
            final amount = Transform.translate(
              offset: Offset(0, (1 - landT) * 40),
              child: Transform.rotate(
                angle: (1 - landT) * 6 * math.pi / 180,
                child: Transform.scale(
                  scale: 0.5 + 0.5 * landT,
                  child: ZendBanknote(
                    width: noteWidth,
                    legal: widget.viaLink ? 'MONEY LINK' : 'WORKS ANYWHERE',
                    line: textNote == null ? null : '“$textNote”',
                    amount: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: ZendLoudAmountText(
                        formatMoney(counted),
                        semanticsLabel: '',
                        style: ZendTextStyles.displayXl.copyWith(
                          fontSize: 60,
                          letterSpacing: -60 * 0.055,
                          color: ZendBanknote.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
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
                          const SizedBox(height: 20),
                          amount,
                          if (emoji != null)
                            Opacity(
                              opacity: noteIn,
                              child: Transform.translate(
                                offset: Offset(0, (1 - noteIn) * 12),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 20),
                                  child: ZendEmojiTile(
                                    emoji,
                                    size: 64,
                                    burst: !reduced,
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

/// Fades [child] in while it rises 24px into place, once, after [delay]
/// (zend-site's `rise`, 1s on the house curve). Stagger a column by giving
/// each piece a later delay: 0, 120, 240, 340ms reads as one gesture. Shows
/// at rest straight away under Reduce Motion.
class ZendRise extends StatefulWidget {
  const ZendRise({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 1000),
    this.distance = 24,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double distance;

  @override
  State<ZendRise> createState() => _ZendRiseState();
}

class _ZendRiseState extends State<ZendRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMicroseconds / _c.duration!.inMicroseconds,
      1,
      curve: ZendMotion.ease,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ZendMotion.reduced(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, widget.distance * (1 - _t.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Swaps its text with zend-site's `swap`: the new value comes up 0.18em
/// out of a 6px blur as it fades in. Use it where an amount or label
/// changes in place (a balance after a currency switch). Plain under
/// Reduce Motion.
class ZendBlurSwap extends StatelessWidget {
  const ZendBlurSwap({super.key, required this.child, required this.swapKey});

  final Widget child;

  /// Changes whenever the shown value changes (the formatted string).
  final Object swapKey;

  @override
  Widget build(BuildContext context) {
    if (ZendMotion.reduced(context)) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: ZendMotion.ease,
      switchOutCurve: const Threshold(0),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.center, children: [?current]),
      transitionBuilder: (child, anim) => AnimatedBuilder(
        animation: anim,
        builder: (context, c) {
          final t = anim.value;
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 3 * (1 - t),
                sigmaY: 3 * (1 - t),
              ),
              child: FractionalTranslation(
                translation: Offset(0, 0.18 * (1 - t)),
                child: c,
              ),
            ),
          );
        },
        child: child,
      ),
      child: KeyedSubtree(key: ValueKey(swapKey), child: child),
    );
  }
}

/// The send celebration's paper plane: flies a curve up and off to the top
/// right, drawing a dashed trail behind it that fades as it goes.
class _PlaneFlightPainter extends CustomPainter {
  _PlaneFlightPainter({
    required this.progress,
    required this.plane,
    required this.trail,
  });

  final double progress;
  final Color plane, trail;

  // A cubic from below left of centre, looping up past the amount.
  // Starts where the amount folded, at the centre, and climbs off to the
  // top right.
  static const _p0 = Offset(0, 0);
  static const _p1 = Offset(0.25, 0.22);
  static const _p2 = Offset(0.3, -0.35);
  static const _p3 = Offset(0.65, -0.45);

  static Offset _at(double t) {
    final u = 1 - t;
    return _p0 * (u * u * u) +
        _p1 * (3 * u * u * t) +
        _p2 * (3 * u * t * t) +
        _p3 * (t * t * t);
  }

  static Offset _tangent(double t) {
    final u = 1 - t;
    return (_p1 - _p0) * (3 * u * u) +
        (_p2 - _p1) * (6 * u * t) +
        (_p3 - _p2) * (3 * t * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    Offset px(Offset o) => Offset(
      size.width / 2 + o.dx * size.width,
      size.height / 2 + o.dy * size.height,
    );
    final fade = progress > 0.8 ? (1 - progress) / 0.2 : 1.0;
    final dash = Paint()
      ..color = trail.withValues(alpha: 0.8 * fade)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    // Dashes every few percent of the way, up to the plane.
    for (var t = 0.0; t < progress - 0.03; t += 0.035) {
      final a = px(_at(t)), b = px(_at(math.min(t + 0.012, progress)));
      canvas.drawLine(a, b, dash);
    }
    final d = _tangent(progress);
    paintZendPaperPlane(
      canvas,
      at: px(_at(progress)),
      angle: math.atan2(d.dy * size.height, d.dx * size.width),
      color: plane.withValues(alpha: fade),
      // Unfolds out of the amount: small at first, full size a quarter of
      // the way along.
      scale: 1.8 * (0.35 + 0.65 * (progress / 0.25).clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(_PlaneFlightPainter old) =>
      old.progress != progress || old.plane != plane || old.trail != trail;
}

/// A money link going out: the letter slides into an envelope, the flap
/// folds down, and the Z seal presses it shut, with a thump as it lands.
/// A brief overlay that removes itself; tap to skip. Under Reduce Motion
/// it's the sealed envelope, fading in and out.
Future<void> showEnvelopeSealed(BuildContext context) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _EnvelopeSealed(
      onDone: () {
        entry.remove();
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  overlay.insert(entry);
  return done.future;
}

class _EnvelopeSealed extends StatefulWidget {
  const _EnvelopeSealed({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_EnvelopeSealed> createState() => _EnvelopeSealedState();
}

class _EnvelopeSealedState extends State<_EnvelopeSealed>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  bool _thumped = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      // The seal lands about 70% of the way through the sealing.
      if (!_thumped && _c.value > 0.55) {
        _thumped = true;
        unawaited(ZendFeel.sendConfirmed());
      }
    });
    _c.forward().whenComplete(_finish);
  }

  void _finish() {
    if (_closing) return;
    _closing = true;
    widget.onDone();
  }

  void _skip() {
    if (_c.value < 0.85) _c.animateTo(1, duration: ZendMotion.quick);
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final opacity = t < 0.1
              ? t / 0.1
              : t > 0.85
              ? (1 - t) / 0.15
              : 1.0;
          // Sealing runs over the first three quarters, then it rests.
          final seal = reduced ? 1.0 : (t / 0.78).clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: ColoredBox(
              color: zt.bgPrimary.withValues(alpha: 0.92),
              child: Center(
                child: Semantics(
                  liveRegion: true,
                  label: 'Your money link is on its way',
                  child: ZendEnvelope(width: 200, progress: seal),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
