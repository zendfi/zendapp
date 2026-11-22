import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'zend_tokens.dart';

// Drawn objects shared with zend-site (components/Illustrations.tsx,
// ZendNote.tsx): real things in flat warm colours with soft shadows, not UI
// cards. Everything is complete at rest; motion only adds to it, and every
// animation here turns off under Reduce Motion.
//
// The signal orange appears here only as thin drawn lines (an underline, a
// stamp ring), never as a fill or body text.

/// A hand-drawn signal underline that draws itself on (zend-site's hero
/// `.swoosh`). Put it under a word with [ZendSwooshText].
class ZendSwoosh extends StatefulWidget {
  const ZendSwoosh({
    super.key,
    this.delay = const Duration(milliseconds: 700),
    this.color,
  });

  /// How long to wait before drawing, so it lands after the words have
  /// risen in.
  final Duration delay;

  /// Defaults to [ZendTheme.signal].
  final Color? color;

  @override
  State<ZendSwoosh> createState() => _ZendSwooshState();
}

class _ZendSwooshState extends State<ZendSwoosh>
    with SingleTickerProviderStateMixin {
  static const _draw = Duration(milliseconds: 1100);
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + _draw,
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
    final color = widget.color ?? ZendTheme.of(context).signal;
    final start = widget.delay.inMicroseconds / _c.duration!.inMicroseconds;
    final progress = CurvedAnimation(
      parent: _c,
      curve: Interval(start, 1, curve: ZendMotion.ease),
    );
    return CustomPaint(
      painter: _SwooshPainter(progress: progress, color: color),
    );
  }
}

class _SwooshPainter extends CustomPainter {
  _SwooshPainter({required this.progress, required this.color})
    : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0) return;
    // The site's path, in its 300×24 box, stretched to fit like
    // preserveAspectRatio="none".
    final sx = size.width / 300, sy = size.height / 24;
    final path = Path()
      ..moveTo(4 * sx, 18 * sy)
      ..cubicTo(70 * sx, 6 * sy, 190 * sx, 2 * sy, 296 * sx, 12 * sy);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.5, size.height * 0.17);
    canvas.drawPath(_partial(path, t), paint);
  }

  @override
  bool shouldRepaint(_SwooshPainter old) =>
      old.color != color || old.progress != progress;
}

/// [text] with a [ZendSwoosh] under it, sized to the word.
class ZendSwooshText extends StatelessWidget {
  const ZendSwooshText(
    this.text, {
    super.key,
    required this.style,
    this.delay = const Duration(milliseconds: 700),
  });

  final String text;
  final TextStyle style;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final size = style.fontSize ?? 16;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Text(text, style: style),
        Positioned(
          left: -size * 0.02,
          right: -size * 0.02,
          bottom: -size * 0.1,
          height: size * 0.26,
          child: IgnorePointer(child: ZendSwoosh(delay: delay)),
        ),
      ],
    );
  }
}

/// The first [t] (0–1) of [path], for drawing a stroke on.
Path _partial(Path path, double t) {
  if (t >= 1) return path;
  final out = Path();
  for (final m in path.computeMetrics()) {
    out.addPath(m.extractPath(0, m.length * t), Offset.zero);
  }
  return out;
}

// ── The Z glyph ──────────────────────────────────────────────────────────────

/// zend-site's `ZMark` path in a [size]×[size] box: the Z with its two
/// marks, slanted 7°. Fill it, then stroke it 4/100 wide with round joins.
Path zendZGlyphPath(double size) {
  final s = size / 100;
  final z = Path()
    ..moveTo(24, 22)
    ..lineTo(78, 22)
    ..lineTo(78, 35)
    ..lineTo(42, 64)
    ..lineTo(76, 64)
    ..lineTo(76, 77)
    ..lineTo(22, 77)
    ..lineTo(22, 64)
    ..lineTo(58, 35)
    ..lineTo(24, 35)
    ..close()
    ..addRect(const Rect.fromLTWH(47, 8, 10, 11))
    ..addRect(const Rect.fromLTWH(42, 80, 10, 11));
  // translate(7 0) skewX(-7deg), then scale into the box.
  final m = Matrix4.identity()
    ..scaleByDouble(s, s, 1, 1)
    ..translateByDouble(7, 0, 0, 1)
    ..multiply(Matrix4.skewX(-7 * math.pi / 180));
  return z.transform(m.storage);
}

