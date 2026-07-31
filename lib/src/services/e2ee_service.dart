import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'api_client.dart';

/// Prefix added to all E2EE-encrypted message content.
/// The server stores and forwards this blob as-is.
/// Old plaintext messages (no prefix) are displayed as-is with a
/// "⚠️ not encrypted" indicator on the bubble.
const kE2eePrefix = 'e2ee:';

/// Manages end-to-end encryption for DM rooms using static X25519 ECDH.
///
/// Security model:
///   - Ed25519 seed (32 bytes of the wallet keypair) → X25519 private scalar
///     via SHA-512(seed)[0:32] (the same "expanded scalar" Ed25519 itself
///     uses internally — X25519 clamps it again at use time, which is
///     idempotent). This is the standard `crypto_sign_ed25519_sk_to_curve25519`
///     conversion used by libsodium.
///   - Counterparty's Ed25519 public key (Edwards y-coordinate) → X25519
///     public key (Montgomery u-coordinate) via the birational map
///     u = (1 + y) / (1 - y) mod (2^255 - 19). This is the standard
///     `crypto_sign_ed25519_pk_to_curve25519` conversion. Without this
///     conversion, raw Ed25519 pubkey bytes are NOT a valid X25519 public key
///     for the corresponding private scalar, and ECDH between two different
///     users' wallets will not produce a matching shared secret.
///   - ECDH shared secret per (sender, recipient) pair → HKDF-SHA256 per room.
///   - ChaCha20-Poly1305 AEAD for each message.
///   - No forward secrecy (same level as Snapchat/Instagram DMs).
///   - The server only ever sees `e2ee:<base64_blob>` — no plaintext.
///
/// Key derivation flow:
///   mySeed32 → SHA-512 → first 32 bytes → X25519 private key
///   counterpartyPubKey (base58 Ed25519) → decode → birational map → X25519 public key
///   X25519.sharedSecretKey(myPriv, theirPub) → sharedSecret
///   HKDF(sharedSecret, salt=room_id, info='zend-dm-e2ee') → symmetricKey
///   ChaCha20Poly1305.encrypt(key=symmetricKey, nonce=random12, plaintext) → ciphertext
class E2eeService {
  E2eeService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  // Algorithms from the `cryptography` package
  static final _x25519 = X25519();
  static final _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );
  static final _chacha = Chacha20.poly1305Aead();

  // Cache derived symmetric keys per room to avoid re-deriving on every message
  final _keyCache = <String, SecretKey>{};

  /// Set once [registerPubkey] has succeeded for the current session, so
  /// repeated calls (every unlock, every DM thread open) short-circuit
  /// instead of re-hitting the network for a key that's already published.
  bool _pubkeyRegisteredThisSession = false;

  /// Tracks an in-flight registration so concurrent callers (e.g. the app
  /// lock overlay and a DM thread screen unlocking at the same moment) share
  /// a single request instead of racing multiple PUTs.
  Future<void>? _registerInFlight;

  static const List<Duration> _registerRetryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  /// Registers the user's Ed25519 public key (base58 Solana wallet address)
  /// with the backend so counterparties can retrieve it for ECDH.
  ///
  /// Must be called on EVERY path that materializes the wallet keypair in
  /// memory (fresh signup, device unlock, backup restore, PIN migration) —
  /// not just app-lock re-unlock — otherwise the very first DM session after
  /// that path sends plaintext until a chat happens to be opened separately.
  ///
  /// Safe to call redundantly: no-ops once registered this session, and
  /// dedupes concurrent in-flight calls. Retries transient failures with
  /// backoff before giving up (silently — the next unlock will retry).
  Future<void> registerPubkey(String walletAddress) async {
    if (_pubkeyRegisteredThisSession) return;
    final inFlight = _registerInFlight;
    if (inFlight != null) return inFlight;

    final future = _registerPubkeyWithRetry(walletAddress);
    _registerInFlight = future;
    try {
      await future;
    } finally {
      _registerInFlight = null;
    }
  }

  Future<void> _registerPubkeyWithRetry(String walletAddress) async {
    for (var attempt = 0; attempt <= _registerRetryDelays.length; attempt++) {
      try {
        await _apiClient.dio.put('/api/zend/users/me/pubkey', data: {
          'ed25519_public_key': walletAddress,
        });
        _pubkeyRegisteredThisSession = true;
        return;
      } catch (e) {
        final isLastAttempt = attempt == _registerRetryDelays.length;
        if (isLastAttempt) {
          // Non-fatal — will retry on the next unlock/thread open. Log for
          // debugging only; never surface this to the user mid-flow.
          assert(() {
            // ignore: avoid_print
            print('E2EE: Failed to register pubkey after ${attempt + 1} attempts: $e');
            return true;
          }());
          return;
        }
        await Future.delayed(_registerRetryDelays[attempt]);
      }
    }
  }

  /// Fetches the counterparty's Ed25519 public key from the backend.
  /// Returns null if the counterparty hasn't registered a pubkey yet
  /// (they're on an old app version or haven't opened the app since E2EE launch),
  /// or if the request keeps failing after one retry (transient network blip).
  Future<String?> fetchCounterpartyPubkey(String userId) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await _apiClient.dio.get('/api/zend/users/$userId/pubkey');
        return resp.data['ed25519_public_key'] as String?;
      } catch (_) {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 400));
          continue;
        }
        return null;
      }
    }
    return null;
  }

  /// Derives the symmetric key for a DM room.
  ///
  /// [mySeed32] — first 32 bytes of the wallet keypair (Ed25519 seed).
  /// [counterpartyPubkeyB58] — counterparty's Ed25519 pubkey in base58.
  /// [roomId] — used as HKDF salt so different rooms get different keys.
  Future<SecretKey?> deriveRoomKey({
    required Uint8List mySeed32,
    required String counterpartyPubkeyB58,
    required String roomId,
  }) async {
    final cacheKey = '$roomId:$counterpartyPubkeyB58';
    if (_keyCache.containsKey(cacheKey)) return _keyCache[cacheKey];

    try {
      // Step 1: Ed25519 seed → X25519 private scalar.
      // This is the standard `crypto_sign_ed25519_sk_to_curve25519` conversion:
      // SHA-512(seed), take the first 32 bytes, then RFC 7748 clamp. This is
      // the exact same scalar Ed25519 itself derives internally, so it is
      // guaranteed to correspond to the Ed25519 public key we published.
      final privScalar = await _ed25519SeedToX25519Scalar(mySeed32);
      final myPriv = await _x25519.newKeyPairFromSeed(privScalar);

      // Step 2: Decode counterparty's Ed25519 pubkey (base58) → raw bytes
      final theirPubBytes = _decodeBase58(counterpartyPubkeyB58);
      if (theirPubBytes == null || theirPubBytes.length != 32) return null;

      // Step 2b: Convert their Ed25519 public key (Edwards y-coordinate) to
      // the corresponding X25519 public key (Montgomery u-coordinate) via the
      // standard birational map. Ed25519 and X25519 pubkey bytes are NOT
      // interchangeable — treating one as the other silently produces a
      // shared secret that only matches by coincidence, so decryption across
      // two different users' devices was unreliable without this step.
      final theirU = _edwardsYToMontgomeryU(theirPubBytes);
      if (theirU == null) return null;
      final theirPub = SimplePublicKey(
        _bigIntToLittleEndian32(theirU),
        type: KeyPairType.x25519,
      );

      // Step 3: ECDH → shared secret
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: myPriv,
        remotePublicKey: theirPub,
      );

      // Step 4: HKDF-SHA256 to bind the shared secret to this specific room
      final roomIdBytes = utf8.encode(roomId);
      final symmetricKey = await _hkdf.deriveKey(
        secretKey: sharedSecret,
        nonce: roomIdBytes,
        info: utf8.encode('zend-dm-e2ee'),
      );

      _keyCache[cacheKey] = symmetricKey;
      return symmetricKey;
    } catch (e) {
      return null;
    }
  }

  /// Encrypts [plaintext] for a DM room.
  ///
  /// Returns the wire-format string: `e2ee:<base64(nonce12 || ciphertext)>`
  /// Returns null if encryption fails (falls back to plaintext send).
  Future<String?> encrypt({
    required String plaintext,
    required Uint8List mySeed32,
    required String counterpartyPubkeyB58,
    required String roomId,
  }) async {
    final key = await deriveRoomKey(
      mySeed32: mySeed32,
      counterpartyPubkeyB58: counterpartyPubkeyB58,
      roomId: roomId,
    );
    if (key == null) return null;

    try {
      final plainBytes = utf8.encode(plaintext);
      // ChaCha20-Poly1305 expects a 12-byte nonce.
      // newNonce() returns List<int> directly — use it as-is.
      final nonce = _chacha.newNonce();
      final box = await _chacha.encrypt(
        plainBytes,
        secretKey: key,
        nonce: nonce,
      );

      // Wire format: nonce (12 bytes) || ciphertext || tag
      final combined = Uint8List(12 + box.cipherText.length + box.mac.bytes.length);
      combined.setRange(0, 12, nonce);
      combined.setRange(12, 12 + box.cipherText.length, box.cipherText);
      combined.setRange(
        12 + box.cipherText.length,
        combined.length,
        box.mac.bytes,
      );

      return '$kE2eePrefix${base64Encode(combined)}';
    } catch (_) {
      return null;
    }
  }

  /// Decrypts a wire-format E2EE message.
  ///
  /// [wireContent] must start with `e2ee:`.
  /// Returns the plaintext string, or null if decryption fails.
  Future<String?> decrypt({
    required String wireContent,
    required Uint8List mySeed32,
    required String counterpartyPubkeyB58,
    required String roomId,
  }) async {
    if (!wireContent.startsWith(kE2eePrefix)) return null;

    final key = await deriveRoomKey(
      mySeed32: mySeed32,
      counterpartyPubkeyB58: counterpartyPubkeyB58,
      roomId: roomId,
    );
    if (key == null) return null;

    try {
      final combined = base64Decode(wireContent.substring(kE2eePrefix.length));
      if (combined.length < 12 + 16) return null; // nonce(12) + min Poly1305 tag(16)

      final nonceBytes = combined.sublist(0, 12);

      // Split ciphertext and MAC (last 16 bytes is Poly1305 tag)
      final cipherTextWithTag = combined.sublist(12);
      final cipherText = cipherTextWithTag.sublist(
        0, cipherTextWithTag.length - 16,
      );
      final mac = Mac(cipherTextWithTag.sublist(cipherTextWithTag.length - 16));

      final box = SecretBox(
        cipherText,
        nonce: nonceBytes,
        mac: mac,
      );

      final plainBytes = await _chacha.decrypt(box, secretKey: key);
      return utf8.decode(plainBytes);
    } catch (_) {
      // Decryption failed — wrong key or tampered ciphertext
      return null;
    }
  }

  /// Clears the key cache (call on logout or key rotation).
  /// Also resets the "registered this session" flag — on logout a different
  /// user may sign in on the same app instance and must publish their own key.
  void clearCache() {
    _keyCache.clear();
    _pubkeyRegisteredThisSession = false;
  }

  // ── Ed25519 → X25519 conversion ─────────────────────────────────────────────
  //
  // Standard conversions (same as libsodium's crypto_sign_ed25519_*_to_curve25519).
  // These are required because Ed25519 and X25519 keys live on different
  // (birationally equivalent) curve models — Edwards vs Montgomery — so raw
  // byte reuse between them is not a valid substitute for the real mapping.

  static final _sha512 = Sha512();

  /// Converts an Ed25519 seed to the corresponding X25519 private scalar.
  /// SHA-512(seed) → take the first 32 bytes. `X25519.newKeyPairFromSeed`
  /// applies RFC 7748 clamping on top of this, matching Ed25519's own
  /// internal scalar derivation.
  Future<Uint8List> _ed25519SeedToX25519Scalar(Uint8List seed) async {
    final hash = await _sha512.hash(seed);
    return Uint8List.fromList(hash.bytes.sublist(0, 32));
  }

  /// The finite field prime p = 2^255 - 19 used by both Curve25519 and Ed25519.
  static final BigInt _p =
      BigInt.parse('7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed', radix: 16);

  /// Converts a compressed Ed25519 public key (little-endian, sign bit in the
  /// top bit of the last byte) to the Montgomery u-coordinate used by X25519,
  /// via the birational map u = (1 + y) / (1 - y) mod p.
  BigInt? _edwardsYToMontgomeryU(Uint8List edPubKey) {
    if (edPubKey.length != 32) return null;
    try {
      // Decode the y-coordinate: little-endian 255 bits (clear the sign bit).
      final clamped = Uint8List.fromList(edPubKey);
      clamped[31] &= 0x7f;
      var y = BigInt.zero;
      for (var i = 31; i >= 0; i--) {
        y = (y << 8) | BigInt.from(clamped[i]);
      }
      if (y >= _p) return null;

      final one = BigInt.one;
      final numerator = (one + y) % _p;
      final denominator = (one - y) % _p;
      final denominatorInv = denominator.modInverse(_p);
      final u = (numerator * denominatorInv) % _p;
      return u < BigInt.zero ? u + _p : u;
    } catch (_) {
      return null;
    }
  }

  /// Serializes a field element as 32 little-endian bytes, as required by
  /// the X25519 public key wire format.
  Uint8List _bigIntToLittleEndian32(BigInt value) {
    final out = Uint8List(32);
    var v = value;
    final mask = BigInt.from(0xff);
    for (var i = 0; i < 32; i++) {
      out[i] = (v & mask).toInt();
      v = v >> 8;
    }
    return out;
  }

  // ── Base58 decoder ─────────────────────────────────────────────────────────
  // Solana wallet addresses are base58-encoded 32-byte Ed25519 public keys.
  // The `cryptography` package doesn't include base58; we implement it here.

  static const _b58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  Uint8List? _decodeBase58(String input) {
    try {
      final bytes = <int>[];
      var n = BigInt.zero;
      for (final c in input.split('')) {
        final digit = _b58Alphabet.indexOf(c);
        if (digit < 0) return null;
        n = n * BigInt.from(58) + BigInt.from(digit);
      }

      // Convert BigInt → bytes
      var hex = n.toRadixString(16);
      if (hex.length % 2 != 0) hex = '0$hex';
      for (var i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }

      // Prepend leading zeros (each leading '1' in base58 = 0x00 byte)
      var leadingZeros = 0;
      for (var i = 0; i < input.length; i++) {
        if (input[i] == '1') {
          leadingZeros++;
        } else {
          break;
        }
      }
      return Uint8List.fromList([
        ...List.filled(leadingZeros, 0),
        ...bytes,
      ]);
    } catch (_) {
      return null;
    }
  }
}
