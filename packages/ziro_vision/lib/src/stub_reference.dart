/// Pure-Dart reference for the on-device math in `ziro_vision`.
///
/// The Kotlin (`android/.../StubEmbedder.kt`, `ImageMath.kt`) and Swift
/// (`ios/Classes/ImageMath.swift`) implementations follow this file step by
/// step so that the same palm crop gives the same vector on every platform.
/// It is not used at runtime; it exists for cross-checking and tests. The
/// expected values are listed in README.md ("Cross-platform check").
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Seed for the "palm-0" projection: ASCII "ZIRO".
const int palmStubSeed = 0x5A49524F;

/// Seed for the "face-0" projection: ASCII "FACE".
const int faceStubSeed = 0x46414345;

const int palmDims = 256;
const int faceDims = 512;

/// Side of the palm crop fed to the embedder.
const int roiSize = 224;

/// Side of the stub's downscaled input (224 / 7).
const int stubSide = 32;
const int stubInputLen = stubSide * stubSide; // 1024

/// SplitMix64 (Steele, Lea, Flood 2014). All arithmetic is mod 2^64.
///
/// Uses Dart VM 64-bit wrapping ints; not valid on the web.
class SplitMix64 {
  SplitMix64(int seed) : _state = seed;

  int _state;

  /// Next 64-bit output, as a (possibly negative) Dart int holding the bits.
  int next() {
    _state = _state + 0x9E3779B97F4A7C15;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  /// Uniform double in [0, 1): top 53 bits × 2^-53.
  double nextDouble() => (next() >>> 11) * (1.0 / 9007199254740992.0);
}

/// Standard normal deviates by Box-Muller, both outputs used in order:
/// u1 = 1 - nextDouble() (in (0, 1]), u2 = nextDouble(),
/// r = sqrt(-2 ln u1), first = r cos(2π u2), second = r sin(2π u2).
class GaussianStream {
  GaussianStream(int seed) : _rng = SplitMix64(seed);

  final SplitMix64 _rng;
  double? _spare;