/// The Z glyph on its own, for watermarks and small badges.
class ZendZGlyph extends StatelessWidget {
  const ZendZGlyph({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _ZGlyphPainter(color)),
  );
}

class _ZGlyphPainter extends CustomPainter {
  _ZGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = zendZGlyphPath(size.shortestSide);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = size.shortestSide * 0.04,
    );
  }

  @override
  bool shouldRepaint(_ZGlyphPainter old) => old.color != color;
}

// ── Ping dot ─────────────────────────────────────────────────────────────────

/// The signal dot with a ring pinging out of it every 1.6s (zend-site's
/// `.signal-dot`): something is waiting on someone. A still dot under
/// Reduce Motion.
class ZendPingDot extends StatefulWidget {
  const ZendPingDot({super.key, this.size = 8, this.color});

  final double size;

  /// Defaults to [ZendTheme.signal].
  final Color? color;

  @override
  State<ZendPingDot> createState() => _ZendPingDotState();
}

class _ZendPingDotState extends State<ZendPingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ZendMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? ZendTheme.of(context).signal;
    final reduced = ZendMotion.reduced(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = reduced ? 1.0 : Curves.easeOut.transform(_c.value);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5 * (1 - t)),
                spreadRadius: widget.size * 1.25 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Rubber stamp ─────────────────────────────────────────────────────────────

/// A round signal-orange rubber stamp (zend-site's hero `.stamp`): two
/// rings, text running around between them, and [label] in the middle. It
/// lands with a thump when [animate] is on (oversized and tilted, then
/// pressed down). Leave [animate] off in lists, which rebuild as they
/// scroll. Decorative: put the same words in text nearby.
class ZendStamp extends StatefulWidget {
  const ZendStamp({
    super.key,
    required this.label,
    this.size = 96,
    this.ring = 'WORKS ANYWHERE • WORKS ANYWHERE • ',
    this.animate = true,
    this.color,
  });

  final String label;
  final double size;
  final String ring;
  final bool animate;

  /// Defaults to [ZendTheme.signal].
  final Color? color;

  @override
  State<ZendStamp> createState() => _ZendStampState();
}

