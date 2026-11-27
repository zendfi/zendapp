/// RFC 9180 HPKE, base mode only, single-shot seal (contracts.md §2.1).
///
/// Suite: DHKEM(X25519, HKDF-SHA256) 0x0020 / HKDF-SHA256 0x0001 /
/// AES-256-GCM 0x0002. AES-128-GCM (0x0001) is supported too, only so the
/// RFC's own A.1 vectors can be checked byte for byte.
///
/// Every step is exposed so tests can compare each intermediate value with
/// the RFC 9180 test vectors.
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'ziro_bytes.dart';

const int kHpkeKemX25519 = 0x0020;
const int kHpkeKdfSha256 = 0x0001;
const int kHpkeAeadAes128Gcm = 0x0001;
const int kHpkeAeadAes256Gcm = 0x0002;

/// What one seal produces: the encapsulated key and `ct || tag`.
class HpkeSealed {
  const HpkeSealed({required this.enc, required this.ciphertext});
  final Uint8List enc;
  final Uint8List ciphertext;
}

/// Key schedule outputs (RFC 9180 §5.1), kept for tests.
class HpkeContext {
  const HpkeContext({
    required this.keyScheduleContext,
    required this.secret,
    required this.key,
    required this.baseNonce,
  });
  final Uint8List keyScheduleContext;
  final Uint8List secret;
  final Uint8List key;
  final Uint8List baseNonce;
}

class Hpke {
  Hpke({this.aeadId = kHpkeAeadAes256Gcm})
    : assert(aeadId == kHpkeAeadAes256Gcm || aeadId == kHpkeAeadAes128Gcm);

  final int aeadId;
  static final _hmac = Hmac.sha256();
  static final _x25519 = X25519();

  int get _nk => aeadId == kHpkeAeadAes256Gcm ? 32 : 16;
  static const _nn = 12;
  static const _nh = 32;

  static final Uint8List _version = zUtf8('HPKE-v1');
  static final Uint8List kemSuiteId = zCat([zUtf8('KEM'), zI2osp2(kHpkeKemX25519)]);
  Uint8List get hpkeSuiteId => zCat([
    zUtf8('HPKE'),
    zI2osp2(kHpkeKemX25519),
    zI2osp2(kHpkeKdfSha256),
    zI2osp2(aeadId),
  ]);

  // ── HKDF-SHA256 (RFC 5869) ────────────────────────────────────────────────

  static Future<Uint8List> hmac(List<int> key, List<int> data) async {
    // HMAC pads the key with zeros to the block size, so an empty key and
    // 32 zero bytes are the same key. `cryptography` refuses an empty one.
    final k = key.isEmpty ? Uint8List(32) : key;
    final mac = await _hmac.calculateMac(data, secretKey: SecretKey(k));
    return Uint8List.fromList(mac.bytes);
  }

  /// HKDF-Extract. An empty salt means HashLen zero bytes.
  static Future<Uint8List> extract(List<int> salt, List<int> ikm) =>
      hmac(salt.isEmpty ? Uint8List(_nh) : salt, ikm);

  /// HKDF-Expand.
  static Future<Uint8List> expand(List<int> prk, List<int> info, int length) async {
    if (length > 255 * _nh) throw ArgumentError('HKDF length too large');
    final out = BytesBuilder();
    var t = Uint8List(0);
    var i = 1;
    while (out.length < length) {
      t = await hmac(prk, zCat([t, info, [i]]));
      out.add(t);
      i++;
    }
    return Uint8List.sublistView(out.toBytes(), 0, length);
  }

  /// HKDF-SHA256(ikm, salt, info, length): the one-call form.
  static Future<Uint8List> hkdf({
    required List<int> ikm,
    List<int> salt = const [],
    required List<int> info,
    required int length,
  }) async => expand(await extract(salt, ikm), info, length);

  // ── Labeled HKDF (RFC 9180 §4) ────────────────────────────────────────────

  static Future<Uint8List> labeledExtract(
    List<int> suiteId,
    List<int> salt,
    String label,
    List<int> ikm,
  ) => extract(salt, zCat([_version, suiteId, zUtf8(label), ikm]));

  static Future<Uint8List> labeledExpand(
    List<int> suiteId,
    List<int> prk,
    String label,
    List<int> info,
    int length,
  ) => expand(
    prk,
    zCat([zI2osp2(length), _version, suiteId, zUtf8(label), info]),
    length,
  );

  // ── DHKEM(X25519, HKDF-SHA256) (RFC 9180 §4.1, §7.1.3) ─────────────────────