  double next() {
    final spare = _spare;
    if (spare != null) {
      _spare = null;
      return spare;
    }
    final u1 = 1.0 - _rng.nextDouble();
    final u2 = _rng.nextDouble();
    final r = math.sqrt(-2.0 * math.log(u1));
    final theta = 2.0 * math.pi * u2;
    _spare = r * math.sin(theta);
    return r * math.cos(theta);
  }
}

/// Projection matrix, row-major `rows × 1024`, each entry a Gaussian deviate
/// rounded to float32. Entry (i, j) is deviate number `i * 1024 + j`.
Float32List projectionMatrix(int seed, int rows) {
  final g = GaussianStream(seed);
  final m = Float32List(rows * stubInputLen);
  for (var k = 0; k < m.length; k++) {
    m[k] = g.next();
  }
  return m;
}

// ---------------------------------------------------------------------------
// CLAHE on a 224×224 grayscale crop.
// ---------------------------------------------------------------------------

const int claheTiles = 8; // 8×8 grid
const int claheTileSize = roiSize ~/ claheTiles; // 28
const int claheTilePixels = claheTileSize * claheTileSize; // 784
/// floor(2.0 × 784 / 256).
const int claheClip = 6;

/// Contrast-limited adaptive histogram equalisation, exactly as specified in
/// README.md ("CLAHE").
Uint8List clahe(Uint8List gray) {
  assert(gray.length == roiSize * roiSize);
  final luts = List<Uint8List>.generate(
      claheTiles * claheTiles, (_) => Uint8List(256));
  final hist = Int32List(256);
  for (var ty = 0; ty < claheTiles; ty++) {
    for (var tx = 0; tx < claheTiles; tx++) {
      hist.fillRange(0, 256, 0);
      for (var y = ty * claheTileSize; y < (ty + 1) * claheTileSize; y++) {
        for (var x = tx * claheTileSize; x < (tx + 1) * claheTileSize; x++) {
          hist[gray[y * roiSize + x]]++;
        }
      }
      var excess = 0;
      for (var b = 0; b < 256; b++) {
        if (hist[b] > claheClip) {
          excess += hist[b] - claheClip;
          hist[b] = claheClip;
        }
      }
      final inc = excess ~/ 256;
      final rem = excess % 256;
      for (var b = 0; b < 256; b++) {
        hist[b] += inc + (b < rem ? 1 : 0);
      }
      final lut = luts[ty * claheTiles + tx];
      var cdf = 0;
      for (var b = 0; b < 256; b++) {
        cdf += hist[b];
        lut[b] = math.min(255, (cdf * 255) ~/ claheTilePixels);
      }
    }
  }
  final out = Uint8List(gray.length);
  for (var y = 0; y < roiSize; y++) {
    final fy = (y + 0.5) / claheTileSize - 0.5;
    final ty = _tileIndex(fy);
    for (var x = 0; x < roiSize; x++) {
      final fx = (x + 0.5) / claheTileSize - 0.5;
      final tx = _tileIndex(fx);
      final p = gray[y * roiSize + x];
      final l00 = luts[ty.i0 * claheTiles + tx.i0][p];
      final l01 = luts[ty.i0 * claheTiles + tx.i1][p];
      final l10 = luts[ty.i1 * claheTiles + tx.i0][p];
      final l11 = luts[ty.i1 * claheTiles + tx.i1][p];
      final v = (1 - ty.a) * ((1 - tx.a) * l00 + tx.a * l01) +
          ty.a * ((1 - tx.a) * l10 + tx.a * l11);
      out[y * roiSize + x] = (v + 0.5).floor().clamp(0, 255);
    }
  }
  return out;
}

({int i0, int i1, double a}) _tileIndex(double f) {
  final i = f.floor();
  if (i < 0) return (i0: 0, i1: 0, a: 0.0);
  if (i >= claheTiles - 1) {
    return (i0: claheTiles - 1, i1: claheTiles - 1, a: 0.0);
  }
  return (i0: i, i1: i + 1, a: f - i);
}

// ---------------------------------------------------------------------------
// Stub embedding.
// ---------------------------------------------------------------------------

/// 224×224 → 32×32 by 7×7 box mean (sum / 49).
Float64List downscale32(Uint8List gray) {
  final out = Float64List(stubInputLen);
  for (var r = 0; r < stubSide; r++) {
    for (var c = 0; c < stubSide; c++) {
      var s = 0;
      for (var dy = 0; dy < 7; dy++) {
        final row = (r * 7 + dy) * roiSize + c * 7;
        for (var dx = 0; dx < 7; dx++) {
          s += gray[row + dx];
        }
      }
      out[r * stubSide + c] = s / 49.0;
    }
  }
  return out;
}

/// Stub embedding of an already-CLAHE'd 224×224 crop:
/// downscale → mean/std normalise (population std; std < 1e-6 → 1) →
/// y = M·z with double accumulation in column order → L2 normalise → float32.
Float32List stubEmbed(Uint8List claheGray, Float32List matrix, int dims) {
  final x = downscale32(claheGray);
  var mean = 0.0;
  for (final v in x) {
    mean += v;
  }
  mean /= stubInputLen;
  var variance = 0.0;
  for (final v in x) {
    variance += (v - mean) * (v - mean);
  }
  variance /= stubInputLen;
  var std = math.sqrt(variance);
  if (std < 1e-6) std = 1.0;
  final z = Float64List(stubInputLen);
  for (var j = 0; j < stubInputLen; j++) {
    z[j] = (x[j] - mean) / std;
  }
  final y = Float64List(dims);
  var norm2 = 0.0;
  for (var i = 0; i < dims; i++) {
    var acc = 0.0;
    final base = i * stubInputLen;
    for (var j = 0; j < stubInputLen; j++) {
      acc += matrix[base + j] * z[j];
    }
    y[i] = acc;
    norm2 += acc * acc;
  }
  final out = Float32List(dims);
  if (norm2 == 0) return out;
  final n = math.sqrt(norm2);
  for (var i = 0; i < dims; i++) {
    out[i] = y[i] / n;
  }
  return out;
}

/// Full "palm-0" path from the raw (pre-CLAHE) 224×224 crop.
Float32List palmStubEmbedding(Uint8List roiGray, Float32List palmMatrix) =>
    stubEmbed(clahe(roiGray), palmMatrix, palmDims);

/// Mean of several embeddings (double accumulation), then L2 normalise.
Float32List averageEmbeddings(List<Float32List> vectors) {
  final dims = vectors.first.length;
  final acc = Float64List(dims);
  for (final v in vectors) {
    for (var i = 0; i < dims; i++) {
      acc[i] += v[i];
    }
  }
  var n2 = 0.0;
  for (final a in acc) {
    n2 += a * a;
  }
  final out = Float32List(dims);
  if (n2 == 0) return out;
  final n = math.sqrt(n2);
  for (var i = 0; i < dims; i++) {
    out[i] = acc[i] / n;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Hand geometry (24 values) and palm quad.
// ---------------------------------------------------------------------------

/// Landmark index pairs, in output order. Each value is the 2-D pixel distance
/// between the pair divided by the palm width |P5 − P17|.
const List<(int, int)> geometryPairs = [
  // finger segments (15)
  (1, 2), (2, 3), (3, 4), // thumb
  (5, 6), (6, 7), (7, 8), // index
  (9, 10), (10, 11), (11, 12), // middle
  (13, 14), (14, 15), (15, 16), // ring
  (17, 18), (18, 19), (19, 20), // pinky
  // palm lengths (5)
  (0, 1), (0, 5), (0, 9), (0, 13), (0, 17),
  // width proxies (4)
  (5, 9), (9, 13), (13, 17), (2, 5),
];

/// [points] are 21 (x, y) pixel coordinates in the upright, mirrored frame.
Float64List handGeometry(List<(double, double)> points) {
  double d(int a, int b) {
    final dx = points[a].$1 - points[b].$1;
    final dy = points[a].$2 - points[b].$2;
    return math.sqrt(dx * dx + dy * dy);
  }

  final w = d(5, 17);
  final out = Float64List(geometryPairs.length);
  if (w <= 0) return out;
  for (var i = 0; i < geometryPairs.length; i++) {
    out[i] = d(geometryPairs[i].$1, geometryPairs[i].$2) / w;
  }
  return out;
}

/// Source quad for the palm crop, in order TL, TR, BR, BL (pixels):
/// TL = P5, TR = P17, BR = P0 + 0.8 (P17 − P9), BL = P0 + 0.8 (P5 − P9).
List<(double, double)> palmQuad(List<(double, double)> p) {
  (double, double) at(int i) => p[i];
  final p0 = at(0), p5 = at(5), p9 = at(9), p17 = at(17);
  return [
    p5,
    p17,
    (p0.$1 + 0.8 * (p17.$1 - p9.$1), p0.$2 + 0.8 * (p17.$2 - p9.$2)),
    (p0.$1 + 0.8 * (p5.$1 - p9.$1), p0.$2 + 0.8 * (p5.$2 - p9.$2)),
  ];
}

/// Homography mapping destination pixel (u, v) to source (x, y), from the
/// destination square of side [size] (corners (0,0), (size-1,0),
/// (size-1,size-1), (0,size-1)) to [quad] (TL, TR, BR, BL).
/// Returns h0..h7 (h8 = 1), or null when the system is singular.
Float64List? homographyToQuad(List<(double, double)> quad, int size) {
  final s = (size - 1).toDouble();
  final dst = [(0.0, 0.0), (s, 0.0), (s, s), (0.0, s)];
  final a = List.generate(8, (_) => Float64List(9));
  for (var k = 0; k < 4; k++) {
    final u = dst[k].$1, v = dst[k].$2;
    final x = quad[k].$1, y = quad[k].$2;
    a[2 * k].setAll(0, [u, v, 1, 0, 0, 0, -u * x, -v * x, x]);
    a[2 * k + 1].setAll(0, [0, 0, 0, u, v, 1, -u * y, -v * y, y]);
  }
  for (var col = 0; col < 8; col++) {
    var piv = col;
    for (var r = col + 1; r < 8; r++) {
      if (a[r][col].abs() > a[piv][col].abs()) piv = r;
    }
    if (a[piv][col].abs() < 1e-12) return null;
    final tmp = a[col];
    a[col] = a[piv];
    a[piv] = tmp;
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final f = a[r][col] / a[col][col];
      if (f == 0) continue;
      for (var c = col; c < 9; c++) {
        a[r][c] -= f * a[col][c];
      }
    }
  }
  final h = Float64List(8);
  for (var i = 0; i < 8; i++) {
    h[i] = a[i][8] / a[i][i];
  }
  return h;
}

/// Bilinear sample of an 8-bit single-channel image with edge clamping,
/// rounded with floor(v + 0.5).
int sampleBilinear(Uint8List img, int w, int h, double x, double y) {
  final x0f = x.floor(), y0f = y.floor();
  final fx = x - x0f, fy = y - y0f;
  int px(int xx, int yy) =>
      img[yy.clamp(0, h - 1) * w + xx.clamp(0, w - 1)];
  final v = (1 - fy) * ((1 - fx) * px(x0f, y0f) + fx * px(x0f + 1, y0f)) +
      fy * ((1 - fx) * px(x0f, y0f + 1) + fx * px(x0f + 1, y0f + 1));
  return (v + 0.5).floor().clamp(0, 255);
}

/// Warps a grayscale image through [quad] into a [size]×[size] crop.
Uint8List? warpGray(Uint8List img, int w, int h,
    List<(double, double)> quad, int size) {
  final hm = homographyToQuad(quad, size);
  if (hm == null) return null;
  final out = Uint8List(size * size);
  for (var v = 0; v < size; v++) {
    for (var u = 0; u < size; u++) {
      final den = hm[6] * u + hm[7] * v + 1.0;
      final x = (hm[0] * u + hm[1] * v + hm[2]) / den;
      final y = (hm[3] * u + hm[4] * v + hm[5]) / den;
      out[v * size + u] = sampleBilinear(img, w, h, x, y);
    }
  }
  return out;
}

/// Integer BT.601 luma used on both platforms: (77 R + 150 G + 29 B) >> 8.
int luma(int r, int g, int b) => (77 * r + 150 * g + 29 * b) >> 8;

/// The fixed test crop used by the cross-platform check:
/// pixel (x, y) = (3x + 5y) & 0xFF.
Uint8List referenceTestCrop() {
  final g = Uint8List(roiSize * roiSize);
  for (var y = 0; y < roiSize; y++) {
    for (var x = 0; x < roiSize; x++) {
      g[y * roiSize + x] = (3 * x + 5 * y) & 0xFF;
    }
  }
  return g;
}
