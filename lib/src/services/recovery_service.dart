import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';

import 'cloud_backup_service.dart';
import 'wallet_service.dart';
import 'wallet_session_cache.dart';

/// ─── Data model ──────────────────────────────────────────────────────────────

/// The JSON payload stored in the user's cloud drive (Drive/iCloud).
///
/// All binary fields are hex-encoded. Version is always `"argon2id-v1"`.
/// The `salt` field is the same Wallet_Salt used for the PIN backup, so the
/// NationalID derivation uses the same salt without revealing a second salt.
class RecoveryPacket {
  const RecoveryPacket({
    required this.version,
    required this.salt,
    required this.iv,
    required this.ciphertext,
    required this.tag,
  });

  /// Always `"argon2id-v1"`.
  final String version;

  /// Hex-encoded Wallet_Salt (32 bytes). Same salt used for PIN derivation.
  final String salt;

  /// Hex-encoded AES-GCM nonce (12 bytes). Fresh for every write.
  final String iv;

  /// Hex-encoded AES-GCM ciphertext (64 bytes) — the encrypted keypair body.
  final String ciphertext;

  /// Hex-encoded AES-GCM authentication tag (16 bytes).
  final String tag;

  Map<String, dynamic> toJson() => {
        'version': version,
        'salt': salt,
        'iv': iv,
        'ciphertext': ciphertext,
        'tag': tag,
      };

  factory RecoveryPacket.fromJson(Map<String, dynamic> j) => RecoveryPacket(
        version: j['version'] as String,
        salt: j['salt'] as String,
        iv: j['iv'] as String,
        ciphertext: j['ciphertext'] as String,
        tag: j['tag'] as String,
      );

  @override
  String toString() => jsonEncode(toJson());
}

/// ─── Exceptions ──────────────────────────────────────────────────────────────

/// Thrown when the NationalID is wrong (AES-GCM tag verification fails).
class RecoveryDecryptionException implements Exception {
  const RecoveryDecryptionException();
  @override
  String toString() => 'RecoveryDecryptionException: incorrect National ID';
}

/// Thrown when no recovery packet exists in the user's cloud storage.
class RecoveryPacketNotFoundException implements Exception {
  const RecoveryPacketNotFoundException();
  @override
  String toString() => 'RecoveryPacketNotFoundException: no recovery packet in cloud';
}

/// ─── Service ─────────────────────────────────────────────────────────────────

/// Manages non-custodial PIN recovery via National ID + cloud backup.
///
/// ## Trust model
/// - The recovery packet is stored in the user's personal cloud (Drive/iCloud),
///   never on Zend's servers.
/// - AES-GCM encryption uses `AltKey = Argon2id(NationalID, Wallet_Salt)`.
/// - Wallet_Salt is the same salt used for the PIN backup, so no second random
///   value needs to be stored. A wrong NationalID always fails decryption.
/// - Zend never sees NationalID, AltKey, or the plaintext keypair.
///
/// ## Usage
/// - Setup: call [createRecoveryBackup] after onboarding (or from Settings).
/// - Recovery: call [decryptRecoveryPacket] during the forgot-PIN flow.
class RecoveryService {
  RecoveryService({
    required WalletService wallet,
    required CloudBackupService cloud,
  })  : _wallet = wallet,
        _cloud = cloud;

  final WalletService _wallet;
  final CloudBackupService _cloud;

