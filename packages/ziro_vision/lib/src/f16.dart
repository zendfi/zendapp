import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// IEEE-754 half-float helpers matching contracts.md §0: little-endian f16,
/// concatenated, standard base64 with padding.
///
/// The float → half conversion rounds to nearest, ties to even. The Kotlin
/// (`F16.kt`) and Swift (`ImageMath.swift`) encoders use the same algorithm.
abstract final class F16 {
  /// Converts [value] to half-float bits (0..0xFFFF).
  static int toBits(double value) {
    final bd = ByteData(4)..setFloat32(0, value, Endian.little);
    final x = bd.getUint32(0, Endian.little);
    final sign = (x >>> 16) & 0x8000;
    final exp = (x >>> 23) & 0xFF;
    var mant = x & 0x7FFFFF;
    if (exp == 0xFF) {
      return sign | 0x7C00 | (mant != 0 ? 0x200 : 0);
    }
    final e = exp - 127 + 15;
    if (e >= 0x1F) return sign | 0x7C00;
    if (e <= 0) {
      if (e < -10) return sign;
      mant |= 0x800000;
      final shift = 14 - e;
      var h = mant >>> shift;
      final rem = mant & ((1 << shift) - 1);
      final half = 1 << (shift - 1);
      if (rem > half || (rem == half && (h & 1) != 0)) h += 1;
      return sign | h;
    }
    var h = (e << 10) | (mant >>> 13);
    final rem = mant & 0x1FFF;
    if (rem > 0x1000 || (rem == 0x1000 && (h & 1) != 0)) h += 1;
    return sign | h;
  }

  /// Converts half-float bits to a double.
  static double fromBits(int h) {
    final sign = (h & 0x8000) != 0 ? -1.0 : 1.0;
    final exp = (h >>> 10) & 0x1F;
    final mant = h & 0x3FF;
    if (exp == 0) {
      return sign * mant * math.pow(2, -24).toDouble();
    }
    if (exp == 0x1F) {
      return mant == 0 ? sign * double.infinity : double.nan;
    }
    return sign * (1 + mant / 1024.0) * math.pow(2, exp - 15).toDouble();
  }

  /// Little-endian f16 bytes for [values].
  static Uint8List encodeBytes(List<double> values) {
    final out = ByteData(values.length * 2);
    for (var i = 0; i < values.length; i++) {
      out.setUint16(i * 2, toBits(values[i]), Endian.little);
    }
    return out.buffer.asUint8List();
  }

  /// Decodes little-endian f16 bytes.
  static Float32List decodeBytes(Uint8List bytes) {
    if (bytes.length.isOdd) {
      throw const FormatException('f16 byte length must be even');
    }
    final bd = ByteData.sublistView(bytes);
    final out = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = fromBits(bd.getUint16(i * 2, Endian.little));
    }
    return out;
  }

  /// Base64 (standard, padded) of the f16 encoding.
  static String encodeBase64(List<double> values) =>
      base64.encode(encodeBytes(values));

  /// Decodes a base64 f16 vector. When [expectedLength] is given, the vector
  /// must have exactly that many values.
  static Float32List decodeBase64(String b64, {int? expectedLength}) {
    final v = decodeBytes(base64.decode(b64));
    if (expectedLength != null && v.length != expectedLength) {
      throw FormatException(
          'expected $expectedLength f16 values, got ${v.length}');
    }
    return v;
  }
}

/// L2-normalises [v]. A zero vector is returned unchanged.
Float32List l2Normalize(List<double> v) {
  var s = 0.0;
  for (final x in v) {
    s += x * x;
  }
  final out = Float32List(v.length);
  if (s == 0) return out;
  final n = math.sqrt(s);
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] / n;
  }
  return out;
}

/// Cosine similarity of two equal-length vectors.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError('length mismatch: ${a.length} vs ${b.length}');
  }
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}
