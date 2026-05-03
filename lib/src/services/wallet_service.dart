import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';

import 'api_client.dart';
import '../models/api_exceptions.dart';

class WalletService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _secureStorage;

  static const _encryptedPrivateKeyKey = 'zend_wallet_encrypted_private_key';
  static const _publicKeyKey = 'zend_wallet_public_key';
  static const _pinSaltKey = 'zend_pin_salt';
  static const _encryptionNonceKey = 'zend_encryption_nonce';

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

    await _secureStorage.write(
      key: _encryptedPrivateKeyKey,
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
    final rawKeyB64 = await _secureStorage.read(key: _encryptedPrivateKeyKey);
    if (rawKeyB64 == null) {
      throw StateError('No keypair found. Call generateKeypair first.');
    }
    final privateKeyBytes = base64Decode(rawKeyB64);

    final salt = _generateRandomBytes(32);

    final derivedKey = await _deriveKeyFromPin(pin, salt);

    final (ciphertext, nonce) = await _encryptAesGcm(privateKeyBytes, derivedKey);

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
  }

  Future<void> restoreFromBackup(String pin) async {
    final backup = await _apiClient.retrieveBackup();

    final backupBytes = base64Decode(backup.encryptedKeypair);
    final nonceBytes = base64Decode(backup.nonce);

    final (salt, ciphertext) = _parseBackupPayload(backupBytes);

    final derivedKey = await _deriveKeyFromPin(pin, salt);

    Uint8List privateKeyBytes;
    try {
      privateKeyBytes = await _decryptAesGcm(ciphertext, nonceBytes, derivedKey);
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

    for (var i = 0; i < privateKeyBytes.length; i++) {
      privateKeyBytes[i] = 0;
    }
  }

  Future<void> changePin(String currentPin, String newPin) async {
    final privateKeyBytes = await _decryptLocalKeypair(currentPin);

    final newSalt = _generateRandomBytes(32);
    final newDerivedKey = await _deriveKeyFromPin(newPin, newSalt);
    final (newCiphertext, newNonce) =
        await _encryptAesGcm(privateKeyBytes, newDerivedKey);

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

    for (var i = 0; i < privateKeyBytes.length; i++) {
      privateKeyBytes[i] = 0;
    }
  }

  Future<String> getBalance() async {
    final response = await _apiClient.getBalance();
    return response.usdcBalance;
  }

  Future<String> buildAndSignTransaction({
    required String pin,
    required double amountUsdc,
    required String recipientAddress,
    required String blockhash,
    required String feePayerAddress,
  }) async {
    final privateKeyBytes = await _decryptLocalKeypair(pin);

    try {
      final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: privateKeyBytes.toList(),
      );

      final senderPubkey = Ed25519HDPublicKey.fromBase58(keypair.address);
      final recipientPubkey = Ed25519HDPublicKey.fromBase58(recipientAddress);
      final usdcMint = Ed25519HDPublicKey.fromBase58(_usdcMintAddress);

      final senderAta = await findAssociatedTokenAddress(
        owner: senderPubkey,
        mint: usdcMint,
      );
      final recipientAta = await findAssociatedTokenAddress(
        owner: recipientPubkey,
        mint: usdcMint,
      );

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

  Future<void> clearWalletData() async {
    await _secureStorage.delete(key: _encryptedPrivateKeyKey);
    await _secureStorage.delete(key: _publicKeyKey);
    await _secureStorage.delete(key: _pinSaltKey);
    await _secureStorage.delete(key: _encryptionNonceKey);
  }

  Future<Uint8List> _decryptLocalKeypair(String pin) async {
    final encryptedB64 =
        await _secureStorage.read(key: _encryptedPrivateKeyKey);
    final saltB64 = await _secureStorage.read(key: _pinSaltKey);
    final nonceB64 = await _secureStorage.read(key: _encryptionNonceKey);

    if (encryptedB64 == null || saltB64 == null || nonceB64 == null) {
      throw StateError('No encrypted keypair found in secure storage.');
    }

    final ciphertext = base64Decode(encryptedB64);
    final salt = base64Decode(saltB64);
    final nonce = base64Decode(nonceB64);

    final derivedKey =
        await _deriveKeyFromPin(pin, Uint8List.fromList(salt));

    try {
      return await _decryptAesGcm(
        Uint8List.fromList(ciphertext),
        Uint8List.fromList(nonce),
        derivedKey,
      );
    } catch (_) {
      throw PinDecryptionException();
    }
  }

  Future<SecretKey> _deriveKeyFromPin(String pin, Uint8List salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
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
}
