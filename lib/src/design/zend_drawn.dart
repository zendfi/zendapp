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
/// (zend-site's `NameSticker`). For the @tag sheet.
class ZendNameSticker extends StatelessWidget {
  const ZendNameSticker({super.key, required this.handle, this.width = 184});

  /// Shown as written, e.g. "@tolu".
  final String handle;
  final double width;

  static const _paper = Color(0xFFFFFEFC);
  static const _ink = Color(0xFF0F0F0E);
  static const _onInk = Color(0xFFF7F6F3);

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final h = width * 80 / 122;
    return Semantics(
      label: 'Name sticker: $handle',
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        handle,
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