class _ZendStampState extends State<ZendStamp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate || ZendMotion.reduced(context)) {
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

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? ZendTheme.of(context).signal;
    final size = widget.size;
    final stamp = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _StampPainter(color: color, ring: widget.ring),
          ),
          Padding(
            padding: EdgeInsets.all(size * 0.3),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: size * 0.12,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: size * 0.004,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          // Keyframes from the site: 0% big and light, 60% pressed past
          // rest, 100% settled at −14°.
          final t = ZendMotion.ease.transform(_c.value);
          final double scale, turn, opacity;
          if (t < 0.6) {
            final k = t / 0.6;
            scale = _lerp(1.7, 0.94, k);
            turn = _lerp(-4, -15, k);
            opacity = 0.95 * k;
          } else {
            final k = (t - 0.6) / 0.4;
            scale = _lerp(0.94, 1, k);
            turn = _lerp(-15, -14, k);
            opacity = _lerp(0.95, 0.88, k);
          }
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: turn * math.pi / 180,
              child: Transform.scale(scale: scale, child: child),
            ),
          );
        },
        child: stamp,
      ),
    );
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter({required this.color, required this.ring});

  final Color color;
  final String ring;

  @override
  void paint(Canvas canvas, Size size) {
    // The site's 120-unit box.
    final u = size.shortestSide / 120;
    final c = size.center(Offset.zero);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * u;
    canvas.drawCircle(c, 57 * u, line);
    canvas.drawCircle(c, 33 * u, line);

    // Text on a 44-unit circle, starting at the left and running over the
    // top, spread to 272 units like the site's textLength.
    final r = 44 * u;
    final style = TextStyle(
      fontFamily: 'Geist',
      fontSize: 9.5 * u,
      fontWeight: FontWeight.w700,
      color: color,
    );
    final glyphs = [
      for (final ch in ring.characters)
        TextPainter(
          text: TextSpan(text: ch, style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    if (glyphs.isEmpty) return;
    final natural = glyphs.fold<double>(0, (s, g) => s + g.width);
    final gap = (272 * u - natural) / glyphs.length;
    var along = 0.0;
    for (final g in glyphs) {
      final mid = along + g.width / 2;
      final a = math.pi + mid / r;
      canvas
        ..save()
        ..translate(c.dx + r * math.cos(a), c.dy + r * math.sin(a))
        ..rotate(a + math.pi / 2);
      g.paint(canvas, Offset(-g.width / 2, -g.height * 0.62));
      canvas.restore();
      along += g.width + gap;
    }
  }

  @override
  bool shouldRepaint(_StampPainter old) =>
      old.color != color || old.ring != ring;
}

// ── Name sticker ─────────────────────────────────────────────────────────────

/// A "HELLO / my name is" sticker with [handle] written on it by hand
/// (zend-site's `NameSticker`). For the @tag sheet, and blank (no [handle])
/// for an empty People list.
class ZendNameSticker extends StatelessWidget {
  const ZendNameSticker({super.key, this.handle, this.width = 184});

  /// Shown as written, e.g. "@tolu". Null leaves a dashed line to write on.
  final String? handle;
  final double width;

  static const _paper = Color(0xFFFFFEFC);
  static const _ink = Color(0xFF0F0F0E);
  static const _onInk = Color(0xFFF7F6F3);

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final h = width * 80 / 122;
    final writing = handle;
    return Semantics(
      label: writing == null ? null : 'Name sticker: $writing',
      excludeSemantics: writing == null,
      child: Transform.rotate(
        angle: -5 * math.pi / 180,
        child: Container(
          width: width,
          height: h,
          decoration: BoxDecoration(
            color: _paper,
            borderRadius: BorderRadius.circular(width * 0.08),
            border: zt.isDark ? null : Border.all(color: zt.border),
            boxShadow: ZendShadows.lift(zt),
          ),
          foregroundDecoration: ZendGrain.decoration(
            BorderRadius.circular(width * 0.08),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                height: h * 0.33,
                width: double.infinity,
                color: _ink,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'HELLO',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: width * 0.085,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: width * 0.017,
                        color: _onInk,
                      ),
                    ),
                    SizedBox(height: width * 0.012),
                    Text(
                      'my name is',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: width * 0.048,
                        height: 1.0,
                        color: _onInk.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.08),
                  child: Center(
                    child: writing == null
                        ? CustomPaint(
                            size: Size(width * 0.6, 2),
                            painter: _DashPainter(const Color(0x590F0F0E)),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              writing,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: width * 0.17,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -width * 0.004,
                                color: _ink,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Moon ─────────────────────────────────────────────────────────────────────

/// The Moon with a Z flag in it (zend-site's `MoonScene`), for empty states:
/// nothing here yet, but it works even up there.
class ZendMoon extends StatelessWidget {
  const ZendMoon({super.key, this.size = 112});

  final double size;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _MoonPainter(star: zt.faint),
      ),
    );
  }
}

class _MoonPainter extends CustomPainter {
  _MoonPainter({required this.star});
  final Color star;

  static const _stars = [
    [22.0, 30.0],
    [58.0, 14.0],
    [200.0, 26.0],
    [222.0, 74.0],
    [16.0, 96.0],
    [36.0, 200.0],
    [214.0, 188.0],
    [190.0, 226.0],
    [96.0, 18.0],
    [8.0, 160.0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.shortestSide / 240;
    Offset p(double x, double y) => Offset(x * u, y * u);

    final dot = Paint()..color = star;
    for (var k = 0; k < _stars.length; k++) {
      canvas.drawCircle(
        p(_stars[k][0], _stars[k][1]),
        (k % 3 == 0 ? 1.8 : 1.2) * u,
        dot,
      );
    }

    // Body, lit from the top left.
    final body = Rect.fromCircle(center: p(120, 132), radius: 86 * u);
    canvas.drawCircle(
      body.center,
      body.width / 2,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.28, -0.32),
          radius: 0.72,
          colors: [Color(0xFFFCFBF7), Color(0xFFE6E2D7), Color(0xFFCBC6B8)],
          stops: [0, 0.68, 1],
        ).createShader(body),
    );
    final crater = Paint()..color = const Color(0x140F0F0E);
    for (final c in const [
      [92.0, 112.0, 15.0],
      [146.0, 156.0, 11.0],
      [104.0, 176.0, 7.0],
      [164.0, 118.0, 6.0],
      [70.0, 150.0, 5.0],
    ]) {
      canvas.drawCircle(p(c[0], c[1]), c[2] * u, crater);
    }

    // The flag: an ink pennant with the Z, planted on top.
    const ink = Color(0xFF0F0F0E);
    canvas.drawLine(
      p(150, 8),
      p(150, 52),
      Paint()
        ..color = ink
        ..strokeWidth = 2.5 * u
        ..strokeCap = StrokeCap.round,
    );
    final flag = Path()
      ..moveTo(151.5 * u, 10 * u)
      ..relativeLineTo(32 * u, 0)
      ..relativeLineTo(-7 * u, 10 * u)
      ..relativeLineTo(7 * u, 10 * u)
      ..relativeLineTo(-32 * u, 0)
      ..close();
    canvas.drawPath(flag, Paint()..color = ink);
    canvas
      ..save()
      ..translate(157 * u, 11 * u);
    final z = zendZGlyphPath(18 * u);
    canvas
      ..drawPath(z, Paint()..color = const Color(0xFFF7F6F3))
      ..restore();
  }

  @override
  bool shouldRepaint(_MoonPainter old) => old.star != star;
}

// ── Paper plane ──────────────────────────────────────────────────────────────

/// Paints zend-site's paper plane at [at], pointing along [angle] (radians),
/// [scale] times its 26-unit length.
void paintZendPaperPlane(
  Canvas canvas, {
  required Offset at,
  required double angle,
  required Color color,
  double scale = 1,
}) {
  final plane = Path()
    ..moveTo(-12, -8)
    ..lineTo(14, 0)
    ..lineTo(-12, 8)
    ..lineTo(-7, 0)
    ..close();
  canvas
    ..save()
    ..translate(at.dx, at.dy)
    ..rotate(angle)
    ..scale(scale)
    ..drawPath(plane, Paint()..color = color)
    ..restore();
}

// ── Zend note ────────────────────────────────────────────────────────────────

/// Money as a banknote (zend-site's hero `ZendNote`): warm paper with fine
/// engraved lines, a Z watermark, a foil strip, and two more notes fanned
/// out behind it. Shows [amount] large with [line] under it. Paper in both
/// modes: it's an object, not a surface.
class ZendBanknote extends StatelessWidget {
  const ZendBanknote({
    super.key,
    required this.amount,
    this.line,
    this.legal = 'WORKS ANYWHERE',
    this.width = 320,
    this.tilt = -3,
  });

  /// The amount, already styled. Draw it in [ZendBanknote.ink].
  final Widget amount;

  /// Small line under the amount: who it's from, or their note.
  final String? line;
  final String legal;
  final double width;

  /// Resting angle in degrees.
  final double tilt;

  static const ink = Color(0xFF0F0F0E);
  static const _muted = Color(0xFF5C5B57);
  static const _faint = Color(0xFFA19F99);

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final h = width / 1.72;
    final r = BorderRadius.circular(width * 0.04);
    final pad = (width * 0.06).clamp(16.0, 28.0);

    Widget sheet(Color c, double deg, Offset shift) => Transform.translate(
      offset: shift,
      child: Transform.rotate(
        angle: deg * math.pi / 180,
        child: Container(
          width: width,
          height: h,
          decoration: BoxDecoration(
            color: c,
            borderRadius: r,
            boxShadow: ZendShadows.lift(zt),
          ),
        ),
      ),
    );

    final note = Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFEFB), Color(0xFFF7F3E8), Color(0xFFEFE9DA)],
          stops: [0, 0.55, 1],
        ),
        boxShadow: ZendShadows.float(zt),
      ),
      foregroundDecoration: ZendGrain.decoration(r),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _GuillochePainter()),
          ),
          // Sheen from the top left.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.4, -0.6),
                  radius: 0.9,
                  colors: [
                    Colors.white.withValues(alpha: 0.4),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -width * 0.04,
            bottom: -h * 0.22,
            child: ZendZGlyph(
              size: width * 0.58,
              color: ink.withValues(alpha: 0.06),
            ),
          ),
          // Foil strip.
          Positioned(
            top: 0,
            bottom: 0,
            right: width * 0.24,
            width: width * 0.055,
            child: Opacity(
              opacity: 0.45,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFD6E0),
                      Color(0xFFCDEEFF),
                      Color(0xFFDCFFD2),
                      Color(0xFFFFF0B8),
                      Color(0xFFE7D6FF),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    ZendZGlyph(size: width * 0.06, color: ink),
                    SizedBox(width: width * 0.022),
                    Text(
                      'ZEND',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: width * 0.04,
                        fontWeight: FontWeight.w700,
                        letterSpacing: width * 0.04 * 0.24,
                        color: ink,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    amount,
                    if (line != null && line!.isNotEmpty) ...[
                      SizedBox(height: width * 0.015),
                      Text(
                        line!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: (width * 0.045).clamp(13.0, 15.0),
                          height: 1.3,
                          color: _muted,
                        ),
                      ),
                    ],
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    legal,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.2,
                      color: _faint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return SizedBox(
      width: width + 28,
      height: h + 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          sheet(const Color(0xFFE0D9C8), 7 + tilt + 3, const Offset(22, 22)),
          sheet(const Color(0xFFEBE6D8), 2 + tilt + 3, const Offset(12, 10)),
          Transform.rotate(angle: tilt * math.pi / 180, child: note),
        ],
      ),
    );
  }
}

