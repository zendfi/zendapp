import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:solana/base58.dart';

import '../models/email_intent.dart';
import 'api_client.dart';
import 'wallet_service.dart';

/// Handles creation, listing, and cancellation of email intents.
///
/// For intent creation the service:
/// 1. Decrypts the sender's wallet keypair using their PIN
/// 2. Generates a fresh ephemeral Ed25519 keypair (ek_pub / ek_priv)
/// 3. Signs the intent payload with the sender's wallet key
/// 4. Encrypts (sig + payload) with ek_pub using X25519 ECDH + AES-256-GCM
/// 5. Constructs the claim link with ek_priv embedded
/// 6. POSTs to the backend (ek_priv is zeroed immediately after)
class EmailIntentService {
  final ApiClient _apiClient;
  final WalletService _walletService;

  EmailIntentService({
    required ApiClient apiClient,
    required WalletService walletService,
  })  : _apiClient = apiClient,
        _walletService = walletService;

  /// Creates an email intent.
  ///
  /// Returns a [CreateIntentResult] on success.
  /// Throws [PinDecryptionException] if the PIN is wrong.
  Future<CreateIntentResult> createIntent({
    required String recipientEmail,
    required double amountUsdc,
    required String pin,
    String? note,
  }) async {
    // Step 1: Fetch the fee payer pubkey from the backend
    final delegationParams = await _apiClient.getDelegationParams();
    final feePayerPubkeyB58 = delegationParams['fee_payer'] as String;

    // Step 2: Decrypt the sender's wallet keypair
    final senderKeypairBytes = await _walletService.decryptLocalKeypair(pin);

    // Step 3: Generate a fresh ephemeral Ed25519 keypair (ek_pub / ek_priv)
    final algorithm = Ed25519();
    final ekKeypair = await algorithm.newKeyPair();
    final ekPub = await ekKeypair.extractPublicKey();
    final ekPrivBytes = Uint8List.fromList(
      (await ekKeypair.extract()).bytes,
    );

    try {
      // Step 4: Build and submit the on-chain SPL Approve transaction
      // This grants the fee payer delegate authority over amountUsdc of
      // the sender's USDC ATA. Daniel's tokens stay in his wallet.
      final approveTxSig = await _walletService.buildAndSubmitSplApprove(
        senderKeypairBytes: senderKeypairBytes,
        feePayerPubkeyB58: feePayerPubkeyB58,
        amountUsdc: amountUsdc,
        pin: pin,
      );

      // Step 5: The encrypted_delegation stores proof the approve was submitted.
      // We encrypt the approve tx signature + intent metadata with ek_pub so
      // only the recipient (who has ek_priv) can verify it.
      final intentPayload = utf8.encode(
        '{"approve_tx":"$approveTxSig","recipient_email":"$recipientEmail","amount_usdc":$amountUsdc}',
      );
      final encryptedDelegation = await _encryptWithEkPub(
        plaintext: Uint8List.fromList(intentPayload),
        ekPubBytes: Uint8List.fromList(ekPub.bytes),
      );

      // Step 6: Encode ek_pub and ek_priv as base58
      final ekPubB58 = base58encode(ekPub.bytes);
      final ekPrivB58 = base58encode(ekPrivBytes);

      // Step 7: Call create_intent — backend substitutes PENDING_ID with real intent_id
      final result = await _apiClient.createEmailIntent(
        recipientEmail: recipientEmail,
        amountUsdc: amountUsdc,
        encryptedDelegation: encryptedDelegation,
        ekPub: ekPubB58,
        ekPrivForLink: ekPrivB58,
        note: note,
      );

      return result;
    } finally {
      // Zero sensitive bytes regardless of success or failure
      for (var i = 0; i < ekPrivBytes.length; i++) {
        ekPrivBytes[i] = 0;
      }
      for (var i = 0; i < senderKeypairBytes.length; i++) {
        senderKeypairBytes[i] = 0;
      }
    }
  }

  /// Returns the list of email intents created by the current user.
  Future<List<EmailIntent>> listIntents() async {
    return _apiClient.listEmailIntents();
  }

  /// Cancels a pending email intent.
  Future<void> cancelIntent(String intentId) async {
    return _apiClient.cancelEmailIntent(intentId);
  }

  // ── Encryption helpers ────────────────────────────────────────────────────

  /// Encrypts [plaintext] using X25519 ECDH key agreement with [ekPubBytes]
  /// (the recipient's ephemeral public key) and AES-256-GCM.
  ///
  /// Returns base64-encoded `[ephemeral_pub_bytes(32)] + [nonce(12)] + [ciphertext+tag]`.
  Future<String> _encryptWithEkPub({
    required Uint8List plaintext,
    required Uint8List ekPubBytes,
  }) async {
    // Generate a one-time X25519 sender ephemeral keypair
    final x25519 = X25519();
    final senderEphemeral = await x25519.newKeyPair();
    final senderEphemeralPub = await senderEphemeral.extractPublicKey();

    // ECDH: shared secret between sender ephemeral and recipient ek_pub
    final recipientPub = SimplePublicKey(ekPubBytes, type: KeyPairType.x25519);
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: senderEphemeral,
      remotePublicKey: recipientPub,
    );

    // Derive AES-256 key from shared secret using HKDF-SHA256
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );
    final aesKey = await hkdf.deriveKey(
      secretKey: sharedSecret,
      info: 'zend-email-intent-encryption'.codeUnits,
      nonce: [],
    );

    // Encrypt with AES-256-GCM
    final aesGcm = AesGcm.with256bits();
    final nonce = aesGcm.newNonce();
    final secretBox = await aesGcm.encrypt(
      plaintext,
      secretKey: aesKey,
      nonce: nonce,
    );

    // Pack: [sender_ephemeral_pub(32)] + [nonce(12)] + [ciphertext+tag]
    final senderPubBytes = Uint8List.fromList(senderEphemeralPub.bytes);
    final nonceBytes = Uint8List.fromList(nonce);
    final ciphertextBytes =
        Uint8List.fromList(secretBox.concatenation(nonce: false));

    final packed = Uint8List(
        senderPubBytes.length + nonceBytes.length + ciphertextBytes.length)
      ..setRange(0, senderPubBytes.length, senderPubBytes)
      ..setRange(senderPubBytes.length,
          senderPubBytes.length + nonceBytes.length, nonceBytes)
      ..setRange(
          senderPubBytes.length + nonceBytes.length,
          senderPubBytes.length + nonceBytes.length + ciphertextBytes.length,
          ciphertextBytes);

    return base64.encode(packed);
  }
}
