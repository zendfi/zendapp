import 'dart:async';

import 'package:flutter/material.dart';

import '../core/zend_format.dart';
import 'zend_mark.dart';
import 'zend_money.dart';
import 'zend_tokens.dart';

/// Pull-to-refresh with the Z mark as the indicator (design revamp motion
/// table): the Z rotates with the pull, ticks a light haptic at the
/// threshold, and spins while refreshing. The stock spinner is kept for its
/// gesture handling but drawn invisibly.
class ZendRefresh extends StatefulWidget {
  const ZendRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<ZendRefresh> createState() => _ZendRefreshState();
}

class _ZendRefreshState extends State<ZendRefresh>
    with SingleTickerProviderStateMixin {
  static const _threshold = 80.0;
  double _pull = 0;
  bool _ticked = false;
  bool _refreshing = false;
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || _refreshing) return false;
    double next = _pull;
    if (n is OverscrollNotification &&
        n.overscroll < 0 &&
        n.dragDetails != null) {
      next = _pull - n.overscroll;
    } else if (n is ScrollUpdateNotification && n.metrics.pixels < 0) {
      next = -n.metrics.pixels;
    } else if (n is ScrollUpdateNotification &&
        _pull > 0 &&
        n.metrics.pixels >= 0) {
      next = (_pull - (n.scrollDelta ?? 0).abs()).clamp(0, 200);
    } else if (n is ScrollEndNotification) {
      next = 0;
    }
    if (next >= _threshold && !_ticked) {
      _ticked = true;
      ZendFeel.keypadTap();
    } else if (next < _threshold) {
      _ticked = false;
    }
    if (next != _pull) setState(() => _pull = next.clamp(0, 200));
    return false;
  }

  Future<void> _run() async {
    setState(() => _refreshing = true);
    if (!ZendMotion.reduced(context)) _spin.repeat();
    try {
      await widget.onRefresh();
    } finally {
      _spin.stop();
      if (mounted) {
        setState(() {
          _refreshing = false;
          _pull = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_pull / _threshold).clamp(0.0, 1.0);
    final visible = _refreshing || progress > 0.05;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: RefreshIndicator(
            onRefresh: _run,
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: widget.child,
          ),
        ),
        if (visible)
          Positioned(
            top: 12 + (_refreshing ? 24 : 36 * progress),
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: _refreshing ? 1 : progress,
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, child) => Transform.rotate(
                      angle:
                          (_refreshing ? _spin.value : progress) * 2 * 3.14159,
                      child: child,
                    ),
                    child: Semantics(
                      label: _refreshing ? 'Refreshing' : null,
                      child: const ZendMark(size: 36),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
                            Text(
                              formatUsd(widget.amount),
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
                        child: ZendGlow(
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: zt.moneyIn,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 56,
                              color: Colors.white,
                              semanticLabel: 'Sent',
                            ),
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