/// Fine engraved sine lines, like the print on a banknote. The site's
/// generator: 16 curves across a 600×320 box.
class _GuillochePainter extends CustomPainter {
  const _GuillochePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 600, sy = size.height / 320;
    final paint = Paint()
      ..color = const Color(0x140F0F0E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var k = 0; k < 16; k++) {
      final path = Path();
      for (var x = 0; x <= 600; x += 6) {
        final y =
            160 +
            math.sin(x / 36 + k * 0.42) *
                (34 + k * 6) *
                math.cos(x / 220 + k * 0.18);
        x == 0 ? path.moveTo(x * sx, y * sy) : path.lineTo(x * sx, y * sy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_GuillochePainter old) => false;
}

// ── Receipt paper ────────────────────────────────────────────────────────────

/// A paper slip with a torn zig-zag bottom (zend-site's `.receipt`), for
/// details you might want to keep. Use [ZendLeaderRow] for its lines.
class ZendReceiptPaper extends StatelessWidget {
  const ZendReceiptPaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: zt.isDark ? zt.bgElevated : const Color(0xFFFBFAF6),
        shape: const ZendTornEdgeBorder(),
        shadows: ZendShadows.lift(zt),
        image: zt.isDark ? null : ZendGrain.image,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: child,
      ),
    );
  }
}

