import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Depth tier assigned at sample time based on glyph edge topology.
enum DepthTier {
  /// Core of thick strokes — stays close, large, bright.
  near,
  /// Mid-weight strokes — standard rendering.
  mid,
  /// Thin strokes and edge pixels — recede, smaller, dimmer.
  far,
  /// Ambient halo: sparse, very blurred, creates luminous atmosphere.
  halo,
}

/// A sampled particle spawn/target position with depth metadata.
class SampledParticle {
  const SampledParticle({
    required this.position,   // logical pixel coordinate in the text bounding box
    required this.tier,
    required this.edgeNormal, // unit vector pointing away from glyph interior
  });

  /// Normalised position (0→1) within the text bounding rect, in logical coords.
  final Offset position;
  final DepthTier tier;
  /// Direction particles peel off / arrive from. For edge pixels this points
  /// outward from the letterform; for core pixels it's random.
  final Offset edgeNormal;
}

/// Result of a completed sampling pass.
class TextSampleResult {
  const TextSampleResult({
    required this.near,
    required this.mid,
    required this.far,
    required this.halo,
    required this.textSize,
  });

  final List<SampledParticle> near;
  final List<SampledParticle> mid;
  final List<SampledParticle> far;
  final List<SampledParticle> halo;
  final Size textSize;

  bool get isEmpty => near.isEmpty && mid.isEmpty && far.isEmpty && halo.isEmpty;
  int get totalCount => near.length + mid.length + far.length + halo.length;
}

