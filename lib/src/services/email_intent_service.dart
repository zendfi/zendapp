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
  ///
  /// Exactly one of [pin] or [keypairBytes] must be provided:
  /// - [pin]: standard PIN path — decrypts the keypair on-device.
  /// - [keypairBytes]: session-signing path — uses a pre-decrypted keypair
  ///   from [WalletSessionCache]. Bytes are zeroed inside this method.
  Future<CreateIntentResult> createIntent({
    required String recipientEmail,
    required double amountUsdc,
    String? pin,
    Uint8List? keypairBytes,
    String? note,
  }) async {
    assert(
      (pin != null) ^ (keypairBytes != null),
      'Exactly one of pin or keypairBytes must be provided',
    );

    // Step 1: Fetch blockhash for the approve tx. fee_payer from params is the
    // gas payer; the SPL delegate will be ek_pub generated below.
    await _apiClient.getDelegationParams();
    // delegationParams['fee_payer'] is used server-side; we don't need it here.

    // Step 2: Get the sender's wallet keypair (either decrypt or copy from cache)
    final senderKeypairBytes = keypairBytes != null
        ? Uint8List.fromList(keypairBytes) // defensive copy — zeroed in finally
        : await _walletService.decryptLocalKeypair(pin!);

    // Step 3: Generate a fresh ephemeral Ed25519 keypair (ek_pub / ek_priv).
    final ekAlgorithm = Ed25519();
    final ekKeypair = await ekAlgorithm.newKeyPair();
    final ekPub = await ekKeypair.extractPublicKey();
    final ekPrivSeed = Uint8List.fromList((await ekKeypair.extract()).bytes);
    final ekPrivBytes = Uint8List(64)
      ..setRange(0, 32, ekPrivSeed)
      ..setRange(32, 64, ekPub.bytes);

    try {
      // Step 4: Build and submit the on-chain SPL Approve transaction.
      // SECURITY: approve ek_pub (the per-intent ephemeral key) as the SPL delegate,
      // NOT fee_payer. This means:
      // - The backend (fee_payer) can pay gas but cannot move tokens unilaterally.
      // - Only whoever holds ek_priv (the claim link recipient) can execute the transfer.
      // - A compromised backend cannot sweep any pending intent's funds.
      final approveTxSig = await _walletService.buildAndSubmitSplApprove(
        senderKeypairBytes: senderKeypairBytes,
        delegatePubkeyB58: base58encode(ekPub.bytes), // ek_pub is the SPL delegate
        amountUsdc: amountUsdc,
        pin: pin ?? '',
      );

      // Step 5: Build the encrypted_delegation blob.
      final intentPayload = utf8.encode(
        '{"approve_tx":"$approveTxSig","recipient_email":"$recipientEmail","amount_usdc":$amountUsdc}',
      );
      final encryptedDelegation = await _encryptPayload(
        plaintext: Uint8List.fromList(intentPayload),
        keyBytes: ekPrivSeed,
      );

      // Step 6: Encode ek_pub and ek_priv as base58.
      final ekPubB58 = base58encode(ekPub.bytes);
      final ekPrivB58 = base58encode(ekPrivBytes);

      // Step 7: Call create_intent
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
      for (var i = 0; i < ekPrivBytes.length; i++) { ekPrivBytes[i] = 0; }
      for (var i = 0; i < ekPrivSeed.length; i++) { ekPrivSeed[i] = 0; }
      for (var i = 0; i < senderKeypairBytes.length; i++) { senderKeypairBytes[i] = 0; }
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