/// Rounded top, torn bottom: 16-wide, 10-deep teeth.
class ZendTornEdgeBorder extends ShapeBorder {
  const ZendTornEdgeBorder({
    this.radius = 16,
    this.tooth = 16,
    this.depth = 10,
  });

  final double radius, tooth, depth;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final p = Path()
      ..moveTo(rect.left, rect.top + radius)
      ..arcToPoint(
        Offset(rect.left + radius, rect.top),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.right - radius, rect.top)
      ..arcToPoint(
        Offset(rect.right, rect.top + radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.right, rect.bottom - depth);
    // Teeth from right to left, spread so they end exactly at the corner.
    final n = math.max(1, (rect.width / tooth).round());
    final w = rect.width / n;
    for (var i = n; i > 0; i--) {
      final x = rect.left + i * w;
      p
        ..lineTo(x - w / 2, rect.bottom)
        ..lineTo(x - w, rect.bottom - depth);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => ZendTornEdgeBorder(
    radius: radius * t,
    tooth: tooth * t,
    depth: depth * t,
  );
}

/// "Label ·········· value", the price-list line (zend-site's `.place`).
class ZendLeaderRow extends StatelessWidget {
  const ZendLeaderRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 15,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: CustomPaint(
                  size: const Size.fromHeight(1.5),
                  painter: _DotsPainter(zt.faint.withValues(alpha: 0.7)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.62),
              child: Text(
                value,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    valueStyle ??
                    TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: zt.textPrimary,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 1.0; x < size.width; x += 4) {
      canvas.drawCircle(Offset(x, size.height / 2), 0.75, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

// ── Paper grain ──────────────────────────────────────────────────────────────

/// Fine paper grain (zend-site's page texture), tiled. Only for drawn
/// objects that are paper (the note, the receipt, the sticker), never for
/// screens: on a screen it would read as dirt, and it costs a layer.
abstract final class ZendGrain {
  static const image = DecorationImage(
    image: AssetImage('assets/textures/grain.png'),
    repeat: ImageRepeat.repeat,
    opacity: 0.22,
    scale: 2,
  );

  /// A foreground decoration that lays the grain over a rounded object.
  static BoxDecoration decoration(BorderRadius radius) =>
      BoxDecoration(borderRadius: radius, image: image);
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + 4, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

// ── Envelope ─────────────────────────────────────────────────────────────────

/// A paper envelope closed with a Z wax seal (zend-site's `SealedEnvelope`),
/// drawn in ink. [progress] runs the sealing: 0 is open with the letter
/// above it, 1 is closed and sealed. A static [ZendEnvelope] with
/// `progress: 0` and no letter is the empty envelope.
class ZendEnvelope extends StatelessWidget {
  const ZendEnvelope({
    super.key,
    this.width = 150,
    this.progress = 1,
    this.letter = true,
  });

  final double width;
  final double progress;

  /// Draws the letter going in. Off for an empty envelope.
  final bool letter;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width, width * 0.86),
        painter: _EnvelopePainter(
          progress: progress,
          letter: letter,
          shadow: !zt.isDark,
        ),
      ),
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  _EnvelopePainter({
    required this.progress,
    required this.letter,
    required this.shadow,
  });

  final double progress;
  final bool letter, shadow;

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    // 150-wide box, the envelope body 114×70 at the bottom.
    final u = size.width / 150;
    final body = Rect.fromLTWH(18 * u, size.height - 76 * u, 114 * u, 70 * u);
    final r = Radius.circular(6 * u);
    final t = progress;

    // Phases: letter slides in, flap folds down, seal presses on.
    final slide = ZendMotion.ease.transform(_seg(t, 0, 0.45));
    final fold = ZendMotion.ease.transform(_seg(t, 0.4, 0.7));
    final press = ZendMotion.bounce.transform(_seg(t, 0.68, 1));

    if (shadow) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(body.shift(Offset(0, 10 * u)), r),
        Paint()
          ..color = const Color(0x260F0F0E)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * u),
      );
    }
    // Back of the envelope.
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, r),
      Paint()..color = const Color(0xFFE6DECB),
    );

