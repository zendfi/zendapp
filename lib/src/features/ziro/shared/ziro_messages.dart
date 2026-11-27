/// Byte layouts Ziro signs or binds (contracts.md §1.1, §1.2, §2.1, §2.2).
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../services/sui_transaction_verifier.dart' show normaliseSuiAddress;
import 'ziro_bytes.dart';

const String kZiroHpkeInfo = 'zend-ziro-hpke-v1';

/// `"zend-ziro-v1/" + op + "/" + (challenge_id or "")`.
Uint8List ziroAad(String op, String? challengeId) =>
    zUtf8('zend-ziro-v1/$op/${challengeId ?? ''}');

/// What the merchant device key signs for an enveloped request:
/// `sha256("zend-ziro-dev-v1" || op || 0x00 || challenge_id_or_empty || 0x00
/// || sha256(enc || ciphertext))`.
Future<Uint8List> ziroDeviceDigest(
  String op,
  String? challengeId,
  List<int> enc,
  List<int> ciphertext,
) async {
  final body = await zSha256(zCat([enc, ciphertext]));
  return zSha256(
    zCat([
      zUtf8('zend-ziro-dev-v1'),
      zUtf8(op),
      [0],
      zUtf8(challengeId ?? ''),
      [0],
      body,
    ]),
  );
}

/// Play Integrity `requestHash` and App Attest `client_data_hash`:
/// `sha256(challenge_id || nonce)`.
Future<Uint8List> ziroRequestHash(String challengeId, List<int> nonce) =>
    zSha256(zCat([zUtf8(challengeId), nonce]));

/// `"zend-ziro-receipt-v1" || record_id (16) || commitment (32)`.
Uint8List ziroReceiptMessage(List<int> recordId, List<int> commitment) {
  if (recordId.length != 16 || commitment.length != 32) {
    throw ArgumentError('receipt fields have the wrong length');
  }
  return zCat([zUtf8('zend-ziro-receipt-v1'), recordId, commitment]);
}

/// `"zend-ziro-chal-v1" || challenge_id || nonce || sha256(json payload)`.
Future<Uint8List> ziroChallengeMessage(
  String challengeId,
  List<int> nonce,
  List<int> payloadJson,
) async => zCat([
  zUtf8('zend-ziro-chal-v1'),
  zUtf8(challengeId),
  nonce,
  await zSha256(payloadJson),
]);

Uint8List _addr(String a) => zUnhex(normaliseSuiAddress(a));

/// The 145-byte approval message `pay` checks (contracts §1.1).
Uint8List ziroPayMessage({
  required String allowanceId,
  required String accountId,
  required String merchant,
  required BigInt amount,
  required BigInt fee,
  required BigInt seq,
  required BigInt expiresMs,
  required bool pinUsed,
}) => zCat([
  zUtf8('zend-ziro-pay-v1'),
  _addr(allowanceId),
  _addr(accountId),
  _addr(merchant),
  zU64le(amount),
  zU64le(fee),
  zU64le(seq),
  zU64le(expiresMs),
  [pinUsed ? 1 : 0],
]);

Future<bool> ziroEd25519Verify({
  required List<int> publicKey,
  required List<int> message,
  required List<int> signature,
}) async {
  if (publicKey.length != 32 || signature.length != 64) return false;
  try {
    return await Ed25519().verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}