  /// DeriveKeyPair(ikm) → (sk, pk). Only used with a fixed ikm in tests;
  /// [seal] uses a fresh random key.
  static Future<(Uint8List, Uint8List)> deriveKeyPair(List<int> ikm) async {
    final prk = await labeledExtract(kemSuiteId, const [], 'dkp_prk', ikm);
    final sk = await labeledExpand(kemSuiteId, prk, 'sk', const [], 32);
    final kp = await _x25519.newKeyPairFromSeed(sk);
    final pk = (await kp.extractPublicKey()).bytes;
    return (sk, Uint8List.fromList(pk));
  }

  static Future<Uint8List> _dh(List<int> sk, List<int> pk) async {
    final kp = await _x25519.newKeyPairFromSeed(sk);
    final s = await _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(pk, type: KeyPairType.x25519),
    );
    final out = Uint8List.fromList(await s.extractBytes());
    // RFC 9180 §7.1.4: refuse a low-order public key.
    if (out.every((b) => b == 0)) {
      throw StateError('HPKE: invalid recipient key');
    }
    return out;
  }

  /// Encap(pkR) with the ephemeral secret [skE]. Returns (shared_secret, enc).
  static Future<(Uint8List, Uint8List)> encapWith(
    List<int> pkR,
    List<int> skE,
  ) async {
    if (pkR.length != 32) throw ArgumentError('X25519 key must be 32 bytes');
    final kp = await _x25519.newKeyPairFromSeed(skE);
    final enc = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final dh = await _dh(skE, pkR);
    final kemContext = zCat([enc, pkR]);
    final eaePrk = await labeledExtract(kemSuiteId, const [], 'eae_prk', dh);
    final shared = await labeledExpand(
      kemSuiteId,
      eaePrk,
      'shared_secret',
      kemContext,
      32,
    );
    zWipe(dh);
    return (shared, enc);
  }

  // ── Key schedule, base mode (RFC 9180 §5.1) ───────────────────────────────

  Future<HpkeContext> keySchedule(List<int> sharedSecret, List<int> info) async {
    final sid = hpkeSuiteId;
    final pskIdHash = await labeledExtract(sid, const [], 'psk_id_hash', const []);
    final infoHash = await labeledExtract(sid, const [], 'info_hash', info);
    final ctx = zCat([
      [0x00],
      pskIdHash,
      infoHash,
    ]);
    final secret = await labeledExtract(sid, sharedSecret, 'secret', const []);
    final key = await labeledExpand(sid, secret, 'key', ctx, _nk);
    final nonce = await labeledExpand(sid, secret, 'base_nonce', ctx, _nn);
    return HpkeContext(
      keyScheduleContext: ctx,
      secret: secret,
      key: key,
      baseNonce: nonce,
    );
  }

  /// Seals with sequence number [seq] (0 for single-shot).
  Future<Uint8List> aeadSeal(
    HpkeContext ctx,
    List<int> aad,
    List<int> plaintext, {
    int seq = 0,
  }) async {
    final nonce = Uint8List.fromList(ctx.baseNonce);
    var s = seq;
    for (var i = _nn - 1; i >= 0 && s > 0; i--) {
      nonce[i] ^= s & 0xff;
      s >>= 8;
    }
    final aead = aeadId == kHpkeAeadAes256Gcm
        ? AesGcm.with256bits()
        : AesGcm.with128bits();
    final box = await aead.encrypt(
      plaintext,
      secretKey: SecretKey(ctx.key),
      nonce: nonce,
      aad: aad,
    );
    return zCat([box.cipherText, box.mac.bytes]);
  }

  /// SealBase(pkR, info, aad, pt) with a fresh ephemeral key.
  /// [ephemeralSecretForTest] fixes skE for known-answer tests only.
  Future<HpkeSealed> seal({
    required List<int> recipientPublicKey,
    required List<int> info,
    required List<int> aad,
    required List<int> plaintext,
    List<int>? ephemeralSecretForTest,
  }) async {
    final skE =
        ephemeralSecretForTest ??
        await (await _x25519.newKeyPair()).extractPrivateKeyBytes();
    final (shared, enc) = await encapWith(recipientPublicKey, skE);
    final ctx = await keySchedule(shared, info);
    final ct = await aeadSeal(ctx, aad, plaintext);
    zWipe(shared);
    zWipe(ctx.key);
    if (ephemeralSecretForTest == null) zWipe(skE);
    return HpkeSealed(enc: enc, ciphertext: ct);
  }
}
