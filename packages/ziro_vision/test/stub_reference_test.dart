import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ziro_vision/src/stub_reference.dart';
import 'package:ziro_vision/ziro_vision.dart';

// The same values are listed in README.md ("Cross-platform check"); the Kotlin
// and Swift implementations must reproduce them.

void main() {
  group('SplitMix64', () {
    test('matches the published test vector (seed 1234567)', () {
      final r = SplitMix64(1234567);
      final outs = [
        for (var i = 0; i < 5; i++) BigInt.from(r.next()).toUnsigned(64),
      ];
      expect(outs, [
        BigInt.parse('6457827717110365317'),
        BigInt.parse('3203168211198807973'),
        BigInt.parse('9817491932198370423'),
        BigInt.parse('4593380528125082431'),
        BigInt.parse('16408922859458223821'),
      ]);
    });

    test('nextDouble is in [0, 1)', () {
      final r = SplitMix64(palmStubSeed);
      for (var i = 0; i < 10000; i++) {
        final d = r.nextDouble();
        expect(d >= 0 && d < 1, isTrue);
      }
    });
  });

  group('projection matrices', () {
    test('palm and face first entries', () {
      final g = GaussianStream(palmStubSeed);
      expect(g.next(), closeTo(0.126832242, 1e-8));
      expect(g.next(), closeTo(-0.264155442, 1e-8));
      expect(g.next(), closeTo(0.891876391, 1e-8));
      expect(g.next(), closeTo(-1.246378626, 1e-8));

      final pm = projectionMatrix(palmStubSeed, palmDims);
      expect(pm.length, 256 * 1024);
      expect(pm[0], closeTo(0.126832247, 1e-8)); // float32-rounded
      expect(pm.last, closeTo(-1.026000023, 1e-8));

      final fm = projectionMatrix(faceStubSeed, faceDims);
      expect(fm.length, 512 * 1024);
      expect(fm[0], closeTo(-0.755913019, 1e-8));
      expect(fm[1], closeTo(-0.751971781, 1e-8));
      expect(fm[2], closeTo(-0.548602998, 1e-8));
      expect(fm[3], closeTo(1.462694287, 1e-8));
    });
  });

  group('crop pipeline on the reference crop', () {
    final crop = referenceTestCrop();
    final c = clahe(crop);

    test('CLAHE values', () {
      expect(c[0], 0);
      expect(c[1], 0);
      expect(c[223], 97);
      expect(c[224 * 100 + 50], 154);
      expect(c[224 * 223 + 223], 255);
    });

    test('downscale', () {
      final ds = downscale32(c);
      expect(ds[0], closeTo(9.775510204, 1e-9));
      expect(ds[1], closeTo(27.489795918, 1e-9));
      expect(ds[1023], closeTo(244.918367347, 1e-9));
    });

    test('palm-0 first values', () {
      final pm = projectionMatrix(palmStubSeed, palmDims);
      final e = palmStubEmbedding(crop, pm);
      const expected = [
        -0.029277, 0.065192, -0.002518, 0.018660,
        -0.066626, -0.008154, 0.010376, 0.049409,
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(e[i], closeTo(expected[i], 1e-5), reason: 'index $i');
      }
      var n = 0.0;
      for (final v in e) {
        n += v * v;
      }
      expect(n, closeTo(1.0, 1e-5));
    });

    test('face-0 first values', () {
      final fm = projectionMatrix(faceStubSeed, faceDims);
      final e = stubEmbed(c, fm, faceDims);
      const expected = [
        0.039946, -0.020275, -0.021324, 0.045991,
        -0.010333, -0.082075, 0.096338, 0.052026,
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(e[i], closeTo(expected[i], 1e-5), reason: 'index $i');
      }
    });

    test('brightness shift barely changes the palm-0 vector', () {
      final pm = projectionMatrix(palmStubSeed, palmDims);
      final brighter = Uint8List.fromList([
        for (final v in crop) (v + 12).clamp(0, 255),
      ]);
      final a = palmStubEmbedding(crop, pm);
      final b = palmStubEmbedding(brighter, pm);
      expect(cosineSimilarity(a, b), greaterThan(0.9));
    });

    test('average of identical vectors is the vector', () {
      final pm = projectionMatrix(palmStubSeed, palmDims);
      final e = palmStubEmbedding(crop, pm);
      final avg = averageEmbeddings([e, e, e]);
      for (var i = 0; i < e.length; i++) {
        expect(avg[i], closeTo(e[i], 1e-6));
      }
    });
  });

  group('geometry and warp', () {
    test('24 geometry pairs', () {
      expect(geometryPairs.length, 24);
    });

    test('geometry is scale invariant and normalised by palm width', () {
      final pts = [
        for (var i = 0; i < 21; i++) ((i * 7.0) % 50, (i * 11.0) % 80),
      ];
      final g1 = handGeometry(pts);
      final g2 = handGeometry([for (final p in pts) (p.$1 * 3, p.$2 * 3)]);
      for (var i = 0; i < 24; i++) {
        expect(g1[i], closeTo(g2[i], 1e-9));
      }
    });

    test('homography maps the destination corners onto the quad', () {
      final quad = [(10.0, 20.0), (200.0, 15.0), (220.0, 240.0), (5.0, 230.0)];
      final h = homographyToQuad(quad, roiSize)!;
      const s = roiSize - 1.0;
      final corners = [(0.0, 0.0), (s, 0.0), (s, s), (0.0, s)];
      for (var k = 0; k < 4; k++) {
        final u = corners[k].$1, v = corners[k].$2;
        final den = h[6] * u + h[7] * v + 1;
        expect((h[0] * u + h[1] * v + h[2]) / den, closeTo(quad[k].$1, 1e-6));
        expect((h[3] * u + h[4] * v + h[5]) / den, closeTo(quad[k].$2, 1e-6));
      }
    });

    test('identity warp reproduces the image', () {
      final img = referenceTestCrop();
      const s = roiSize - 1.0;
      final out = warpGray(img, roiSize, roiSize,
          [(0.0, 0.0), (s, 0.0), (s, s), (0.0, s)], roiSize)!;
      expect(out, img);
    });

    test('degenerate quad returns null', () {
      expect(
          homographyToQuad(
              [(1.0, 1.0), (1.0, 1.0), (1.0, 1.0), (1.0, 1.0)], roiSize),
          isNull);
    });
  });
}