    // The letter, sliding down into the pocket.
    if (letter && slide < 1) {
      final lw = 96 * u, lh = 64 * u;
      final top = body.top - lh * 0.9 + (lh * 0.9 + 6 * u) * slide;
      final paper = Rect.fromLTWH(body.center.dx - lw / 2, top, lw, lh);
      canvas
        ..save()
        ..clipRect(Rect.fromLTRB(0, 0, size.width, body.top + 30 * u));
      canvas.drawRRect(
        RRect.fromRectAndRadius(paper, Radius.circular(3 * u)),
        Paint()..color = const Color(0xFFFFFEFC),
      );
      final line = Paint()
        ..color = const Color(0x260F0F0E)
        ..strokeWidth = 2 * u
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final y = paper.top + (16 + i * 11) * u;
        canvas.drawLine(
          Offset(paper.left + 14 * u, y),
          Offset(paper.right - (i == 2 ? 40 : 14) * u, y),
          line,
        );
      }
      canvas.restore();
    }

    // Front pocket: the two lower flaps.
    final front = Path()
      ..moveTo(body.left, body.top + 6 * u)
      ..lineTo(body.center.dx, body.top + 40 * u)
      ..lineTo(body.right, body.top + 6 * u)
      ..lineTo(body.right, body.bottom - 6 * u)
      ..arcToPoint(Offset(body.right - 6 * u, body.bottom), radius: r)
      ..lineTo(body.left + 6 * u, body.bottom)
      ..arcToPoint(Offset(body.left, body.bottom - 6 * u), radius: r)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFFEFE8D6));
    canvas.drawPath(
      front,
      Paint()
        ..color = const Color(0xFFDDD4BF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * u,
    );

    // Top flap: points up while open, folds down over the pocket.
    final tipY = body.top - 38 * u + (38 * u + 40 * u) * fold;
    final flap = Path()
      ..moveTo(body.left, body.top + 6 * u)
      ..lineTo(body.center.dx, tipY)
      ..lineTo(body.right, body.top + 6 * u)
      ..close();
    canvas.drawPath(
      flap,
      Paint()
        ..color = Color.lerp(
          const Color(0xFFE6DECB),
          const Color(0xFFEAE2CF),
          fold,
        )!,
    );
    canvas.drawPath(
      flap,
      Paint()
        ..color = const Color(0xFFDDD4BF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * u,
    );

    // Wax seal with the Z, pressed onto the flap's tip.
    if (press > 0) {
      final c = Offset(body.center.dx, body.top + 38 * u);
      final sr = 16 * u * (0.4 + 0.6 * press);
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..scale(1.6 - 0.6 * press)
        ..translate(-c.dx, -c.dy);
      canvas.drawCircle(c, sr, Paint()..color = const Color(0xFF0F0F0E));
      canvas.drawCircle(
        c,
        sr * 0.72,
        Paint()
          ..color = const Color(0x59F7F6F3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 * u,
      );
      final g = sr * 1.05;
      canvas
        ..translate(c.dx - g / 2, c.dy - g / 2)
        ..drawPath(zendZGlyphPath(g), Paint()..color = const Color(0xFFF7F6F3))
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_EnvelopePainter old) =>
      old.progress != progress || old.letter != letter || old.shadow != shadow;
}

// ── Plane trail ──────────────────────────────────────────────────────────────

/// A paper plane at the end of a dashed loop (zend-site's final section),
/// at rest. For an empty Chats list: nothing sent yet.
class ZendPlaneTrail extends StatelessWidget {
  const ZendPlaneTrail({super.key, this.width = 150});

  final double width;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width, width * 0.66),
        painter: _PlaneTrailPainter(plane: zt.textPrimary, trail: zt.faint),
      ),
    );
  }
}

