/// Shamir 2-of-3 secret sharing for the zkLogin salt.
///
/// The salt is the second factor of zkLogin's 2-of-2 scheme `(live JWT, salt)`.
/// Splitting it removes the single point of *loss* — any two of {device, Google
/// Drive, backend} reconstruct it — without changing theft resistance, which the
/// OAuth binding already provides.
///
/// Correctness here is unforgiving: a subtly wrong field implementation still
/// round-trips on the happy path and only fails once a share is missing, by which
/// point the funds are unreachable. Hence the field arithmetic is checked against
/// published AES GF(2^8) vectors and every 2-of-3 subset is asserted to agree.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Salt width in bytes.
///
/// Must match `SALT_BYTES = 16` on the backend. Not arbitrary: the salt is
/// consumed as a BN254 field element when deriving the address, and Sui requires
/// it below 2^128. A wider secret is either rejected by the prover or silently
/// truncated — and truncation yields an address nobody controls.
const int kSaltBytes = 16;

/// Wire format version. Present because an undetected format change here is
/// unrecoverable.
const int kShareVersion = 0x01;

/// version + x index + payload.
const int kShareWireBytes = 2 + kSaltBytes;

/// GF(2^8) with the AES reduction polynomial, generator 0x03.
///
/// Exposed for testing so the field can be validated independently of the
/// threshold scheme built on top of it.
class Gf256 {
  Gf256._();

  static final Uint8List _exp = Uint8List(255);
  static final Uint8List _log = Uint8List(256);
  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    var x = 1;
    for (var i = 0; i < 255; i++) {
      _exp[i] = x;
      _log[x] = i;
      // x *= 3, i.e. (x * 2) XOR x, reducing by 0x11b on overflow.
      var doubled = x << 1;
      if ((doubled & 0x100) != 0) doubled ^= 0x11b;
      x = (doubled ^ x) & 0xff;
    }
    _ready = true;
  }

  /// Multiplication. Zero is absorbing; logarithms are undefined there.
  static int mul(int a, int b) {
    _init();
    if (a == 0 || b == 0) return 0;
    return _exp[(_log[a] + _log[b]) % 255];
  }

  /// Division. Dividing by zero has no meaning in the field.
  static int div(int a, int b) {
    _init();
    if (b == 0) {
      throw ArgumentError('GF(256) division by zero');
    }
    if (a == 0) return 0;
    return _exp[(_log[a] - _log[b] + 255) % 255];
  }
}

/// One share of a split salt.
///
/// [x] is carried alongside the payload so reconstruction never has to infer
/// which share it is holding — getting that wrong would produce a plausible but
/// incorrect secret.
class SaltShare {
  SaltShare({required this.x, required Uint8List y})
    : y = Uint8List.fromList(y) {
    if (x < 1 || x > 3) {
      throw ArgumentError('Share index must be 1, 2 or 3 (got $x)');
    }
    if (y.length != kSaltBytes) {
      throw ArgumentError('Share payload must be $kSaltBytes bytes');
    }
  }

  /// Evaluation point, 1-based. Zero is the secret itself and is never a share.
  final int x;
  final Uint8List y;

  /// `version || x || y`, base64 encoded.
  String encode() {
    final out = Uint8List(kShareWireBytes)
      ..[0] = kShareVersion
      ..[1] = x
      ..setRange(2, kShareWireBytes, y);
    return base64Encode(out);
  }

  /// Parses [encoded], rejecting anything malformed rather than guessing.
  ///
  /// Every rejection here is preferable to a silent mis-reconstruction: a wrong
  /// secret produces a valid-looking address that holds no funds.
  static SaltShare decode(String encoded) {
    final Uint8List raw;
    try {
      raw = base64Decode(encoded.trim());
    } catch (_) {
      throw const SaltShareFormatException('Share is not valid base64');
    }
    if (raw.length != kShareWireBytes) {
      throw SaltShareFormatException(
        'Share must be $kShareWireBytes bytes, got ${raw.length}',
      );
    }
    if (raw[0] != kShareVersion) {
      throw SaltShareFormatException(
        'Unsupported share version ${raw[0]}; this build understands '
        '$kShareVersion',
      );
    }
    return SaltShare(x: raw[1], y: Uint8List.sublistView(raw, 2));
  }

  /// Overwrites the payload. Call once the secret has been reconstructed.
  void zeroize() {
    for (var i = 0; i < y.length; i++) {
      y[i] = 0;
    }
  }

  /// Never log a share: two of them reconstruct the salt.
  @override
  String toString() => 'SaltShare(x: $x, y: <redacted>)';
}

/// Splits and reconstructs a 16-byte salt as 2-of-3 shares.
class SaltSharing {
  const SaltSharing._();