  /// Creates (or updates) the recovery packet in the user's cloud drive.
  ///
  /// Requires the session cache to be populated (app must be unlocked).
  /// Zeroes all sensitive bytes in memory on every exit path.
  ///
  /// Throws [RecoverySetupRequiresUnlockException] if the session cache is empty.
  /// Throws [CloudBackupException] on Drive/iCloud failure.
  Future<void> createRecoveryBackup(String nationalId) async {
    // Must have an active session — keypair comes from the cache, not a PIN prompt
    final cachedKeypair = WalletSessionCache.instance.keypair;
    if (cachedKeypair == null) {
      throw RecoverySetupRequiresUnlockException();
    }

    // Wallet_Salt — used for both PIN backup and recovery
    final salt = await _wallet.readSalt();

    // Derive AltKey = Argon2id(NationalID, Wallet_Salt)
    final Uint8List altKey = await _wallet.deriveKeyArgon2id(nationalId, salt);

    try {
      final (ciphertext, nonce) = await _encryptAesGcm(cachedKeypair, altKey);

      // Split ciphertext (64 bytes) and tag (16 bytes)
      final bodyLen = ciphertext.length - 16;
      final body = ciphertext.sublist(0, bodyLen);
      final tag = ciphertext.sublist(bodyLen);

      final packet = RecoveryPacket(
        version: 'argon2id-v1',
        salt: hex.encode(salt),
        iv: hex.encode(nonce),
        ciphertext: hex.encode(body),
        tag: hex.encode(tag),
      );

      await _cloud.storeRecoveryPacket(packet);
    } finally {
      for (var i = 0; i < altKey.length; i++) { altKey[i] = 0; }
      for (var i = 0; i < cachedKeypair.length; i++) { cachedKeypair[i] = 0; }
    }
  }

  /// Downloads and decrypts the recovery packet using [nationalId].
  ///
  /// Returns the plaintext 64-byte keypair on success.
  /// The caller MUST zero the returned bytes after use.
  ///
  /// Throws [RecoveryPacketNotFoundException] if no packet exists.
  /// Throws [RecoveryDecryptionException] if the NationalID is wrong.
  /// Throws [CloudBackupException] on Drive/iCloud failure.
  Future<Uint8List> decryptRecoveryPacket(String nationalId) async {
    final packet = await _cloud.downloadRecoveryPacket();
    if (packet == null) throw const RecoveryPacketNotFoundException();

    final salt = Uint8List.fromList(hex.decode(packet.salt));
    final altKey = await _wallet.deriveKeyArgon2id(nationalId, salt);

    try {
      // Re-assemble ciphertext + tag
      final body = Uint8List.fromList(hex.decode(packet.ciphertext));
      final tag = Uint8List.fromList(hex.decode(packet.tag));
      final combined = Uint8List(body.length + tag.length)
        ..setRange(0, body.length, body)
        ..setRange(body.length, body.length + tag.length, tag);

      final nonce = Uint8List.fromList(hex.decode(packet.iv));

      try {
        return await _decryptAesGcm(combined, nonce, altKey);
      } catch (_) {
        throw const RecoveryDecryptionException();
      }
    } finally {
      for (var i = 0; i < altKey.length; i++) { altKey[i] = 0; }
    }
  }

  /// Returns true if a recovery packet exists in the user's cloud storage.
  Future<bool> hasRecoveryBackup() => _cloud.hasRecoveryPacket();

  // ── AES-256-GCM helpers ───────────────────────────────────────────────────

  Future<(Uint8List ciphertext, Uint8List nonce)> _encryptAesGcm(
    Uint8List plaintext,
    Uint8List keyBytes,
  ) async {
    final algorithm = AesGcm.with256bits();
    final key = SecretKey(keyBytes.toList());
    final nonce = algorithm.newNonce(); // 12 bytes, random
    final secretBox = await algorithm.encrypt(plaintext, secretKey: key, nonce: nonce);
    return (
      Uint8List.fromList(secretBox.concatenation(nonce: false)),
      Uint8List.fromList(nonce),
    );
  }

  Future<Uint8List> _decryptAesGcm(
    Uint8List ciphertext, // ciphertext + 16-byte tag
    Uint8List nonce,
    Uint8List keyBytes,
  ) async {
    const macLength = 16;
    final algorithm = AesGcm.with256bits();
    final key = SecretKey(keyBytes.toList());
    final encData = ciphertext.sublist(0, ciphertext.length - macLength);
    final mac = Mac(ciphertext.sublist(ciphertext.length - macLength));
    final secretBox = SecretBox(encData, nonce: nonce, mac: mac);
    final plaintext = await algorithm.decrypt(secretBox, secretKey: key);
    return Uint8List.fromList(plaintext);
  }
}

/// Thrown when [createRecoveryBackup] is called while the session cache is empty.
/// The user must unlock the app first.
class RecoverySetupRequiresUnlockException implements Exception {
  @override
  String toString() =>
      'RecoverySetupRequiresUnlockException: app must be unlocked to set up recovery';
}
