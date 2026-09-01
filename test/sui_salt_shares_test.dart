import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zendapp/src/services/sui_salt_shares.dart';

/// Deterministic coefficient source so a split can be asserted against a
/// hand-computed answer. Never acceptable in production.
class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final int value;

  @override
  int nextInt(int max) => value % max;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

Uint8List _filled(int byte) =>
    Uint8List.fromList(List<int>.filled(kSaltBytes, byte));

void main() {
  group('GF(256) field arithmetic', () {
    // Published AES GF(2^8) vectors. These validate the field independently of
    // the sharing scheme built on top of it — if these pass, the reduction
    // polynomial and log tables are right.
    test('matches the published AES multiplication vectors', () {
      expect(Gf256.mul(0x57, 0x83), 0xc1);
      expect(Gf256.mul(0x57, 0x13), 0xfe);
    });

    test('zero is absorbing and one is the identity', () {
      for (final v in [0x00, 0x01, 0x53, 0xff]) {
        expect(Gf256.mul(v, 0), 0);
        expect(Gf256.mul(0, v), 0);
        expect(Gf256.mul(v, 1), v);
        expect(Gf256.mul(1, v), v);
      }
    });

    test('division inverts multiplication for every non-zero pair', () {
      for (var a = 1; a < 256; a++) {
        for (var b = 1; b < 256; b += 17) {
          expect(Gf256.div(Gf256.mul(a, b), b), a, reason: 'a=$a b=$b');
        }
      }
    });

    test('division by zero is refused rather than returning a wrong answer', () {
      expect(() => Gf256.div(0x42, 0), throwsArgumentError);
    });
  });

  group('split', () {
    test('produces exactly three shares at indices 1, 2, 3', () {
      final shares = SaltSharing.split(_filled(0xab));
      expect(shares.length, 3);
      expect(shares.map((s) => s.x).toList(), [1, 2, 3]);
      for (final share in shares) {
        expect(share.y.length, kSaltBytes);
      }
    });

    test('matches a hand-computed line over GF(256)', () {
      // secret byte 0x01, coefficient 0x02, so f(x) = 0x01 ^ (0x02 · x):
      //   f(1) = 0x01 ^ 0x02 = 0x03
      //   f(2) = 0x01 ^ 0x04 = 0x05
      //   f(3) = 0x01 ^ 0x06 = 0x07   (0x02 · 0x03 = 0x06, no reduction needed)
      final shares = SaltSharing.split(
        _filled(0x01),
        random: _FixedRandom(0x02),
      );
      expect(shares[0].y.every((b) => b == 0x03), isTrue);
      expect(shares[1].y.every((b) => b == 0x05), isTrue);
      expect(shares[2].y.every((b) => b == 0x07), isTrue);
    });

    test('rejects a secret that is not 16 bytes', () {
      expect(
        () => SaltSharing.split(Uint8List(32)),
        throwsArgumentError,
        reason: 'a 32-byte salt exceeds 2^128 and would be truncated by the '
            'prover, yielding an address nobody controls',
      );
      expect(() => SaltSharing.split(Uint8List(15)), throwsArgumentError);
    });

    test('is randomised — two splits of the same secret differ', () {
      final a = SaltSharing.split(_filled(0x7f));
      final b = SaltSharing.split(_filled(0x7f));
      // Rotation depends on this: fresh shares must not combine with old ones.
      expect(a[0].y, isNot(equals(b[0].y)));
    });
  });

  group('combine', () {
    test('ALL THREE 2-of-3 subsets reconstruct identically', () {
      final rng = Random(20260901);
      for (var trial = 0; trial < 200; trial++) {
        final secret = Uint8List.fromList(
          List<int>.generate(kSaltBytes, (_) => rng.nextInt(256)),
        );
        final shares = SaltSharing.split(secret);

        // This is the property that a happy-path test would miss and that a
        // real recovery depends on.
        expect(SaltSharing.combine([shares[0], shares[1]]), secret);
        expect(SaltSharing.combine([shares[0], shares[2]]), secret);
        expect(SaltSharing.combine([shares[1], shares[2]]), secret);
        expect(SaltSharing.combine(shares), secret);
      }
    });

    test('order of shares does not matter', () {
      final secret = _filled(0x3c);
      final shares = SaltSharing.split(secret);
      expect(SaltSharing.combine([shares[2], shares[0]]), secret);
      expect(SaltSharing.combine([shares[1], shares[0]]), secret);
    });

    test('reconstructs all-zero and all-ones secrets', () {
      for (final byte in [0x00, 0xff]) {
        final secret = _filled(byte);
        final shares = SaltSharing.split(secret);
        expect(SaltSharing.combine([shares[0], shares[2]]), secret);
      }
    });

    test('refuses fewer than two distinct shares', () {
      final shares = SaltSharing.split(_filled(0x11));
      expect(
        () => SaltSharing.combine([shares[0]]),
        throwsA(isA<SaltShareThresholdException>()),
      );
      // The same share twice is still only one point on the line.
      expect(
        () => SaltSharing.combine([shares[1], shares[1]]),
        throwsA(isA<SaltShareThresholdException>()),
      );
    });

    test('detects a corrupted third share instead of silently mis-combining',
        () {
      final secret = _filled(0x5a);
      final shares = SaltSharing.split(secret);
      final tampered = SaltShare(
        x: shares[2].x,
        y: Uint8List.fromList(shares[2].y)..[0] ^= 0xff,
      );
      expect(
        () => SaltSharing.combine([shares[0], shares[1], tampered]),
        throwsA(isA<SaltShareFormatException>()),
      );
    });

    test('rejects conflicting payloads at the same index', () {
      final shares = SaltSharing.split(_filled(0x22));
      final conflicting = SaltShare(
        x: shares[0].x,
        y: Uint8List.fromList(shares[0].y)..[3] ^= 0x01,
      );
      expect(
        () => SaltSharing.combine([shares[0], conflicting]),
        throwsA(isA<SaltShareFormatException>()),
      );
    });
  });

  group('wire format', () {
    test('round-trips through encode/decode', () {
      final shares = SaltSharing.split(_filled(0x6e));
      for (final share in shares) {
        final decoded = SaltShare.decode(share.encode());
        expect(decoded.x, share.x);
        expect(decoded.y, share.y);
      }
    });

    test('survives a full split -> encode -> decode -> combine cycle', () {
      final secret = _filled(0x91);
      final encoded = SaltSharing.split(secret).map((s) => s.encode()).toList();
      // Simulates Drive (B) plus backend (C) after the device is lost.
      final recovered = SaltSharing.combine([
        SaltShare.decode(encoded[1]),
        SaltShare.decode(encoded[2]),
      ]);
      expect(recovered, secret);
    });

    test('rejects an unsupported version byte', () {
      final share = SaltSharing.split(_filled(0x01)).first;
      final raw = base64Decode(share.encode())..[0] = 0x02;
      expect(
        () => SaltShare.decode(base64Encode(raw)),
        throwsA(isA<SaltShareFormatException>()),
      );
    });

    test('rejects a wrong-length payload', () {
      expect(
        () => SaltShare.decode(base64Encode(Uint8List(10))),
        throwsA(isA<SaltShareFormatException>()),
      );
    });

    test('rejects non-base64 input', () {
      expect(
        () => SaltShare.decode('not base64 at all!!'),
        throwsA(isA<SaltShareFormatException>()),
      );
    });

    test('rejects an out-of-range share index', () {
      final raw = base64Decode(SaltSharing.split(_filled(0x01)).first.encode())
        ..[1] = 4;
      expect(() => SaltShare.decode(base64Encode(raw)), throwsArgumentError);
    });
  });

  group('rotation', () {
    test('changes shares but preserves the secret, so the address is stable',
        () {
      final secret = _filled(0x4d);
      final original = SaltSharing.split(secret);
      final rotated = SaltSharing.split(
        SaltSharing.combine([original[0], original[1]]),
      );

      expect(SaltSharing.combine([rotated[0], rotated[2]]), secret);
      // Old and new share sets must not be interchangeable, or rotation would
      // not actually invalidate a leaked share.
      expect(rotated[0].y, isNot(equals(original[0].y)));
    });
  });

  group('hygiene', () {
    test('zeroize clears the payload', () {
      final share = SaltSharing.split(_filled(0x77)).first;
      share.zeroize();
      expect(share.y.every((b) => b == 0), isTrue);
    });

    test('toString does not leak share material', () {
      final share = SaltSharing.split(_filled(0xde)).first;
      expect(share.toString(), contains('redacted'));
      expect(share.toString(), isNot(contains('de')));
    });
  });
}
