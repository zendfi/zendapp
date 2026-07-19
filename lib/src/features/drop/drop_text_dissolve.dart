import 'dart:math';

import 'package:flutter/material.dart';

import 'drop_dissolve_painter.dart';
import 'drop_text_sampler.dart';

export 'drop_dissolve_painter.dart' show DissolveDirection;

/// A self-contained widget that renders a text-dissolve / text-reform
/// particle effect.
///
/// Usage:
/// ```dart
/// DropTextDissolve(
///   text: '\$20',
///   style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 88, ...),
///   direction: DissolveDirection.dissolve,   // sender: text → particles
///   controller: _animCtrl,
///   focalXFraction: 0.5,
///   focalYFraction: 0.18,
/// )
/// ```
///
/// The widget sizes itself to [width] × [height] and renders:
/// 1. A static crisp text layer (either fading out for dissolve or fading in
///    for reform).
/// 2. A depth-bucketed particle layer drawn by [DropDissolvePainter].
///
/// Text sampling is performed once in [initState] and reused every frame.
class DropTextDissolve extends StatefulWidget {
  const DropTextDissolve({
    super.key,
    required this.text,
    required this.style,
    required this.direction,
    required this.controller,
    required this.focalXFraction,
    required this.focalYFraction,
    this.width = double.infinity,
    this.height = 120,
    this.textYFraction = 0.5,
    this.samplingDensity = 0.28,
    this.maxParticles = 2000,
    this.pixelRatio = 2.5,
    this.particleColor = Colors.white,
  });

  final String text;
  final TextStyle style;
  final DissolveDirection direction;
  final AnimationController controller;

  /// Fraction 0→1 of this widget's width where particles converge/emerge.
  final double focalXFraction;

  /// Fraction 0→1 of the *canvas* height where particles converge/emerge.
  /// Typically maps to the avatar's Y position in the parent screen.
  final double focalYFraction;

  final double width;
  final double height;
  /// Fraction 0→1 of the canvas height where the text centre is drawn.
  /// Default 0.54. Override when the widget canvas is taller than the text zone.
  final double textYFraction;
  final double samplingDensity;
  final int maxParticles;
  final double pixelRatio;
  final Color particleColor;

  @override
  State<DropTextDissolve> createState() => _DropTextDissolveState();
}

class _DropTextDissolveState extends State<DropTextDissolve> {
  TextSampleResult? _result;
  List<ParticleState>? _states;
  bool _sampling = false;

  @override
  void initState() {
    super.initState();
    // Defer sampling to post-frame — avoids racing with AnimatedSwitcher's
    // transition compositing, which can cause picture.toImage() to return a
    // 0×0 image and produce zero particles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sample();
    });
  }

  @override
  void didUpdateWidget(DropTextDissolve old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      _sample();
    }
  }

  Future<void> _sample() async {
    if (_sampling) return;
    _sampling = true;
    final result = await sampleTextParticles(
      widget.text,
      style: widget.style,
      pixelRatio: widget.pixelRatio,
      samplingDensity: widget.samplingDensity,
      maxParticles: widget.maxParticles,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _states = buildParticleStates(result, Random(99));
      _sampling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final states = _states;

    // Before sampling completes — show static text only (no flash).
    if (result == null || states == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Center(
          child: Text(
            widget.text,
            style: widget.style,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, child) {
          final t = widget.controller.value; // 0→1

          // Text opacity: dissolve fades OUT over 0–100%, reform fades IN.
          final textOpacity = widget.direction == DissolveDirection.dissolve
              ? (1.0 - t * 1.2).clamp(0.0, 1.0)
              : (t * 1.3 - 0.3).clamp(0.0, 1.0);

          return Stack(
            alignment: Alignment.center,
            children: [
              // Particle layer — fills the widget bounds.
              Positioned.fill(
                child: CustomPaint(
                  painter: DropDissolvePainter(
                    animation: widget.controller,
                    direction: widget.direction,
                    states: states,
                    result: result,
                    focalXFraction: widget.focalXFraction,
                    focalYFraction: widget.focalYFraction,
                    textYFraction: widget.textYFraction,
                    particleColor: widget.particleColor,
                  ),
                ),
              ),
              // Text layer — centred in the widget, fades with animation.
              Opacity(
                opacity: textOpacity,
                child: Text(
                  widget.text,
                  style: widget.style,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