class _PlaneTrailPainter extends CustomPainter {
  _PlaneTrailPainter({required this.plane, required this.trail});
  final Color plane, trail;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 150;
    final path = Path()
      ..moveTo(6 * u, 84 * u)
      ..cubicTo(40 * u, 92 * u, 58 * u, 60 * u, 44 * u, 46 * u)
      ..cubicTo(30 * u, 32 * u, 14 * u, 52 * u, 34 * u, 62 * u)
      ..cubicTo(60 * u, 74 * u, 96 * u, 30 * u, 128 * u, 18 * u);
    final dash = Paint()
      ..color = trail
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2 * u;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length - 12 * u; d += 11 * u) {
        canvas.drawPath(m.extractPath(d, d + 4 * u), dash);
      }
      final end = m.getTangentForOffset(m.length)!;
      paintZendPaperPlane(
        canvas,
        at: end.position,
        angle: -end.angle,
        color: plane,
        scale: 1.1 * u,
      );
    }
  }

  @override
  bool shouldRepaint(_PlaneTrailPainter old) =>
      old.plane != plane || old.trail != trail;
}

// ── Postmark ─────────────────────────────────────────────────────────────────

/// A round postmark with wavy cancellation lines beside it: "FIRST ZEND"
/// over [when]. Marks the first time money moved between two people. Lands
/// like a rubber stamp when [animate] is on; at rest otherwise.
class ZendPostmark extends StatefulWidget {
  const ZendPostmark({super.key, required this.when, this.animate = false});

  /// Short date, e.g. "NOV 2026".
  final String when;
  final bool animate;

