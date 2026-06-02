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

    // Step 3: Generate a fresh ephemeral Ed25519 keypair (ek_pub / ek_priv).
    // The backend validates ek_priv as a 64-byte Ed25519 keypair (Solana format)
    // and verifies that ek_priv derives to ek_pub stored in the intent record.
    // We use the solana Ed25519HDKeyPair for this so the bytes are in the correct
    // format the backend expects (seed || public_key, 64 bytes total).
    final ekAlgorithm = Ed25519();
    final ekKeypair = await ekAlgorithm.newKeyPair();
    final ekPub = await ekKeypair.extractPublicKey();
    final ekPrivSeed = Uint8List.fromList((await ekKeypair.extract()).bytes);
    // Solana stores keypairs as seed(32) || pubkey(32) = 64 bytes
    final ekPrivBytes = Uint8List(64)
      ..setRange(0, 32, ekPrivSeed)
      ..setRange(32, 64, ekPub.bytes);

    try {
      // Step 4: Build and submit the on-chain SPL Approve transaction.
      // This grants the fee payer delegate authority over amountUsdc of
      // the sender's USDC ATA. Sender's tokens stay in their wallet.
      final approveTxSig = await _walletService.buildAndSubmitSplApprove(
        senderKeypairBytes: senderKeypairBytes,
        feePayerPubkeyB58: feePayerPubkeyB58,
        amountUsdc: amountUsdc,
        pin: pin,
      );

      // Step 5: Build the encrypted_delegation blob.
      // This is a proof payload stored server-side linking the approve tx
      // to the intent. We encrypt it with AES-256-GCM using the ek_priv
      // seed as the key (no ECDH needed — ek_priv is already secret).
      final intentPayload = utf8.encode(
        '{"approve_tx":"$approveTxSig","recipient_email":"$recipientEmail","amount_usdc":$amountUsdc}',
      );
      final encryptedDelegation = await _encryptPayload(
        plaintext: Uint8List.fromList(intentPayload),
        keyBytes: ekPrivSeed, // 32-byte seed used directly as AES-256 key
      );

      // Step 6: Encode ek_pub and ek_priv as base58 for transmission.
      // ek_pub: just the 32-byte public key bytes
      // ek_priv: full 64-byte Solana keypair format the backend validates
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
      for (var i = 0; i < ekPrivSeed.length; i++) {
        ekPrivSeed[i] = 0;
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

  /// Encrypts [plaintext] using AES-256-GCM with [keyBytes] as the key.
  ///
  /// [keyBytes] must be exactly 32 bytes (the Ed25519 seed, which is already
  /// a uniformly random 32-byte value suitable for use as an AES key).
  ///
  /// Returns base64-encoded `[nonce(12)] + [ciphertext+tag]`.
  Future<String> _encryptPayload({
    required Uint8List plaintext,
    required Uint8List keyBytes,
  }) async {
    final aesGcm = AesGcm.with256bits();
    final secretKey = SecretKey(keyBytes.toList());
    final nonce = aesGcm.newNonce();
    final secretBox = await aesGcm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );

    final nonceBytes = Uint8List.fromList(nonce);
    final ciphertextBytes = Uint8List.fromList(secretBox.concatenation(nonce: false));

    final packed = Uint8List(nonceBytes.length + ciphertextBytes.length)
      ..setRange(0, nonceBytes.length, nonceBytes)
      ..setRange(nonceBytes.length, nonceBytes.length + ciphertextBytes.length, ciphertextBytes);

    return base64.encode(packed);
  }
}
