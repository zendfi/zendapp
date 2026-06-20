import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/key_derivators/argon2.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';

import 'api_client.dart';
import 'wallet_kdf.dart';
import 'wallet_session_cache.dart';
import '../models/api_exceptions.dart';

// ── Argon2id background isolate helpers ───────────────────────────────────────
// These must be top-level (not inside a class) so `compute()` can serialize
// them across isolate boundaries.

/// Parameters passed to the background isolate for Argon2id derivation.
class _Argon2Params {
  const _Argon2Params({required this.secret, required this.salt, this.tCostOverride});
  final String secret;
  final Uint8List salt;
  /// When set, overrides [WalletKdf.tCost] for this derivation.
  /// Used only for the v3→v4 migration to decrypt old t=3 backups.
  final int? tCostOverride;
}

/// Top-level entry point for the Argon2id background isolate.
/// Called by [WalletService._deriveKeyArgon2id] via `compute()`.
Uint8List _argon2idIsolateEntry(_Argon2Params params) {
  final secretBytes = Uint8List.fromList(utf8.encode(params.secret));
  try {
    final argon2Params = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      params.salt,
      desiredKeyLength: WalletKdf.hashLen,
      memory: WalletKdf.mCost,
      iterations: params.tCostOverride ?? WalletKdf.tCost,
      lanes: WalletKdf.pCost,
      version: Argon2Parameters.ARGON2_VERSION_13,
    );
    final argon2 = Argon2BytesGenerator()..init(argon2Params);
    final result = Uint8List(WalletKdf.hashLen);
    argon2.deriveKey(secretBytes, 0, result, 0);
    return result;
  } finally {
    for (var i = 0; i < secretBytes.length; i++) { secretBytes[i] = 0; }
  }
}