  @override
  State<ZendPostmark> createState() => _ZendPostmarkState();
}

class _ZendPostmarkState extends State<ZendPostmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate || ZendMotion.reduced(context)) {
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
    final zt = ZendTheme.of(context);
    final ink = zt.textSecondary;
    const d = 64.0;
    final mark = SizedBox(
      width: d + 64,
      height: d,
      child: Stack(
        children: [
          Positioned(
            left: d - 6,
            top: 0,
            bottom: 0,
            right: 0,
            child: CustomPaint(
              painter: _WavesPainter(ink.withValues(alpha: 0.6)),
            ),
          ),
          Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: zt.chatBg,
              border: Border.all(color: ink, width: 1.6),
            ),
            alignment: Alignment.center,
            child: Container(
              width: d - 10,
              height: d - 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: ink.withValues(alpha: 0.6),
                  width: 0.8,
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'FIRST',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 8,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: ink,
                    ),
                  ),
                  Text(
                    'ZEND',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: ink,
                    ),
                  ),
                  Text(
                    widget.when,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 7.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: 'First Zend, ${widget.when.toLowerCase()}',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = ZendMotion.bounce.transform(_c.value);
          return Opacity(
            opacity: _c.value.clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: (-8 + 2 * (1 - t)) * math.pi / 180,
              child: Transform.scale(scale: 1.5 - 0.5 * t, child: child),
            ),
          );
        },
        child: mark,
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  _WavesPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (0.2 + i * 0.2);
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 2) {
        path.lineTo(x, y + math.sin(x / 6) * 2.4);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavesPainter old) => old.color != color;
}

// ── The Z drawing itself on ──────────────────────────────────────────────────

/// The Z glyph tracing its outline, filling in, then the signal underline
/// drawing under it, over [duration]. For the first frame of the app. At
/// rest straight away under Reduce Motion. Calls [onDone] when finished.
class ZendZDrawOn extends StatefulWidget {
  const ZendZDrawOn({
    super.key,
    this.size = 96,
    this.duration = const Duration(milliseconds: 900),
    this.onDone,
  });

  final double size;
  final Duration duration;
  final VoidCallback? onDone;

  @override
  State<ZendZDrawOn> createState() => _ZendZDrawOnState();
}

class _ZendZDrawOnState extends State<ZendZDrawOn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.value > 0 || _c.isAnimating) return;
    if (ZendMotion.reduced(context)) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onDone?.call(),
      );
    } else {
      _c.forward().whenComplete(() => widget.onDone?.call());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(widget.size, widget.size * 1.2),
        painter: _ZDrawPainter(
          progress: _c,
          ink: zt.textPrimary,
          signal: zt.signal,
        ),
      ),
    );
  }
}

class _ZDrawPainter extends CustomPainter {
  _ZDrawPainter({
    required this.progress,
    required this.ink,
    required this.signal,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color ink, signal;

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final s = size.width;
    final glyph = zendZGlyphPath(s);
    final trace = ZendMotion.ease.transform(_seg(t, 0, 0.55));
    final fill = _seg(t, 0.35, 0.65);
    final under = ZendMotion.ease.transform(_seg(t, 0.55, 1));

    if (fill > 0) {
      canvas.drawPath(glyph, Paint()..color = ink.withValues(alpha: fill));
    }
    canvas.drawPath(
      _partial(glyph, trace),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeWidth = s * 0.04,
    );
    if (under > 0) {
      final sx = s * 0.8 / 300, y0 = s * 1.04;
      final swoosh = Path()
        ..moveTo(s * 0.1 + 4 * sx, y0 + 12 * sx)
        ..cubicTo(
          s * 0.1 + 70 * sx,
          y0 + 4 * sx,
          s * 0.1 + 190 * sx,
          y0,
          s * 0.1 + 296 * sx,
          y0 + 8 * sx,
        );
      canvas.drawPath(
        _partial(swoosh, under),
        Paint()
          ..color = signal
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s * 0.05,
      );
    }
  }

  @override
  bool shouldRepaint(_ZDrawPainter old) =>
      old.ink != ink || old.signal != signal || old.progress != progress;
}