  /// Splits [secret] into exactly three shares, any two of which reconstruct it.
  ///
  /// Each byte position gets an independent line `f(x) = secret ^ (r · x)` over
  /// GF(256), with fresh randomness per call — which is what makes rotation
  /// meaningful: re-splitting the same secret invalidates old shares while
  /// leaving the derived address untouched.
  ///
  /// [random] is injectable so tests can pin the coefficients; production must
  /// use the default, which is `Random.secure()`.
  static List<SaltShare> split(Uint8List secret, {Random? random}) {
    if (secret.length != kSaltBytes) {
      throw ArgumentError(
        'Salt must be exactly $kSaltBytes bytes, got ${secret.length}',
      );
    }
    final rng = random ?? Random.secure();
    final coefficients = Uint8List(kSaltBytes);
    for (var i = 0; i < kSaltBytes; i++) {
      coefficients[i] = rng.nextInt(256);
    }

    final shares = <SaltShare>[];
    for (var x = 1; x <= 3; x++) {
      final y = Uint8List(kSaltBytes);
      for (var i = 0; i < kSaltBytes; i++) {
        y[i] = secret[i] ^ Gf256.mul(coefficients[i], x);
      }
      shares.add(SaltShare(x: x, y: y));
    }

    // The coefficients are as sensitive as the secret while they live.
    for (var i = 0; i < coefficients.length; i++) {
      coefficients[i] = 0;
    }
    return shares;
  }

  /// Reconstructs the secret from two or more shares.
  ///
  /// When three shares are supplied, the result is computed twice from two
  /// different pairs and the answers must agree. That converts a corrupted share
  /// from a silent wrong answer into a thrown error — worth the extra work,
  /// because the wrong answer would look like a perfectly valid salt.
  static Uint8List combine(List<SaltShare> shares) {
    final byIndex = <int, SaltShare>{};
    for (final share in shares) {
      final existing = byIndex[share.x];
      if (existing != null) {
        // Two different payloads at the same x cannot both be right, and picking
        // one silently would be a coin flip on the user's funds.
        for (var i = 0; i < kSaltBytes; i++) {
          if (existing.y[i] != share.y[i]) {
            throw const SaltShareFormatException(
              'Conflicting shares supplied for the same index',
            );
          }
        }
        continue;
      }
      byIndex[share.x] = share;
    }

    final distinct = byIndex.values.toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    if (distinct.length < 2) {
      throw const SaltShareThresholdException(
        'At least 2 distinct shares are required to reconstruct the salt',
      );
    }

    final primary = _interpolate([distinct[0], distinct[1]]);
    if (distinct.length > 2) {
      final crossCheck = _interpolate([distinct[0], distinct[2]]);
      for (var i = 0; i < kSaltBytes; i++) {
        if (primary[i] != crossCheck[i]) {
          throw const SaltShareFormatException(
            'Shares disagree — at least one is corrupt',
          );
        }
      }
    }
    return primary;
  }

  /// Lagrange interpolation at x = 0, which is where the secret lives.
  static Uint8List _interpolate(List<SaltShare> points) {
    final secret = Uint8List(kSaltBytes);
    for (var j = 0; j < points.length; j++) {
      // basis_j = product over k != j of x_k / (x_j XOR x_k)
      var basis = 1;
      for (var k = 0; k < points.length; k++) {
        if (k == j) continue;
        final denominator = points[j].x ^ points[k].x;
        basis = Gf256.mul(basis, Gf256.div(points[k].x, denominator));
      }
      for (var i = 0; i < kSaltBytes; i++) {
        // Addition in GF(2^n) is XOR.
        secret[i] ^= Gf256.mul(points[j].y[i], basis);
      }
    }
    return secret;
  }
}

/// A share was structurally invalid, or shares contradicted each other.
class SaltShareFormatException implements Exception {
  const SaltShareFormatException(this.message);
  final String message;

  @override
  String toString() => 'SaltShareFormatException: $message';
}

/// Fewer than two distinct shares were available.
class SaltShareThresholdException implements Exception {
  const SaltShareThresholdException(this.message);
  final String message;

  @override
  String toString() => 'SaltShareThresholdException: $message';
}

/// Renders a 16-byte salt as the decimal integer the prover and address
/// derivation expect.
///
/// Must match the backend's `UserSalt::to_decimal_string` byte for byte: the salt
/// is interpreted as a big-endian integer below 2^128. A mismatch here produces a
/// valid-looking proof against an address nobody controls.
String saltToDecimalString(Uint8List salt) {
  if (salt.length != kSaltBytes) {
    throw ArgumentError('Salt must be exactly $kSaltBytes bytes');
  }
  var value = BigInt.zero;
  for (final byte in salt) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value.toString();
}