class WalletService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _secureStorage;

  static const _encryptedPrivateKeyKey = 'zend_wallet_encrypted_private_key';
  static const _rawPrivateKeyKey = 'zend_wallet_raw_private_key'; // cleared after PIN setup
  static const _publicKeyKey = 'zend_wallet_public_key';
  static const _pinSaltKey = 'zend_pin_salt';
  static const _encryptionNonceKey = 'zend_encryption_nonce';
  static const _kdfVersionKey = 'zend_kdf_version';

  static const _usdcMintAddress = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

  WalletService({
        required ApiClient apiClient,
        required FlutterSecureStorage secureStorage,
      })  : _apiClient = apiClient,
        _secureStorage = secureStorage;

      ApiClient get apiClient => _apiClient;

  Future<String> generateKeypair() async {
    final keypair = await Ed25519HDKeyPair.random();

    final walletAddress = keypair.address;

    final extractedKey = await keypair.extract();
    final keypairBytes = extractedKey.bytes;

    // Store raw bytes in a dedicated slot. setupPinAndBackup reads from here
    // and moves the encrypted result to _encryptedPrivateKeyKey. Using separate
    // slots prevents double-encryption if setupPinAndBackup is retried.
    await _secureStorage.write(
      key: _rawPrivateKeyKey,
      value: base64Encode(Uint8List.fromList(keypairBytes)),
    );

    await _secureStorage.write(key: _publicKeyKey, value: walletAddress);

    return walletAddress;
  }


  Future<bool> hasLocalKeypair() async {
    final key = await _secureStorage.read(key: _encryptedPrivateKeyKey);
    return key != null && key.isNotEmpty;
  }

  Future<bool> hasPinSetup() async {
    final salt = await _secureStorage.read(key: _pinSaltKey);
    return salt != null && salt.isNotEmpty;
  }

  Future<void> verifyLocalPin(String pin) async {
    final privateKeyBytes = await _decryptLocalKeypair(pin);
    for (var i = 0; i < privateKeyBytes.length; i++) {
      privateKeyBytes[i] = 0;
    }
  }

  Future<String?> getWalletAddress() async {
    return _secureStorage.read(key: _publicKeyKey);
  }

  Future<void> setupPinAndBackup(String pin) async {
    // Read from the raw key slot. If not present, fall back to the encrypted
    // slot for devices that registered on an older build.
    final rawKeyB64 = await _secureStorage.read(key: _rawPrivateKeyKey)
        ?? await _secureStorage.read(key: _encryptedPrivateKeyKey);
    if (rawKeyB64 == null) {
      throw StateError('No keypair found. Call generateKeypair first.');
    }
    final privateKeyBytes = base64Decode(rawKeyB64);

    final salt = _generateRandomBytes(32);

    final rawKey = await _deriveKeyArgon2id(pin, salt);
    final secretKey = SecretKey(rawKey);
    final (ciphertext, nonce) = await _encryptAesGcm(privateKeyBytes, secretKey);

    await _secureStorage.write(
      key: _encryptedPrivateKeyKey,
      value: base64Encode(ciphertext),
    );
    await _secureStorage.write(
      key: _pinSaltKey,
      value: base64Encode(salt),
    );
    await _secureStorage.write(
      key: _encryptionNonceKey,
      value: base64Encode(nonce),
    );

    // Clear the raw key slot now that the encrypted version is stored.
    await _secureStorage.delete(key: _rawPrivateKeyKey);

    final walletAddress = await _secureStorage.read(key: _publicKeyKey);
    if (walletAddress == null) {
      throw StateError('No wallet address found.');
    }

    // Combine salt + nonce + ciphertext for the backup payload
    // The server stores this as opaque bytes — it can't decrypt without the PIN
    final backupPayload = _buildBackupPayload(salt, nonce, ciphertext);

    try {
      await _apiClient.storeBackup(
        base64Encode(backupPayload),
        base64Encode(nonce),
        walletAddress,
      );
    } catch (e) {
      // Retry once
      try {
        await _apiClient.storeBackup(
          base64Encode(backupPayload),
          base64Encode(nonce),
          walletAddress,
        );
      } catch (_) {
        // Backup failed but keypair is stored locally — user can proceed
        // The backup can be retried later
      }
    }
    await _secureStorage.write(key: _kdfVersionKey, value: '4');
    await _secureStorage.write(key: _pinLengthKey, value: '6');
  }

  Future<void> restoreFromBackup(String pin) async {
    final backup = await _apiClient.retrieveBackup();

    final backupBytes = base64Decode(backup.encryptedKeypair);
    final nonceBytes = base64Decode(backup.nonce);

    // Detect backup format:
    // - 80-byte payload: salt(32) || ciphertext(48)  — current format (32-byte seed)
    // - 112-byte payload: salt(32) || ciphertext(80) — old intended format (64-byte keypair)
    // - Legacy ciphertext-only: use locally stored salt (pre-unified builds)
    final Uint8List salt;
    final Uint8List ciphertext;
    final bool isLegacyBackup;

    if (backupBytes.length == 80 || backupBytes.length == 112) {
      // Unified format: first 32 bytes are the salt, rest is ciphertext
      (salt, ciphertext) = _parseBackupPayload(backupBytes);
      isLegacyBackup = false;
    } else if (backupBytes.length == 48) {
      // Very old legacy: ciphertext only (no salt in payload), salt stored locally
      final localSaltB64 = await _secureStorage.read(key: _pinSaltKey);
      if (localSaltB64 == null) throw PinDecryptionException();
      salt = base64Decode(localSaltB64);
      ciphertext = backupBytes;
      isLegacyBackup = true;
    } else {
      throw PinDecryptionException();
    }

    final derivedKey = await _deriveKeyArgon2id(pin, salt);

    Uint8List privateKeyBytes;
    try {
      privateKeyBytes = await _decryptAesGcm(ciphertext, nonceBytes, SecretKey(derivedKey));
    } catch (_) {
      throw PinDecryptionException();
    }

    await _secureStorage.write(
      key: _encryptedPrivateKeyKey,
      value: base64Encode(ciphertext),
    );
    await _secureStorage.write(key: _publicKeyKey, value: backup.publicKey);
    await _secureStorage.write(
      key: _pinSaltKey,
      value: base64Encode(salt),
    );
    await _secureStorage.write(
      key: _encryptionNonceKey,
      value: base64Encode(nonceBytes),
    );
    await _secureStorage.write(key: _kdfVersionKey, value: '4');

    // If this was a very old ciphertext-only backup (no salt embedded), silently
    // re-encrypt and re-upload in the current 80-byte unified format.
    if (isLegacyBackup) {
      unawaited(_reuploadUnifiedBackup(pin, privateKeyBytes));
    }

    for (var i = 0; i < privateKeyBytes.length; i++) {
      privateKeyBytes[i] = 0;
    }
  }

  /// Silently re-derives, re-encrypts, and re-uploads a unified 80-byte backup
  /// (salt32 + ciphertext48). Called after a successful legacy ciphertext-only
  /// restore. Best-effort — errors are ignored.
  Future<void> _reuploadUnifiedBackup(String pin, Uint8List privateKeyBytes) async {
    try {
      final newSalt = _generateRandomBytes(32);
      final rawKey = await _deriveKeyArgon2id(pin, newSalt);
      final secretKey = SecretKey(rawKey);
      final (newCiphertext, newNonce) = await _encryptAesGcm(privateKeyBytes, secretKey);

      // Persist the new encrypted data locally
      await _secureStorage.write(
        key: _encryptedPrivateKeyKey,
        value: base64Encode(newCiphertext),
      );
      await _secureStorage.write(
        key: _pinSaltKey,
        value: base64Encode(newSalt),
      );
      await _secureStorage.write(
        key: _encryptionNonceKey,
        value: base64Encode(newNonce),
      );
      await _secureStorage.write(key: _kdfVersionKey, value: '4');

      final walletAddress = await _secureStorage.read(key: _publicKeyKey);
      if (walletAddress == null) return;

      final backupPayload = _buildBackupPayload(newSalt, newNonce, newCiphertext);
      await _apiClient.storeBackup(
        base64Encode(backupPayload),
        base64Encode(newNonce),
        walletAddress,
      );
    } catch (_) {
      // Best-effort — ignore failures; will retry on next restore
    }
  }

  Future<void> changePin(String currentPin, String newPin) async {
    final privateKeyBytes = await _decryptLocalKeypair(currentPin);

    final newSalt = _generateRandomBytes(32);
    final rawKey = await _deriveKeyArgon2id(newPin, newSalt);
    final secretKey = SecretKey(rawKey);
    final (newCiphertext, newNonce) = await _encryptAesGcm(privateKeyBytes, secretKey);

    await _secureStorage.write(
      key: _encryptedPrivateKeyKey,
      value: base64Encode(newCiphertext),
    );
    await _secureStorage.write(
      key: _pinSaltKey,
      value: base64Encode(newSalt),
    );
    await _secureStorage.write(
      key: _encryptionNonceKey,
      value: base64Encode(newNonce),
    );

    final walletAddress = await _secureStorage.read(key: _publicKeyKey);
    if (walletAddress != null) {
      final backupPayload =
          _buildBackupPayload(newSalt, newNonce, newCiphertext);
      await _apiClient.storeBackup(
        base64Encode(backupPayload),
        base64Encode(newNonce),
        walletAddress,
      );
    }
    await _secureStorage.write(key: _kdfVersionKey, value: '4');
    await _secureStorage.write(key: _pinLengthKey, value: '6');

    for (var i = 0; i < privateKeyBytes.length; i++) {
      privateKeyBytes[i] = 0;
    }
  }

  Future<String> getBalance() async {
    final response = await _apiClient.getBalance();
    return response.spendableBalance;
  }

  /// Returns both the raw on-chain balance and the spendable balance.
  /// Spendable = on-chain minus pending email intent amounts.
  Future<({String usdc, String spendable})> getFullBalance() async {
    final response = await _apiClient.getBalance();
    return (usdc: response.usdcBalance, spendable: response.spendableBalance);
  }

  /// Public wrapper around [_decryptLocalKeypair] for use by [EmailIntentService].
  /// Callers are responsible for zeroing the returned bytes after use.
  Future<Uint8List> decryptLocalKeypair(String pin) async {
    return _decryptLocalKeypair(pin);
  }

  /// Builds, signs, and submits an SPL Token `Approve` instruction on-chain.
  ///
  /// This grants [feePayerPubkeyB58] delegate authority over [amountUsdc] of
  /// USDC in the sender's token account. The tokens stay in the sender's wallet.
  /// Returns the transaction signature.
  Future<String> buildAndSubmitSplApprove({
    required Uint8List senderKeypairBytes,
    required String feePayerPubkeyB58,
    required double amountUsdc,
    required String pin,
  }) async {
    // Defensive copy so we can zero on exit, regardless of what the caller does.
    final keyCopy = Uint8List.fromList(senderKeypairBytes);
    try {
    final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
      privateKey: _extractSeed(keyCopy).toList(),
    );

    final senderPubkey = Ed25519HDPublicKey.fromBase58(keypair.address);
    final feePayerPubkey = Ed25519HDPublicKey.fromBase58(feePayerPubkeyB58);
    final usdcMint = Ed25519HDPublicKey.fromBase58(_usdcMintAddress);

    final senderAta = await findAssociatedTokenAddress(
      owner: senderPubkey,
      mint: usdcMint,
    );

    // Amount in USDC base units (6 decimals)
    final amountTokens = (amountUsdc * 1_000_000).round();

    // SPL Token Approve instruction: discriminator = 4, followed by 8-byte LE amount
    // accounts: [source (writable), delegate, owner (signer)]
    final amountBytes = Uint8List(8);
    var v = amountTokens;
    for (var i = 0; i < 8; i++) { amountBytes[i] = v & 0xFF; v >>= 8; }

    final approveIx = Instruction(
      programId: Ed25519HDPublicKey.fromBase58(
          'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'),
      accounts: [
        AccountMeta(pubKey: senderAta, isWriteable: true, isSigner: false),
        AccountMeta(pubKey: feePayerPubkey, isWriteable: false, isSigner: false),
        AccountMeta(pubKey: senderPubkey, isWriteable: false, isSigner: true),
      ],
      data: ByteArray(Uint8List.fromList([4, 0, 0, 0, ...amountBytes])),
    );

    // Fetch a fresh blockhash from the backend
    final prepData = await _apiClient.prepareApproveTransaction(
      amountUsdc: amountUsdc,
      feePayerPubkey: feePayerPubkeyB58,
    );
    final blockhash = prepData['blockhash'] as String;
    final feePayer = Ed25519HDPublicKey.fromBase58(prepData['fee_payer'] as String);

    final message = Message(instructions: [approveIx]);
    final compiled = message.compile(recentBlockhash: blockhash, feePayer: feePayer);

    final sig = await keypair.sign(compiled.toByteArray());

    final signedTx = SignedTx(
      compiledMessage: compiled,
      signatures: [
        Signature(List.filled(64, 0), publicKey: feePayer),
        Signature(sig.bytes, publicKey: senderPubkey),
      ],
    );

    final txB64 = base64Encode(signedTx.toByteArray().toList());

    // Submit the partially-signed approve tx; backend fee-payer co-signs and submits
    final result = await _apiClient.submitApproveTransaction(txB64: txB64);
    return result['transaction_signature'] as String;
    } finally {
      // Zero the defensive keypair copy regardless of outcome
      for (var i = 0; i < keyCopy.length; i++) { keyCopy[i] = 0; }
    }
  }

  Future<String> buildAndSignTransaction({
    required String pin,
    required double amountUsdc,
    required String recipientAddress,
    required String blockhash,
    required String feePayerAddress,
    String? senderAtaOverride,
    String? recipientAtaOverride,
  }) async {
    final privateKeyBytes = await _decryptLocalKeypair(pin);

    try {
      final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: _extractSeed(privateKeyBytes).toList(),
      );

      final senderPubkey = Ed25519HDPublicKey.fromBase58(keypair.address);
      final recipientPubkey = Ed25519HDPublicKey.fromBase58(recipientAddress);
      final usdcMint = Ed25519HDPublicKey.fromBase58(_usdcMintAddress);

      // Use server-provided ATAs when available — they're derived from the wallet
      // address stored in the DB which is authoritative. Deriving locally can
      // produce a mismatch if the stored keypair address doesn't exactly match.
      final senderAta = senderAtaOverride != null
          ? Ed25519HDPublicKey.fromBase58(senderAtaOverride)
          : await findAssociatedTokenAddress(owner: senderPubkey, mint: usdcMint);
      final recipientAta = recipientAtaOverride != null
          ? Ed25519HDPublicKey.fromBase58(recipientAtaOverride)
          : await findAssociatedTokenAddress(owner: recipientPubkey, mint: usdcMint);

      final amountTokens = (amountUsdc * 1000000).round();

      final transferInstruction = TokenInstruction.transfer(
        source: senderAta,
        destination: recipientAta,
        owner: senderPubkey,
        amount: amountTokens,
      );

      final feePayer = Ed25519HDPublicKey.fromBase58(feePayerAddress);

      final message = Message(
        instructions: [transferInstruction],
      );

      final compiledMessage = message.compile(
        recentBlockhash: blockhash,
        feePayer: feePayer,
      );

      final signature = await keypair.sign(compiledMessage.toByteArray());

      final signedTx = SignedTx(
        compiledMessage: compiledMessage,
        signatures: [
          Signature(List.filled(64, 0), publicKey: feePayer),
          Signature(signature.bytes, publicKey: senderPubkey),
        ],
      );

      return base64Encode(signedTx.toByteArray().toList());
    } finally {
      for (var i = 0; i < privateKeyBytes.length; i++) {
        privateKeyBytes[i] = 0;
      }
    }
  }

  /// Build and sign a USDC transfer to a Solana wallet address (e.g. PAJ deposit
  /// address or Bridge liquidation address). Derives the destination ATA from
  /// the wallet address — same pattern as [buildAndSignTransaction].
  Future<String> buildAndSignTransactionToAddress({
    required String pin,
    required double amountUsdc,
    required String destinationAddress,
    required String blockhash,
    required String feePayerAddress,
  }) async {
    final privateKeyBytes = await _decryptLocalKeypair(pin);

    try {
      final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: _extractSeed(privateKeyBytes).toList(),
      );

      final senderPubkey = Ed25519HDPublicKey.fromBase58(keypair.address);
      final destinationPubkey =
          Ed25519HDPublicKey.fromBase58(destinationAddress);
      final usdcMint = Ed25519HDPublicKey.fromBase58(_usdcMintAddress);

      final senderAta = await findAssociatedTokenAddress(
        owner: senderPubkey,
        mint: usdcMint,
      );

      // Both PAJ and Bridge deposit addresses are wallet addresses that own
      // an ATA — derive the ATA before transferring.
      final destinationAta = await findAssociatedTokenAddress(
        owner: destinationPubkey,
        mint: usdcMint,
      );

      final amountTokens = (amountUsdc * 1000000).round();

      final transferInstruction = TokenInstruction.transfer(
        source: senderAta,
        destination: destinationAta,
        owner: senderPubkey,
        amount: amountTokens,
      );

      final feePayer = Ed25519HDPublicKey.fromBase58(feePayerAddress);

      final message = Message(instructions: [transferInstruction]);
      final compiledMessage = message.compile(
        recentBlockhash: blockhash,
        feePayer: feePayer,
      );

      final signature = await keypair.sign(compiledMessage.toByteArray());

      final signedTx = SignedTx(
        compiledMessage: compiledMessage,
        signatures: [
          Signature(List.filled(64, 0), publicKey: feePayer),
          Signature(signature.bytes, publicKey: senderPubkey),
        ],
      );

      return base64Encode(signedTx.toByteArray().toList());
    } finally {
      for (var i = 0; i < privateKeyBytes.length; i++) {
        privateKeyBytes[i] = 0;
      }
    }
  }

  /// Signs a pre-built versioned transaction (v0 or legacy) from the backend.
  ///
  /// The backend returns an unsigned [VersionedTransaction] as base64. This method:
  /// 1. Decrypts the user's keypair with their PIN
  /// 2. Extracts the message bytes from the raw transaction bytes
  /// 3. Signs the message with the keypair
  /// 4. Places the signature in the correct slot (matching the user's pubkey)
  /// 5. Returns the partially-signed transaction as base64
  ///
  /// The private key is zeroed in memory before returning, regardless of outcome.
  /// Throws [PinDecryptionException] if the PIN is wrong.
  Future<String> signExistingTransaction({
    required String pin,
    required String txBytesB64,
  }) async {
    final privateKeyBytes = await _decryptLocalKeypair(pin);
    try {
      final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: _extractSeed(privateKeyBytes).toList(),
      );

      final txBytes = base64Decode(txBytesB64);

      // VersionedTransaction wire format:
      //   [compact-u16: num_signatures]
      //   [num_signatures × 64 bytes: signature slots (zeros for unsigned)]
      //   [message bytes: remainder]
      final numSigsResult = _readCompactU16(Uint8List.fromList(txBytes), 0);
      final numSigs = numSigsResult.value;
      final sigsSectionStart = numSigsResult.bytesConsumed;
      final messageStart = sigsSectionStart + numSigs * 64;
      final messageBytes = Uint8List.fromList(txBytes.sublist(messageStart));

      // Sign the raw message bytes
      final signature = await keypair.sign(messageBytes);

      // Find the user's pubkey slot in the message's accountKeys
      final userPubkeyBytes = keypair.publicKey.bytes;
      final sigSlot = _findPubkeySlotInMessage(messageBytes, userPubkeyBytes);

      // Splice the signature into a copy of the transaction bytes
      final result = Uint8List.fromList(txBytes);
      final slotOffset = sigsSectionStart + sigSlot * 64;
      result.setRange(slotOffset, slotOffset + 64, signature.bytes);

      return base64Encode(result);
    } finally {
      for (var i = 0; i < privateKeyBytes.length; i++) {
        privateKeyBytes[i] = 0;
      }
    }
  }

  /// Reads a compact-u16 from [bytes] at [offset].
  /// Returns the decoded value and the number of bytes consumed (1, 2, or 3).
  ///
  /// Solana compact-u16 encoding:
  ///   - Values 0–127: 1 byte
  ///   - Values 128–16383: 2 bytes (low 7 bits in first byte with high bit set, next 7 bits in second byte)
  ///   - Values 16384–32767: 3 bytes
  ({int value, int bytesConsumed}) _readCompactU16(Uint8List bytes, int offset) {
    int value = 0;
    int bytesConsumed = 0;
    for (var i = 0; i < 3; i++) {
      final byte = bytes[offset + i];
      value |= (byte & 0x7F) << (7 * i);
      bytesConsumed++;
      if ((byte & 0x80) == 0) break;
    }
    return (value: value, bytesConsumed: bytesConsumed);
  }

  /// Finds the index of [pubkeyBytes] in the static account keys section of a
  /// Solana message (both legacy and v0 formats).
  ///
  /// Returns the slot index (0-based) where the pubkey appears.
  /// Returns 0 as a safe fallback if the pubkey is not found (fee payer slot).
  int _findPubkeySlotInMessage(Uint8List messageBytes, List<int> pubkeyBytes) {
    // Both legacy and v0 messages have a 3-byte header followed by a compact-u16
    // count of static account keys, then the keys themselves (32 bytes each).
    //
    // v0 messages start with a version prefix byte (0x80), legacy do not.
    int offset = 0;
    if (messageBytes.isNotEmpty && messageBytes[0] == 0x80) {
      offset = 1; // skip v0 version prefix
    }
    offset += 3; // skip 3-byte message header

    final numKeysResult = _readCompactU16(messageBytes, offset);
    final numKeys = numKeysResult.value;
    offset += numKeysResult.bytesConsumed;

    for (var i = 0; i < numKeys; i++) {
      final keyStart = offset + i * 32;
      if (keyStart + 32 > messageBytes.length) break;
      final key = messageBytes.sublist(keyStart, keyStart + 32);
      if (_bytesEqual(key, pubkeyBytes)) return i;
    }

    return 0; // safe fallback: fee payer slot
  }

  /// Compares two byte sequences for equality.
  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static const _pinLengthKey = 'zend_pin_length';

  /// Returns true if the device has a 4-digit PIN that needs upgrading to 6 digits.
  ///
  /// A migration is only needed when:
  ///   1. The PIN length key is explicitly '4', OR
  ///   2. The PIN length key is absent AND the KDF version is legacy (not '4').
  ///
  /// New accounts always have kdf_version='4' written by [setupPinAndBackup].
  /// Any device with the current KDF version is either already migrated or was
  /// created after the migration system launched — either way, no upgrade needed.
  Future<bool> needsMigration() async {
    final pinLength = await _secureStorage.read(key: _pinLengthKey);
    final kdfVersion = await _secureStorage.read(key: _kdfVersionKey);

    // If pin_length is explicitly '6', never needs migration.
    if (pinLength == '6') return false;

    // If the KDF is already current (v4 = Argon2id t=1), the account was either
    // created with the new system or already migrated — no PIN upgrade needed.
    // We write the pin_length key here as a side-effect so future checks are fast.
    if (kdfVersion == '4') {
      // Backfill the pin_length key so we skip this check next time.
      unawaited(_secureStorage.write(key: _pinLengthKey, value: '6'));
      return false;
    }

    // pin_length absent + KDF not v4 → legacy account that needs 4→6 digit upgrade.
    return true;
  }

  /// Marks the PIN migration as complete by storing pin_length=6.
  Future<void> markMigrationComplete() async {
    await _secureStorage.write(key: _pinLengthKey, value: '6');
  }

  /// Reads the currently stored 32-byte salt from secure storage.
  Future<Uint8List> readSalt() async {
    final b64 = await _secureStorage.read(key: _pinSaltKey);
    if (b64 == null) throw StateError('No salt found in secure storage.');
    return base64Decode(b64);
  }

  /// Reads the currently stored 12-byte nonce from secure storage.
  Future<Uint8List> readNonce() async {
    final b64 = await _secureStorage.read(key: _encryptionNonceKey);
    if (b64 == null) throw StateError('No nonce found in secure storage.');
    return base64Decode(b64);
  }

  /// Reads the currently stored ciphertext (48 bytes: 32-byte seed + 16-byte GCM tag) from secure storage.
  Future<Uint8List> readCiphertext() async {
    final b64 = await _secureStorage.read(key: _encryptedPrivateKeyKey);
    if (b64 == null) throw StateError('No ciphertext found in secure storage.');
    return base64Decode(b64);
  }

  Future<void> clearLocalData() async {
    await _secureStorage.delete(key: _encryptedPrivateKeyKey);
    await _secureStorage.delete(key: _rawPrivateKeyKey);
    await _secureStorage.delete(key: _publicKeyKey);
    await _secureStorage.delete(key: _pinSaltKey);
    await _secureStorage.delete(key: _encryptionNonceKey);
    await _secureStorage.delete(key: _kdfVersionKey);
    await _secureStorage.delete(key: _pinLengthKey);
  }

  /// Normalises a keypair byte array to the 32-byte Ed25519 seed.
  ///
  /// Accounts created on zendonline store a 64-byte keypair (seed || pubkey).
  /// Accounts created on zendapp store a 32-byte seed only.
  /// `Ed25519HDKeyPair.fromPrivateKeyBytes` accepts exactly 32 bytes, so we
  /// always take the first 32 bytes regardless of the total length.
  static Uint8List _extractSeed(Uint8List keypairBytes) {
    if (keypairBytes.length >= 64) {
      return Uint8List.fromList(keypairBytes.sublist(0, 32));
    }
    return keypairBytes; // already 32 bytes — return as-is
  }

  Future<Uint8List> _decryptLocalKeypair(String pin) async {
    final encryptedB64 = await _secureStorage.read(key: _encryptedPrivateKeyKey);
    final saltB64 = await _secureStorage.read(key: _pinSaltKey);
    final nonceB64 = await _secureStorage.read(key: _encryptionNonceKey);
    final kdfVersion = await _secureStorage.read(key: _kdfVersionKey);

    if (encryptedB64 == null || saltB64 == null || nonceB64 == null) {
      throw StateError('No encrypted keypair found in secure storage.');
    }

    final ciphertext = base64Decode(encryptedB64);
    final salt = base64Decode(saltB64);
    final nonce = base64Decode(nonceB64);

    // kdfVersion == '4' → Argon2id m=65536, t=1 (current)
    // kdfVersion == '3' → Argon2id m=65536, t=3 (previous — transparently migrate to v4)
    // kdfVersion == null or '2' → PBKDF2 legacy
    if (kdfVersion == '4' || kdfVersion == '3') {
      // Argon2id path — parameters stored in WalletKdf constants (currently t=1).
      // v3 backups were encrypted with t=3; since we changed tCost to 1, decrypting
      // a v3 backup with the current params will fail. We must use the stored version
      // to select the right tCost.
      final tCost = kdfVersion == '3' ? 3 : WalletKdf.tCost;
      final rawKey = await _deriveKeyArgon2idWithParams(pin, Uint8List.fromList(salt), tCost: tCost);
      final secretKey = SecretKey(rawKey);
      try {
        final plaintext = await _decryptAesGcm(
          Uint8List.fromList(ciphertext),
          Uint8List.fromList(nonce),
          secretKey,
        );
        // If decrypted with v3 params (t=3), silently re-encrypt with v4 (t=1) in background
        if (kdfVersion == '3') {
          unawaited(_migrateToArgon2id(plaintext, pin));
        }
        return plaintext;
      } catch (_) {
        throw PinDecryptionException();
      } finally {
        for (var i = 0; i < rawKey.length; i++) { rawKey[i] = 0; }
      }
    } else {
      // Legacy PBKDF2 path — decrypt then transparently migrate to Argon2id
      final plaintext = await _legacyDecryptPbkdf2(pin, salt, nonce, ciphertext);
      // Background migration: re-encrypt with Argon2id
      unawaited(_migrateToArgon2id(plaintext, pin));
      return plaintext;
    }
  }

  /// Decrypts a legacy PBKDF2-encrypted keypair. Called only when kdfVersion != '3'.
  Future<Uint8List> _legacyDecryptPbkdf2(
      String pin, List<int> salt, List<int> nonce, List<int> ciphertext) async {
    final iterationsStr = await _secureStorage.read(key: 'zend_pbkdf2_iterations');
    final storedIterations = int.tryParse(iterationsStr ?? '');

    if (storedIterations != null) {
      final derivedKey = await _deriveKeyFromPinWithIterations(
          pin, Uint8List.fromList(salt), storedIterations);
      try {
        final plaintext = await _decryptAesGcm(
          Uint8List.fromList(ciphertext),
          Uint8List.fromList(nonce),
          derivedKey,
        );
        return plaintext;
      } catch (_) {
        throw PinDecryptionException();
      }
    }

    // No stored count — try both known PBKDF2 iteration counts
    for (final iterations in [100000, 10000]) {
      final derivedKey = await _deriveKeyFromPinWithIterations(
          pin, Uint8List.fromList(salt), iterations);
      try {
        return await _decryptAesGcm(
          Uint8List.fromList(ciphertext),
          Uint8List.fromList(nonce),
          derivedKey,
        );
      } catch (_) {
        continue;
      }
    }
    throw PinDecryptionException();
  }

  /// Re-encrypts with Argon2id and re-uploads. Called after legacy PBKDF2 decrypt.
  /// Best-effort — errors ignored; migration retried on next unlock.
  Future<void> _migrateToArgon2id(Uint8List privateKeyBytes, String pin) async {
    try {
      final newSalt = _generateRandomBytes(32);
      final rawKey = await _deriveKeyArgon2id(pin, newSalt);
      final secretKey = SecretKey(rawKey);
      final (newCiphertext, newNonce) = await _encryptAesGcm(privateKeyBytes, secretKey);

      await _secureStorage.write(
          key: _encryptedPrivateKeyKey, value: base64Encode(newCiphertext));
      await _secureStorage.write(
          key: _pinSaltKey, value: base64Encode(newSalt));
      await _secureStorage.write(
          key: _encryptionNonceKey, value: base64Encode(newNonce));
      await _secureStorage.write(key: _kdfVersionKey, value: '4');

      final walletAddress = await _secureStorage.read(key: _publicKeyKey);
      if (walletAddress == null) return;

      final backupPayload = _buildBackupPayload(newSalt, newNonce, newCiphertext);
      await _apiClient.storeBackup(
          base64Encode(backupPayload), base64Encode(newNonce), walletAddress);
      for (var i = 0; i < rawKey.length; i++) { rawKey[i] = 0; }
    } catch (_) {
      // Best-effort — ignore
    }
  }

  Future<SecretKey> _deriveKeyFromPinWithIterations(
      String pin, Uint8List salt, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
  }

  /// Derives a 32-byte AES-256-GCM key from [secret] using Argon2id.
  ///
  /// Uses [WalletKdf] parameters: m=65536, t=3, p=1.
  /// The [secret] bytes are zeroed in memory after derivation.
  /// Returns a raw 32-byte key suitable for direct use with AES-256-GCM.
  ///
  /// **Runs on a background isolate via `compute()`** to avoid blocking the
  /// UI thread — pointycastle's pure-Dart Argon2id at m=65536 takes ~2-4s on
  /// a mid-range Android device, which would otherwise cause ANR dialogs.
  Future<Uint8List> _deriveKeyArgon2id(String secret, Uint8List salt) async {
    final result = await compute(
      _argon2idIsolateEntry,
      _Argon2Params(secret: secret, salt: salt),
    );
    return result;
  }

  /// Derives a key using Argon2id with an explicit [tCost] override.
  /// Used for the v3→v4 migration path where v3 backups must be decrypted
  /// with the old t=3 parameter before re-encrypting with the new t=1.
  Future<Uint8List> _deriveKeyArgon2idWithParams(
    String secret,
    Uint8List salt, {
    required int tCost,
  }) async {
    final result = await compute(
      _argon2idIsolateEntry,
      _Argon2Params(secret: secret, salt: salt, tCostOverride: tCost),
    );
    return result;
  }

  /// Public Argon2id key derivation for use by [RecoveryService].
  /// Callers are responsible for zeroing the returned bytes after use.
  Future<Uint8List> deriveKeyArgon2id(String secret, Uint8List salt) =>
      _deriveKeyArgon2id(secret, salt);

  /// Resets the wallet PIN using a keypair recovered during the forgot-PIN flow.
  ///
  /// This is the counterpart to [setupPinAndBackup]: instead of generating a
  /// fresh keypair, it re-encrypts the *recovered* keypair with the new PIN,
  /// submits it to the backend via the recovery endpoint, then persists locally
  /// and populates the session cache.
  ///
  /// The [recoveryToken] is the single-use JWT issued by `recovery_verify`.
  /// Zeroes all intermediate key material in `finally` blocks.
  Future<void> resetPinWithRecoveredKeypair({
    required String newPin,
    required Uint8List recoveredKeypair,
    required String recoveryToken,
  }) async {
    // Read the existing Wallet_Salt so the keypair stays bound to it
    final salt = await readSalt();

    // Derive new_PINKey = Argon2id(newPIN, Wallet_Salt)
    final rawKey = await _deriveKeyArgon2id(newPin, salt);

    try {
      final secretKey = SecretKey(rawKey);
      final (newCiphertext, newNonce) =
          await _encryptAesGcm(recoveredKeypair, secretKey);

      // Build the 112-byte unified payload: salt(32) || ciphertext+tag(80)
      final backupPayload = _buildBackupPayload(salt, newNonce, newCiphertext);
      final encB64 = base64Encode(backupPayload);
      final nonceB64 = base64Encode(newNonce);

      // Submit to backend
      await _apiClient.recoveryResetPin(
        recoveryToken: recoveryToken,
        encryptedKeypair: encB64,
        nonce: nonceB64,
      );

      // Persist new encryption locally
      await _secureStorage.write(
        key: _encryptedPrivateKeyKey,
        value: base64Encode(newCiphertext),
      );
      await _secureStorage.write(
        key: _pinSaltKey,
        value: base64Encode(salt),
      );
      await _secureStorage.write(
        key: _encryptionNonceKey,
        value: base64Encode(newNonce),
      );
      await _secureStorage.write(key: _kdfVersionKey, value: '4');
      await _secureStorage.write(key: _pinLengthKey, value: '6');

      // Populate the session cache so subsequent sends work without re-unlock
      WalletSessionCache.instance.store(recoveredKeypair);
    } finally {
      for (var i = 0; i < rawKey.length; i++) { rawKey[i] = 0; }
    }
  }

  Future<(Uint8List, Uint8List)> _encryptAesGcm(
    Uint8List plaintext,
    SecretKey key,
  ) async {
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce(); // 12 bytes
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );
    return (
      Uint8List.fromList(secretBox.concatenation(nonce: false)),
      Uint8List.fromList(nonce),
    );
  }

  Future<Uint8List> _decryptAesGcm(
    Uint8List ciphertext,
    Uint8List nonce,
    SecretKey key,
  ) async {
    final algorithm = AesGcm.with256bits();
    const macLength = 16;
    final encryptedData =
        ciphertext.sublist(0, ciphertext.length - macLength);
    final mac = Mac(ciphertext.sublist(ciphertext.length - macLength));
    final secretBox = SecretBox(encryptedData, nonce: nonce, mac: mac);
    final plaintext = await algorithm.decrypt(secretBox, secretKey: key);
    return Uint8List.fromList(plaintext);
  }

  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  Uint8List _buildBackupPayload(
    Uint8List salt,
    Uint8List nonce,
    Uint8List ciphertext,
  ) {
    final payload = Uint8List(salt.length + ciphertext.length);
    payload.setAll(0, salt);
    payload.setAll(salt.length, ciphertext);
    return payload;
  }

  (Uint8List, Uint8List) _parseBackupPayload(Uint8List payload) {
    final salt = Uint8List.fromList(payload.sublist(0, 32));
    final ciphertext = Uint8List.fromList(payload.sublist(32));
    return (salt, ciphertext);
  }

  // ── Session-signing variants ───────────────────────────────────────────────
  //
  // These accept a raw keypair bytes from [WalletSessionCache] instead of a PIN,
  // enabling zero-friction sends when the session is active. The keypair bytes
  // are zeroed in memory before returning, regardless of outcome.

  /// Build and sign a USDC transfer using a cached keypair instead of a PIN.
  ///
  /// Mirrors [buildAndSignTransaction] but accepts [keypairBytes] from the
  /// session cache. The caller is responsible for providing a valid keypair.
  Future<String> buildAndSignTransactionFromCache({
    required Uint8List keypairBytes,
    required double amountUsdc,
    required String recipientAddress,
    required String blockhash,
    required String feePayerAddress,
    String? senderAtaOverride,
    String? recipientAtaOverride,
  }) async {
    final keyCopy = Uint8List.fromList(keypairBytes);
    try {
      final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: _extractSeed(keyCopy).toList(),
      );

      final senderPubkey = Ed25519HDPublicKey.fromBase58(keypair.address);
      final recipientPubkey = Ed25519HDPublicKey.fromBase58(recipientAddress);
      final usdcMint = Ed25519HDPublicKey.fromBase58(_usdcMintAddress);

      // Use server-provided ATAs when available — authoritative from the DB.
      final senderAta = senderAtaOverride != null
          ? Ed25519HDPublicKey.fromBase58(senderAtaOverride)
          : await findAssociatedTokenAddress(owner: senderPubkey, mint: usdcMint);
      final recipientAta = recipientAtaOverride != null
          ? Ed25519HDPublicKey.fromBase58(recipientAtaOverride)
          : await findAssociatedTokenAddress(owner: recipientPubkey, mint: usdcMint);

      final amountTokens = (amountUsdc * 1000000).round();
      final transferInstruction = TokenInstruction.transfer(
        source: senderAta,
        destination: recipientAta,
        owner: senderPubkey,
        amount: amountTokens,
      );

      final feePayer = Ed25519HDPublicKey.fromBase58(feePayerAddress);
      final message = Message(instructions: [transferInstruction]);
      final compiledMessage = message.compile(
        recentBlockhash: blockhash,
        feePayer: feePayer,
      );

      final signature = await keypair.sign(compiledMessage.toByteArray());
      final signedTx = SignedTx(
        compiledMessage: compiledMessage,
        signatures: [
          Signature(List.filled(64, 0), publicKey: feePayer),
          Signature(signature.bytes, publicKey: senderPubkey),
        ],
      );

      return base64Encode(signedTx.toByteArray().toList());
    } finally {
      for (var i = 0; i < keyCopy.length; i++) { keyCopy[i] = 0; }
    }
  }

  /// Build and sign a USDC transfer to a Solana wallet address (bank/bridge)
  /// using a cached keypair instead of a PIN.
  ///
  /// Mirrors [buildAndSignTransactionToAddress] but accepts [keypairBytes].
  Future<String> buildAndSignTransactionToAddressFromCache({
    required Uint8List keypairBytes,
    required double amountUsdc,
    required String destinationAddress,
    required String blockhash,
    required String feePayerAddress,
  }) async {
    final keyCopy = Uint8List.fromList(keypairBytes);
    try {
      final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: _extractSeed(keyCopy).toList(),
      );

      final senderPubkey = Ed25519HDPublicKey.fromBase58(keypair.address);
      final destinationPubkey =
          Ed25519HDPublicKey.fromBase58(destinationAddress);
      final usdcMint = Ed25519HDPublicKey.fromBase58(_usdcMintAddress);

      final senderAta = await findAssociatedTokenAddress(
        owner: senderPubkey,
        mint: usdcMint,
      );
      final destinationAta = await findAssociatedTokenAddress(
        owner: destinationPubkey,
        mint: usdcMint,
      );

      final amountTokens = (amountUsdc * 1000000).round();
      final transferInstruction = TokenInstruction.transfer(
        source: senderAta,
        destination: destinationAta,
        owner: senderPubkey,
        amount: amountTokens,
      );

      final feePayer = Ed25519HDPublicKey.fromBase58(feePayerAddress);
      final message = Message(instructions: [transferInstruction]);
      final compiledMessage = message.compile(
        recentBlockhash: blockhash,
        feePayer: feePayer,
      );

      final signature = await keypair.sign(compiledMessage.toByteArray());
      final signedTx = SignedTx(
        compiledMessage: compiledMessage,
        signatures: [
          Signature(List.filled(64, 0), publicKey: feePayer),
          Signature(signature.bytes, publicKey: senderPubkey),
        ],
      );

      return base64Encode(signedTx.toByteArray().toList());
    } finally {
      for (var i = 0; i < keyCopy.length; i++) { keyCopy[i] = 0; }
    }
  }

  /// Signs a pre-built versioned transaction using a cached keypair
  /// instead of a PIN. Mirrors [signExistingTransaction] but accepts
  /// [keypairBytes] from the session cache.
  Future<String> signExistingTransactionFromCache({
    required Uint8List keypairBytes,
    required String txBytesB64,
  }) async {
    final keyCopy = Uint8List.fromList(keypairBytes);
    try {
      final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: _extractSeed(keyCopy).toList(),
      );

      final txBytes = base64Decode(txBytesB64);
      final numSigsResult = _readCompactU16(Uint8List.fromList(txBytes), 0);
      final numSigs = numSigsResult.value;
      final sigsSectionStart = numSigsResult.bytesConsumed;
      final messageStart = sigsSectionStart + numSigs * 64;
      final messageBytes = Uint8List.fromList(txBytes.sublist(messageStart));

      final signature = await keypair.sign(messageBytes);
      final userPubkeyBytes = keypair.publicKey.bytes;
      final sigSlot = _findPubkeySlotInMessage(messageBytes, userPubkeyBytes);

      final result = Uint8List.fromList(txBytes);
      final slotOffset = sigsSectionStart + sigSlot * 64;
      result.setRange(slotOffset, slotOffset + 64, signature.bytes);

      return base64Encode(result);
    } finally {
      for (var i = 0; i < keyCopy.length; i++) { keyCopy[i] = 0; }
    }
  }
}
