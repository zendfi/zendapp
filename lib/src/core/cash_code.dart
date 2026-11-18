/// Cash codes: a money link whose key comes from a 17-character code instead of
/// a random key in the URL, so it can be read out, written down or scanned.
///
///   K7Q4M-9X2P-WRTH-3NB6
///   └┬┘└────── 13 ────┘└ check
///   lookup
///
/// * **Lookup** (3): reserved from the server, unique among live cash. It is
///   the only part Zend knows. It finds the link and is the Argon2 salt, so
///   every live cash link has its own salt.
/// * **Secret** (13 = 65 bits): made on this device and never sent anywhere.
/// * **Check** (1): catches a typo as soon as the code is complete. Adds no
///   security.
///
/// The link key is `Argon2id(secret, salt = "zend-cash-v1:" + lookup)`, 64 MiB,
/// 1 pass, 1 lane, 32 bytes, Argon2 v1.3. The memory cost is what holds off
/// GPU guessing: never lower it, on any platform. Web runs the same parameters
/// through WebAssembly (`web/zend_argon2.js`, built from `seal/src/zend_argon2.ts`).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import 'cash_kdf_io.dart' if (dart.library.js_interop) 'cash_kdf_web.dart';

/// Crockford base32: no I, L, O or U, so it reads aloud and survives handwriting.
const String kCashAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Must match `CASH_OPEN_DOMAIN` in `src/zlinks.rs`.
const String kCashOpenDomain = 'zend-cash-open-v1';
const String kCashSaltDomain = 'zend-cash-v1:';
const String kCashUrlBase = 'https://app.usezend.app/cash';

const int kCashPrefixLength = 3;
const int kCashSecretLength = 13;
const int kCashCodeLength = kCashPrefixLength + kCashSecretLength + 1;

/// Why a typed code can't be used yet.
enum CashCodeProblem { incomplete, tooLong, badCharacter, typo }

class CashCode {
  const CashCode._(this.prefix, this.secret);

  /// The 3-character lookup.
  final String prefix;

  /// The 13-character secret. Never log it, never send it.
  final String secret;

  /// A fresh code on the reserved [prefix].
  factory CashCode.generate(String prefix) {
    assert(prefix.length == kCashPrefixLength);
    final rng = Random.secure();
    final secret = String.fromCharCodes(
      List.generate(
        kCashSecretLength,
        (_) => kCashAlphabet.codeUnitAt(rng.nextInt(kCashAlphabet.length)),
      ),
    );
    return CashCode._(prefix, secret);
  }

  /// Parses a typed, scanned or linked code. Forgiving about case, spaces,
  /// dashes and look-alike letters (O→0, I/L→1).
  static CashCode? tryParse(String input) =>
      check(input) == null ? _parse(normalise(input)) : null;

  /// Null when [input] is a complete, valid code.
  static CashCodeProblem? check(String input) {
    final n = normalise(input);
    if (n.split('').any((c) => !kCashAlphabet.contains(c))) {
      return CashCodeProblem.badCharacter;
    }
    if (n.length < kCashCodeLength) return CashCodeProblem.incomplete;
    if (n.length > kCashCodeLength) return CashCodeProblem.tooLong;
    final body = n.substring(0, kCashCodeLength - 1);
    if (_checkChar(body) != n[kCashCodeLength - 1]) {
      return CashCodeProblem.typo;
    }
    return null;
  }

  static CashCode _parse(String n) => CashCode._(
    n.substring(0, kCashPrefixLength),
    n.substring(kCashPrefixLength, kCashCodeLength - 1),
  );

  /// Upper case, separators dropped, look-alikes mapped. Characters that are
  /// still outside the alphabet are kept so [check] can point at them.
  static String normalise(String input) {
    final out = StringBuffer();
    for (final c in input.toUpperCase().split('')) {
      if (c == '-' || c == ' ' || c == '_' || c == '.' || c == '\n') continue;
      out.write(switch (c) {
        'O' => '0',
        'I' || 'L' => '1',
        _ => c,
      });
    }
    return out.toString();
  }

  /// Groups a (partial) code for display: `K7Q4M-9X2P-WRTH-3NB6`.
  static String group(String normalised) {
    const breaks = [5, 9, 13];
    final out = StringBuffer();
    for (var i = 0; i < normalised.length; i++) {
      if (breaks.contains(i)) out.write('-');
      out.write(normalised[i]);
    }
    return out.toString();
  }

  static String _checkChar(String body) {
    final digest = SHA256Digest().process(
      Uint8List.fromList(ascii.encode(body)),
    );
    return kCashAlphabet[digest[0] >> 3];
  }

  /// All 17 characters, ungrouped.
  String get compact {
    final body = '$prefix$secret';
    return '$body${_checkChar(body)}';
  }

  /// How people see and type it.
  String get display => group(compact);

  /// The shareable link. The code sits after `#`, which browsers never send
  /// to a server.
  String get url => '$kCashUrlBase#$compact';

  /// The bytes the link key signs to open the cash (see `zlinks::cash_open`).
  Uint8List get openMessage =>
      Uint8List.fromList([...utf8.encode(kCashOpenDomain), ...ascii.encode(prefix)]);

  static final Map<String, Future<Uint8List>> _seeds = {};

  /// The 32-byte link key seed. Takes seconds on purpose; the result is kept
  /// in memory (never on disk) so starting it early, opening and collecting
  /// all share one derivation.
  Future<Uint8List> seed() {
    final key = compact;
    return _seeds[key] ??= () async {
      try {
        final out = await deriveCashSeed(
          Uint8List.fromList(ascii.encode(secret)),
          Uint8List.fromList(utf8.encode('$kCashSaltDomain$prefix')),
        );
        if (out.length != 32) throw StateError('cash key derivation failed');
        return out;
      } catch (_) {
        _seeds.remove(key);
        rethrow;
      }
    }();
  }

  @override
  String toString() => 'CashCode($prefix…)';
}

/// The code carried by a cash link (`app.usezend.app/cash#…`), or null.
CashCode? cashCodeFromFragment(String fragment) =>
    CashCode.tryParse(Uri.decodeComponent(fragment));
