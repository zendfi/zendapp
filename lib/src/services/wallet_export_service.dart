import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;

import '../models/api_exceptions.dart';
import 'wallet_kdf.dart';
import 'wallet_service.dart';

/// Handles wallet export operations — encrypted JSON backup and BIP-39 mnemonic.
///
/// All operations require PIN re-entry to prevent unauthorized export
/// from an unlocked device.
class WalletExportService {
  final WalletService _wallet;

  WalletExportService(this._wallet);

  /// Verifies the PIN and generates an encrypted backup JSON string.
  ///
  /// The returned JSON has exactly these fields:
  /// ```json
  /// {
  ///   "version": 3,
  ///   "kdf": { "algorithm": "argon2id", "m_cost": 65536, "t_cost": 3, "p_cost": 1 },
  ///   "salt": "<base64>",
  ///   "nonce": "<base64>",
  ///   "ciphertext": "<base64>"
  /// }
  /// ```
  ///
  /// Throws [PinDecryptionException] if the PIN is wrong.
  /// Throws [StateError] if local wallet data is missing.
  Future<String> exportEncryptedBackup(String pin) async {
    // Verify PIN — throws PinDecryptionException if wrong
    await _wallet.verifyLocalPin(pin);

    // Read current encrypted material from secure storage
    final salt = await _wallet.readSalt();
    final nonce = await _wallet.readNonce();
    final ciphertext = await _wallet.readCiphertext();

    return jsonEncode({
      'version': WalletKdf.encryptionVersion,
      'kdf': WalletKdf.paramsJson,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(ciphertext),
    });
  }

  /// Generates the filename for an exported backup.
  ///
  /// Format: `zend-wallet-backup-YYYY-MM-DD.json` (UTC date).
  static String exportFilename() {
    final now = DateTime.now().toUtc();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return 'zend-wallet-backup-$date.json';
  }

  /// Verifies the PIN and derives the 12-word BIP-39 mnemonic from the wallet seed.
  ///
  /// The mnemonic is derived from the first 32 bytes of the 64-byte keypair
  /// (the Ed25519 seed). The keypair bytes are zeroed immediately after
  /// mnemonic derivation.
  ///
  /// Returns a list of 12 words.
  /// Throws [PinDecryptionException] if the PIN is wrong.
  Future<List<String>> exportMnemonic(String pin) async {
    // Decrypt keypair — throws PinDecryptionException if wrong
    final keypair = await _wallet.decryptLocalKeypair(pin);

    try {
      // Ed25519 keypair: seed(32) || pubkey(32)
      // BIP-39 entropy source is the 32-byte seed
      final seed = Uint8List.fromList(keypair.sublist(0, 32));

      // entropyToMnemonic expects a hex string of entropy bytes.
      // Standard BIP-39 uses 128 bits (16 bytes) for a 12-word mnemonic.
      // We use the first 16 bytes of the 32-byte seed as the entropy source.
      final entropy16Hex =
          seed.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final mnemonic = bip39.entropyToMnemonic(entropy16Hex);
      return mnemonic.split(' ');
    } finally {
      // Zero the keypair bytes regardless of outcome — never leave them in memory
      for (var i = 0; i < keypair.length; i++) {
        keypair[i] = 0;
      }
    }
  }
}
