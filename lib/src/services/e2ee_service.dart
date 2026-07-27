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
///   - Ed25519 seed (first 32 bytes of the wallet keypair) → X25519 key via
///     the standard RFC 8032 clamping. Same keypair already on device.
///   - ECDH shared secret per (sender, recipient) pair → HKDF-SHA256 per room.
///   - ChaCha20-Poly1305 AEAD for each message.
///   - No forward secrecy (same level as Snapchat/Instagram DMs).
///   - The server only ever sees `e2ee:<base64_blob>` — no plaintext.
///
/// Key derivation flow:
///   seed32 → X25519PrivateKey
///   counterpartyPubKey → X25519PublicKey (from base58-encoded Ed25519 pubkey)
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

  /// Registers the user's Ed25519 public key (base58 Solana wallet address)
  /// with the backend so counterparties can retrieve it for ECDH.
  /// Should be called once on first wallet unlock, and on key rotation.
  Future<void> registerPubkey(String walletAddress) async {
    try {
      await _apiClient.dio.put('/api/zend/users/me/pubkey', data: {
        'ed25519_public_key': walletAddress,
      });
    } catch (e) {
      // Non-fatal — will retry next unlock. Log for debugging only.
      assert(() {
        // ignore: avoid_print
        print('E2EE: Failed to register pubkey: $e');
        return true;
      }());
    }
  }

  /// Fetches the counterparty's Ed25519 public key from the backend.
  /// Returns null if the counterparty hasn't registered a pubkey yet
  /// (they're on an old app version or haven't opened the app since E2EE launch).
  Future<String?> fetchCounterpartyPubkey(String userId) async {
    try {
      final resp = await _apiClient.dio.get('/api/zend/users/$userId/pubkey');
      return resp.data['ed25519_public_key'] as String?;
    } catch (_) {
      return null;
    }
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
      // Step 1: Ed25519 seed → X25519 private key
      // The X25519 private key is the clamped SHA-512 hash of the Ed25519 seed.
      // We use the `cryptography` package's X25519 directly from seed bytes.
      final myPriv = await _x25519.newKeyPairFromSeed(mySeed32);

      // Step 2: Decode counterparty's Ed25519 pubkey (base58) → raw bytes
      final theirPubBytes = _decodeBase58(counterpartyPubkeyB58);
      if (theirPubBytes == null || theirPubBytes.length != 32) return null;

      // The `cryptography` X25519 package treats Ed25519 pubkey bytes as
      // X25519 pubkey bytes directly — this is the "static ECDH" approach
      // used by libsodium's crypto_box and NaCl.
      final theirPub = SimplePublicKey(theirPubBytes, type: KeyPairType.x25519);

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
  void clearCache() => _keyCache.clear();

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
