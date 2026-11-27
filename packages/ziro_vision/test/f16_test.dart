import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziro_vision/ziro_vision.dart';

void main() {
  test('known half-float bit patterns', () {
    expect(F16.toBits(0.0), 0x0000);
    expect(F16.toBits(-0.0), 0x8000);
    expect(F16.toBits(1.0), 0x3C00);
    expect(F16.toBits(-2.0), 0xC000);
    expect(F16.toBits(0.5), 0x3800);
    expect(F16.toBits(65504.0), 0x7BFF);
    expect(F16.toBits(65520.0), 0x7C00); // rounds to infinity
    expect(F16.toBits(double.infinity), 0x7C00);
    expect(F16.toBits(double.nan) & 0x7C00, 0x7C00);
    expect(F16.toBits(5.960464477539063e-8), 0x0001); // smallest subnormal
    expect(F16.toBits(6.103515625e-5), 0x0400); // smallest normal
    expect(F16.toBits(0.333333333), 0x3555);
  });

  test('round to nearest even at the tie', () {
    // 1 + 2^-11 is exactly between 1.0 (0x3C00) and 1+2^-10 (0x3C01).
    expect(F16.toBits(1.0 + 1 / 2048), 0x3C00);
    // 1 + 3·2^-11 is between 0x3C01 and 0x3C02; ties to even → 0x3C02.
    expect(F16.toBits(1.0 + 3 / 2048), 0x3C02);
  });

  test('fromBits inverts toBits on all finite halves', () {
    for (var h = 0; h < 0x10000; h++) {
      final exp = (h >> 10) & 0x1F;
      if (exp == 0x1F) continue;
      expect(F16.toBits(F16.fromBits(h)), h, reason: 'h=$h');
    }
  });

  test('little-endian byte layout and base64', () {
    final bytes = F16.encodeBytes([1.0, -2.0]);
    expect(bytes, [0x00, 0x3C, 0x00, 0xC0]);
    expect(F16.encodeBase64([1.0, -2.0]), base64.encode(bytes));
    expect(F16.decodeBase64(F16.encodeBase64([1.0, -2.0])), [1.0, -2.0]);
  });

  test('decode checks length', () {
    final b64 = F16.encodeBase64(List.filled(24, 0.25));
    expect(F16.decodeBase64(b64, expectedLength: 24).length, 24);
    expect(() => F16.decodeBase64(b64, expectedLength: 256),
        throwsFormatException);
    expect(() => F16.decodeBytes(Uint8List(3)), throwsFormatException);
  });

  test('a normalised 256-D vector survives f16 with cosine > 0.9999', () {
    final v = l2Normalize([for (var i = 0; i < 256; i++) (i * 37 % 101) - 50.0]);
    final back = F16.decodeBase64(F16.encodeBase64(v), expectedLength: 256);
    expect(F16.encodeBytes(v).length, 512);
    expect(cosineSimilarity(v, back), greaterThan(0.9999));
  });
}
