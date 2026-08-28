import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/digests/blake2b.dart';

/// Client-side Sui signing for zkLogin sessions.
///
/// This holds the only secret operation in the Sui flow: the ephemeral private
/// key lives here and never leaves the device. The backend assembles the
/// zkLogin signature from the resulting public signature plus the proof, so no
/// BCS authenticator encoding is duplicated across Dart clients.
///
/// Deliberately absent: zkLogin nonce derivation and address derivation. Both
/// are Poseidon-BN254 hashes over the BN254 scalar field, which is not something
/// to hand-roll in Dart. The backend supplies the nonce, and the identity
/// provider supplies the address.

/// Sui intent prefix for user transaction data.
///
/// Three bytes: intent scope `TransactionData` (0), intent version `V0` (0), and
/// app id `Sui` (0). Signing the raw transaction bytes without this prefix
/// produces a signature the network rejects.
const List<int> kSuiTransactionDataIntent = <int>[0, 0, 0];

/// Ed25519 scheme flag, prepended to a public key to form the "extended"
/// ephemeral public key the prover expects.
const int kSuiEd25519Flag = 0x00;

/// An ephemeral session key pair. Valid only until the session's `maxEpoch`.
class SuiEphemeralKeyPair {
  const SuiEphemeralKeyPair({required this.seed, required this.publicKey});

  /// 32-byte Ed25519 private seed. Treat as a secret; zero after use.
  final Uint8List seed;

  /// 32-byte Ed25519 public key.
  final Uint8List publicKey;

  String get publicKeyBase64 => base64.encode(publicKey);

  /// Scheme-flagged public key (33 bytes), base64. This is the
  /// `extendedEphemeralPublicKey` the prover binds the proof to.
  String get extendedPublicKeyBase64 =>
      base64.encode(Uint8List.fromList(<int>[kSuiEd25519Flag, ...publicKey]));

  void zeroize() {
    for (var i = 0; i < seed.length; i++) {
      seed[i] = 0;
    }
  }
}

/// A signature over Sui transaction data, ready to hand to the backend for
/// zkLogin assembly.
class SuiEphemeralSignature {
  const SuiEphemeralSignature({
    required this.signatureBase64,
    required this.publicKeyBase64,
  });

  final String signatureBase64;
  final String publicKeyBase64;
}

class SuiSigningService {
  const SuiSigningService();

  static final Ed25519 _ed25519 = Ed25519();

  /// Computes the Sui signing digest: `blake2b256(intent || transactionData)`.
  ///
  /// Exposed separately so it can be verified against a known vector without
  /// performing a signature.
  static Uint8List signingDigest(Uint8List transactionDataBcs) {
    if (transactionDataBcs.isEmpty) {
      throw ArgumentError('Transaction data must not be empty');
    }
    final intent = Uint8List.fromList(kSuiTransactionDataIntent);
    final digest = Blake2bDigest(digestSize: 32);
    digest.update(intent, 0, intent.length);
    digest.update(transactionDataBcs, 0, transactionDataBcs.length);
    final output = Uint8List(32);
    digest.doFinal(output, 0);
    return output;
  }

  /// Generates a fresh ephemeral key pair for a new zkLogin session.
  Future<SuiEphemeralKeyPair> generateEphemeralKeyPair() async {
    final keyPair = await _ed25519.newKeyPair();
    final privateKey = await keyPair.extract();
    final publicKey = await keyPair.extractPublicKey();
    return SuiEphemeralKeyPair(
      seed: Uint8List.fromList(privateKey.bytes),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// Reconstructs an ephemeral key pair from a cached 32-byte seed.
  Future<SuiEphemeralKeyPair> keyPairFromSeed(Uint8List seed) async {
    if (seed.length != 32) {
      throw ArgumentError('Ephemeral seed must be exactly 32 bytes');
    }
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return SuiEphemeralKeyPair(
      seed: Uint8List.fromList(seed),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// Signs prepared Sui transaction data with an ephemeral key.
  ///
  /// [transactionDataBcs] must be the exact bytes returned by the backend's
  /// prepare step. Re-encoding or re-ordering them invalidates the signature.
  Future<SuiEphemeralSignature> signTransactionData({
    required Uint8List transactionDataBcs,
    required SuiEphemeralKeyPair keyPair,
  }) async {
    final digest = signingDigest(transactionDataBcs);
    final signingKeyPair = await _ed25519.newKeyPairFromSeed(keyPair.seed);
    final signature = await _ed25519.sign(digest, keyPair: signingKeyPair);
    return SuiEphemeralSignature(
      signatureBase64: base64.encode(signature.bytes),
      publicKeyBase64: keyPair.publicKeyBase64,
    );
  }

  /// Convenience wrapper for the base64 transaction data the API returns.
  Future<SuiEphemeralSignature> signPreparedTransfer({
    required String transactionDataBcsBase64,
    required SuiEphemeralKeyPair keyPair,
  }) {
    final bytes = base64.decode(transactionDataBcsBase64);
    return signTransactionData(
      transactionDataBcs: Uint8List.fromList(bytes),
      keyPair: keyPair,
    );
  }
}
