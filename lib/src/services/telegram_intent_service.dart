// Telegram pending intent service for the native Zend app.
//
// Mirrors EmailIntentService exactly in its delegation mechanics:
// - Generates a fresh ephemeral Ed25519 keypair (ek_pub / ek_priv) per intent
// - Approves ek_pub (NOT fee_payer) as the on-chain SPL delegate
// - ek_priv is embedded in the claim_link returned by the backend
// - The backend never holds ek_priv — only the claim link recipient does
//
// This means a compromised backend cannot move funds from any pending TG
// intent without the ek_priv that only the claim link holder has.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:solana/base58.dart';

import '../models/email_intent.dart';
import 'api_client.dart';
import 'wallet_service.dart';

class TelegramIntentService {
  final ApiClient _apiClient;
  final WalletService _walletService;

  TelegramIntentService({
    required ApiClient apiClient,
    required WalletService walletService,
  })  : _apiClient = apiClient,
        _walletService = walletService;

  /// Creates a Telegram pending intent.
  ///
  /// [recipientTgUsername] — Telegram @username without the @.
  /// Returns a [CreateIntentResult] on success.
  /// Throws [PinDecryptionException] if the PIN is wrong.
  ///
  /// Exactly one of [pin] or [keypairBytes] must be provided.
  Future<CreateIntentResult> createIntent({
    required String recipientTgUsername,
    required double amountUsdc,
    String? pin,
    Uint8List? keypairBytes,
    String? note,
  }) async {
    assert(
      (pin != null) ^ (keypairBytes != null),
      'Exactly one of pin or keypairBytes must be provided',
    );

    // Step 1: Generate a fresh ephemeral Ed25519 keypair for this intent.
    // ek_pub becomes the on-chain SPL delegate.
    // ek_priv goes into the claim link — the backend never stores or sees it.
    final ekAlgorithm = Ed25519();
    final ekKeypair = await ekAlgorithm.newKeyPair();
    final ekPub = await ekKeypair.extractPublicKey();
    final ekPrivSeed = Uint8List.fromList((await ekKeypair.extract()).bytes);
    // 64-byte keypair: seed(32) || pubkey(32)
    final ekPrivBytes = Uint8List(64)
      ..setRange(0, 32, ekPrivSeed)
      ..setRange(32, 64, ekPub.bytes);

    // Step 2: Get the sender's wallet keypair.
    final senderKeypairBytes = keypairBytes != null
        ? Uint8List.fromList(keypairBytes)
        : await _walletService.decryptLocalKeypair(pin!);

    try {
      // Step 3: Submit SPL Approve, designating ek_pub as the delegate.
      // fee_payer is gas-only — it has no SPL authority over sender_ata.
      await _walletService.buildAndSubmitSplApprove(
        senderKeypairBytes: senderKeypairBytes,
        delegatePubkeyB58: base58encode(ekPub.bytes), // ek_pub is the delegate
        amountUsdc: amountUsdc,
        pin: pin ?? '',
      );

      // Step 4: Build the encrypted delegation blob (same as email intent).
      // Encrypted with ek_priv seed so the backend can verify ek_pub ownership
      // at claim time without ever having seen ek_priv.
      final intentPayload = utf8.encode(
        '{"recipient_tg":"$recipientTgUsername","amount_usdc":$amountUsdc}',
      );
      final encryptedDelegation = await _encryptPayload(
        plaintext: Uint8List.fromList(intentPayload),
        keyBytes: ekPrivSeed,
      );

      final ekPubB58 = base58encode(ekPub.bytes);
      // ek_priv is passed to the backend ONLY so it can embed it in the
      // Telegram bot notification URL. The backend must not log or store it.
      final ekPrivB58 = base58encode(ekPrivBytes);

      // Step 5: Create the intent on the backend.
      final result = await _apiClient.createTelegramIntent(
        recipientTgUsername: recipientTgUsername,
        amountUsdc: amountUsdc,
        encryptedDelegation: encryptedDelegation,
        ekPub: ekPubB58,
        ekPrivForLink: ekPrivB58,
        note: note,
      );

      // The backend embeds ek_priv in the claim_link it returns and sends
      // to the recipient via the bot. Surface the claim_link to the sender
      // so they can share it manually if the bot notification fails.
      return CreateIntentResult(
        id: result['id'] as String,
        amountUsdc: amountUsdc,
        expiry: DateTime.parse(result['expiry'] as String),
        status: result['status'] as String? ?? 'pending',
        recipientHint: '@$recipientTgUsername',
        claimLink: result['claim_link'] as String?,
      );
    } finally {
      // Zero all key material regardless of success or failure.
      for (var i = 0; i < ekPrivBytes.length; i++) { ekPrivBytes[i] = 0; }
      for (var i = 0; i < ekPrivSeed.length; i++) { ekPrivSeed[i] = 0; }
      for (var i = 0; i < senderKeypairBytes.length; i++) { senderKeypairBytes[i] = 0; }
    }
  }

  /// Encrypts [plaintext] using AES-256-GCM with [keyBytes] as the key.
  /// Returns base64-encoded [nonce(12)] + [ciphertext+tag].
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
    final ciphertextBytes =
        Uint8List.fromList(secretBox.concatenation(nonce: false));
    final packed =
        Uint8List(nonceBytes.length + ciphertextBytes.length)
          ..setRange(0, nonceBytes.length, nonceBytes)
          ..setRange(nonceBytes.length,
              nonceBytes.length + ciphertextBytes.length, ciphertextBytes);
    return base64.encode(packed);
  }
}
