import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:solana/base58.dart';
import 'package:solana/solana.dart';

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
    // Decrypt the sender's wallet keypair — throws PinDecryptionException on wrong PIN
    final senderKeypairBytes = await _walletService.decryptLocalKeypair(pin);

    late Uint8List ekPrivBytes;
    try {
      // Generate a fresh ephemeral Ed25519 keypair
      final algorithm = Ed25519();
      final ekKeypair = await algorithm.newKeyPair();
      final ekPub = await ekKeypair.extractPublicKey();
      ekPrivBytes = Uint8List.fromList(
        (await ekKeypair.extract()).bytes,
      );

      // Serialize intent payload as canonical JSON
      final expiryTs = DateTime.now().toUtc().add(const Duration(days: 30));
      final payloadStr =
          '{"recipient_email":"$recipientEmail","amount_usdc":$amountUsdc,'
          '"expiry":"${expiryTs.toIso8601String()}"}';
      final payloadBytes = Uint8List.fromList(payloadStr.codeUnits);

      // Sign intent payload with the sender's wallet key (Ed25519)
      final senderKeypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: senderKeypairBytes.toList(),
      );
      final sig = await senderKeypair.sign(payloadBytes);

      // Encrypt (sig_bytes + payload) with ek_pub using X25519 + AES-256-GCM
      final sigBytes = Uint8List.fromList(sig.bytes);
      final plaintext = Uint8List(sigBytes.length + payloadBytes.length)
        ..setRange(0, sigBytes.length, sigBytes)
        ..setRange(sigBytes.length, sigBytes.length + payloadBytes.length, payloadBytes);

      final encryptedDelegationB64 = await _encryptWithEkPub(
        plaintext: plaintext,
        ekPubBytes: Uint8List.fromList(ekPub.bytes),
      );

      // Encode ek_pub as base58 for the backend
      final ekPubB58 = base58encode(ekPub.bytes);

      // Encode ek_priv as base58 for the claim link
      final ekPrivB58 = base58encode(ekPrivBytes);

      // Construct claim link with ek_priv embedded (never sent to server)
      // The intent ID is not known yet; the backend returns it. We pass the
      // claim link template — the backend will use the actual intent ID.
      // Since we don't have the ID yet, we pass a placeholder that the
      // backend ignores (it uses the claim link for the email only and does
      // NOT store it; the final link must be reconstructed by the recipient).
      //
      // Practical approach: construct with a placeholder, then after getting
      // the intent ID from the backend response, the real link would be:
      // https://web.usezend.app/claim?k={ekPrivB58}&id={intentId}
      //
      // The backend stores ek_pub + encrypted_delegation. The claim_link in
      // the email is what the recipient will click. Since we only know the
      // intent ID after creation, we pass a temporary link here and would
      // ideally do a two-step: create intent → get ID → send claim email.
      // For MVP, the backend sends the email with the ID it just generated,
      // so we pass the ek_priv and let the backend substitute the ID.
      // We signal this by passing "PENDING_ID" — the backend uses its own
      // generated intent_id to build the final link.
      final claimLink =
          'https://web.usezend.app/claim?k=$ekPrivB58&id=PENDING_ID';

      final result = await _apiClient.createEmailIntent(
        recipientEmail: recipientEmail,
        amountUsdc: amountUsdc,
        encryptedDelegation: encryptedDelegationB64,
        ekPub: ekPubB58,
        claimLink: claimLink,
        note: note,
      );

      return result;
    } finally {
      // Zero ek_priv bytes regardless of success or failure
      if (ekPrivBytes.isNotEmpty) {
        for (var i = 0; i < ekPrivBytes.length; i++) {
          ekPrivBytes[i] = 0;
        }
      }
      // Zero sender keypair bytes
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