/// Renders [text] with [style] off-screen at [pixelRatio] * logical size,
/// reads the pixel data, and returns depth-bucketed [SampledParticle] lists.
///
/// Call once during [State.initState]; the result is reused every frame.
Future<TextSampleResult> sampleTextParticles(
  String text, {
  required TextStyle style,
  /// Oversample ratio — 2.5 gives crisp glyph-edge dust without blocky pixels.
  double pixelRatio = 2.5,
  /// Fraction of sampled pixels to keep (0→1). 0.25 → ~1,500 particles for "$20".
  double samplingDensity = 0.25,
  /// Target max total particle count (stratified subsample if exceeded).
  int maxParticles = 2200,
}) async {
  // ── 1. Measure the text at logical size ──────────────────────────────────
  // TextAlign.left avoids the TextAlign.center + ParagraphConstraints(∞) bug:
  // centering with an infinite constraint positions glyphs at (∞ - lineW) / 2
  // which produces off-canvas or NaN X offsets when painting, resulting in
  // an all-transparent bitmap and zero sampled particles.
  // Alignment is irrelevant for single-line text — we only need maxIntrinsicWidth.
  final pb = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontFamily: style.fontFamily,
      fontSize: style.fontSize,
      fontStyle: style.fontStyle,
      fontWeight: style.fontWeight,
      height: style.height,
    ),
  )..pushStyle(
      ui.TextStyle(
        color: const Color(0xFFFFFFFF),
        fontFamily: style.fontFamily,
        fontSize: style.fontSize,
        fontStyle: style.fontStyle,
        fontWeight: style.fontWeight,
        height: style.height,
      ),
    )..addText(text);

  final para = pb.build();
  // Layout at maxIntrinsicWidth so glyphs are fully within the bitmap bounds.
  para.layout(const ui.ParagraphConstraints(width: double.infinity));
  final textW = para.maxIntrinsicWidth.ceil();
  final textH = para.height.ceil();
  if (textW <= 0 || textH <= 0) {
    return TextSampleResult(
      near: [], mid: [], far: [], halo: [],
      textSize: Size(textW.toDouble(), textH.toDouble()),
    );
  }

  // ── 2. Render at high resolution ─────────────────────────────────────────
  // Re-layout at the exact measured width so glyph positions are finite and
  // within the bitmap bounds when we call canvas.drawParagraph.
  para.layout(ui.ParagraphConstraints(width: textW.toDouble()));

  final imgW = (textW * pixelRatio).ceil();
  final imgH = (textH * pixelRatio).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio, pixelRatio);
  canvas.drawParagraph(para, Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(imgW, imgH);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  para.dispose();

  if (byteData == null) {
    return TextSampleResult(near: [], mid: [], far: [], halo: [], textSize: Size(textW.toDouble(), textH.toDouble()));
  }

  final pixels = byteData.buffer.asUint8List();

  // ── 3. Build opacity map ─────────────────────────────────────────────────
  // opacityMap[y * imgW + x] = alpha channel (0–255)
  final opacityMap = Uint8List(imgW * imgH);
  for (var i = 0; i < imgW * imgH; i++) {
    opacityMap[i] = pixels[i * 4 + 3]; // RGBA alpha
  }

  // ── 4. Sample non-transparent pixels ────────────────────────────────────
  final rng = Random(42);
  final near = <SampledParticle>[];
  final mid = <SampledParticle>[];
  final far = <SampledParticle>[];
  final halo = <SampledParticle>[];

  // Stride sampling with jitter to avoid a grid pattern.
  const strideBase = 4;

  for (var y = 1; y < imgH - 1; y++) {
    for (var x = 1; x < imgW - 1; x++) {
      // Stride skip with small random jitter.
      if ((x + y * 7) % strideBase != 0) continue;
      if (rng.nextDouble() > samplingDensity * 1.6) continue;

      final alpha = opacityMap[y * imgW + x];
      if (alpha < 30) continue; // skip nearly transparent pixels

      // Normalised position in logical pixel space (0→1).
      final nx = x / imgW;
      final ny = y / imgH;

      // ── 5. Edge-normal from 3×3 neighbourhood ─────────────────────────
      // Gradient of opacity field → outward normal of glyph edge.
      final left = opacityMap[y * imgW + (x - 1)].toDouble();
      final right = opacityMap[y * imgW + (x + 1)].toDouble();
      final up = opacityMap[(y - 1) * imgW + x].toDouble();
      final down = opacityMap[(y + 1) * imgW + x].toDouble();

      // Gradient points toward higher opacity (into the glyph).
      // Negate to get outward normal.
      var gnx = -(right - left);
      var gny = -(down - up);
      final gLen = sqrt(gnx * gnx + gny * gny);
      if (gLen > 0.5) {
        gnx /= gLen;
        gny /= gLen;
      } else {
        // Core pixel — random normal.
        final angle = rng.nextDouble() * 2 * pi;
        gnx = cos(angle);
        gny = sin(angle);
      }
      final normal = Offset(gnx, gny);

      // ── 6. Depth bucketing ───────────────────────────────────────────
      // Count opaque neighbours in 3×3 window to determine "thickness".
      var opaqueNeighbours = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx2 = (x + dx).clamp(0, imgW - 1);
          final ny2 = (y + dy).clamp(0, imgH - 1);
          if (opacityMap[ny2 * imgW + nx2] > 80) opaqueNeighbours++;
        }
      }

      final DepthTier tier;
      if (opaqueNeighbours >= 7) {
        tier = DepthTier.near;   // completely surrounded — thick stroke core
      } else if (opaqueNeighbours >= 4) {
        tier = DepthTier.mid;
      } else {
        tier = DepthTier.far;    // edge pixel, isolated, thin stroke
      }

      final particle = SampledParticle(
        position: Offset(nx, ny),
        tier: tier,
        edgeNormal: normal,
      );

      switch (tier) {
        case DepthTier.near: near.add(particle);
        case DepthTier.mid: mid.add(particle);
        case DepthTier.far: far.add(particle);
        case DepthTier.halo: halo.add(particle);
      }
    }
  }

  // ── 7. Subsample to maxParticles ─────────────────────────────────────────
  // Proportional subsample preserving tier ratios.
  final total = near.length + mid.length + far.length;

  if (total > maxParticles) {
    final ratio = maxParticles / total;
    near.retainWhere((_) => rng.nextDouble() < ratio);
    mid.retainWhere((_) => rng.nextDouble() < ratio);
    far.retainWhere((_) => rng.nextDouble() < ratio);
  }

  // Halo: ~4% of total, sampled from near tier positions.
  final haloCount = ((near.length + mid.length + far.length) * 0.04).floor();
  final haloSource = [...near, ...mid]..shuffle(rng);
  halo.addAll(haloSource.take(haloCount).map((p) => SampledParticle(
    position: p.position,
    tier: DepthTier.halo,
    edgeNormal: p.edgeNormal,
  )));

  return TextSampleResult(
    near: near,
    mid: mid,
    far: far,
    halo: halo,
    textSize: Size(textW.toDouble(), textH.toDouble()),
  );
}
