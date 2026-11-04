import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'sui_transaction_decoder.dart';
import 'sui_transaction_verifier.dart';
import 'sui_zklogin_service.dart';

/// Must match `DOMAIN` in `move/zend_zlink/sources/zlink.move`.
const String kZlinkClaimDomain = 'zend-zlink-claim-v1';

/// Shown whenever the device refuses to approve what the server prepared.
const String _kSafetyStop =
    "We stopped this because something didn't look right. Your money hasn't moved.";

const String kZlinkWebOrigin = 'https://app.usezend.app';

/// Optional pin for the published package. When set, every prepared Zlink
/// transaction must call into exactly this package.
const String kZlinkPackageId = String.fromEnvironment('ZLINK_PACKAGE_ID');

class ZlinkException implements Exception {
  const ZlinkException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A give link this device created. The seed is the link key; it lives only in
/// secure storage and in the URL fragment, never on Zend's servers.
class CreatedGiveLink {
  const CreatedGiveLink({required this.id, required this.seed});
  final String id;
  final Uint8List seed;

  String get url => zlinkGiveUrl(id, seed);
}

String zlinkGiveUrl(String id, Uint8List seed) =>
    '$kZlinkWebOrigin/z/$id#${base64Url.encode(seed).replaceAll('=', '')}';

String zlinkAskUrl(String id) => '$kZlinkWebOrigin/a/$id';

/// Parses the link key carried after `#` (base64url, unpadded, 32 bytes).
Uint8List? parseZlinkKey(String fragment) {
  try {
    var f = fragment.trim();
    if (f.isEmpty) return null;
    f = f.padRight((f.length + 3) ~/ 4 * 4, '=');
    final bytes = base64Url.decode(f);
    return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
  } catch (_) {
    return null;
  }
}

Uint8List _hex32(String raw) {
  final hex = normaliseSuiAddress(raw).substring(2);
  final out = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// `DOMAIN || link id (32 bytes) || bcs(recipient) (32 bytes)`, exactly as
/// `zlink::claim_message` builds it on chain.
Uint8List zlinkClaimMessage(String linkId, String recipient) {
  return Uint8List.fromList([
    ...utf8.encode(kZlinkClaimDomain),
    ..._hex32(linkId),
    ..._hex32(recipient),
  ]);
}

/// The check run before signing anything for a link (or, with [module]
/// `prize`, a prize): only the expected `<module>::<function>` call, sent by [sender], withdrawing exactly
/// [withdrawBaseUnits] when set (creating a link) and nothing otherwise.
/// Throws [ZlinkException] with the safety message on anything else.
void verifyZlinkTransaction(
  String txBase64, {
  required String sender,
  required String function,
  BigInt? withdrawBaseUnits,
  String packageId = kZlinkPackageId,
  String module = 'zlink',
}) {
  final SuiDecodedTransaction tx;
  try {
    tx = decodeSuiTransaction(Uint8List.fromList(base64.decode(txBase64)));
  } on SuiTransactionDecodeException {
    throw const ZlinkException(_kSafetyStop);
  }
  if (normaliseSuiAddress(tx.sender) != normaliseSuiAddress(sender)) {
    throw const ZlinkException(_kSafetyStop);
  }
  final calls = tx.commands.whereType<SuiMoveCallCommand>().toList();
  if (calls.length != tx.commands.length) {
    throw const ZlinkException(_kSafetyStop);
  }
  // Creating a link takes the money out of the balance first, so it is two
  // steps: `0x2::balance::redeem_funds<T>(withdrawal)`, then
  // `zlink::create<T>(that balance, ...)`. Everything else is one step.
  final expectedSteps = withdrawBaseUnits == null ? 1 : 2;
  if (calls.length != expectedSteps) {
    throw const ZlinkException(_kSafetyStop);
  }
  final call = calls.last;
  if (call.module != module || call.function != function) {
    throw const ZlinkException(_kSafetyStop);
  }
  if (withdrawBaseUnits != null) {
    final redeem = calls.first;
    final withdrawal = tx.inputs.whereType<SuiFundsWithdrawalInput>();
    if (normaliseSuiAddress(redeem.package) != normaliseSuiAddress('0x2') ||
        redeem.module != 'balance' ||
        redeem.function != 'redeem_funds' ||
        redeem.typeArguments.length != 1 ||
        redeem.arguments.length != 1 ||
        withdrawal.length != 1) {
      throw const ZlinkException(_kSafetyStop);
    }
    // redeem_funds must spend the withdrawal input, from the sender.
    final from = redeem.arguments.single;
    if (from.kind != SuiArgumentKind.input ||
        from.index == null ||
        from.index! >= tx.inputs.length ||
        tx.inputs[from.index!] is! SuiFundsWithdrawalInput ||
        withdrawal.single.source != SuiWithdrawFrom.sender) {
      throw const ZlinkException(_kSafetyStop);
    }
    // The link must be funded by exactly that balance, of the same type.
    final coinType = withdrawal.single.coinType.canonical;
    if (call.arguments.isEmpty ||
        call.arguments.first.kind != SuiArgumentKind.result ||
        call.arguments.first.index != 0 ||
        call.arguments.skip(1).any((a) => a.kind == SuiArgumentKind.result || a.kind == SuiArgumentKind.nestedResult) ||
        redeem.typeArguments.single.canonical != coinType ||
        call.typeArguments.length != 1 ||
        call.typeArguments.single.canonical != coinType) {
      throw const ZlinkException(_kSafetyStop);
    }
  }
  if (packageId.isNotEmpty &&
      normaliseSuiAddress(call.package) !=
          normaliseSuiAddress(packageId)) {
    throw const ZlinkException(_kSafetyStop);
  }
  final withdrawals = tx.inputs.whereType<SuiFundsWithdrawalInput>().toList();
  if (withdrawBaseUnits == null) {
    if (withdrawals.isNotEmpty) {
      throw const ZlinkException(_kSafetyStop);
    }
  } else if (withdrawals.length != 1 ||
      withdrawals.single.amount != withdrawBaseUnits) {
    throw const ZlinkException(_kSafetyStop);
  }}

class ZlinkService {
  ZlinkService({
    required ApiClient api,
    required SuiZkLoginService zkLogin,
    FlutterSecureStorage? storage,
  }) : _api = api,
       _zkLogin = zkLogin,
       _storage = storage ?? const FlutterSecureStorage();

  final ApiClient _api;
  final SuiZkLoginService _zkLogin;
  final FlutterSecureStorage _storage;
  static final Ed25519 _ed25519 = Ed25519();
  static const _keyPrefix = 'zlink_key:';
  static const _pubPrefix = 'zlink_pub:';
  static const _pinnedAddressKey = 'zlink_pinned_address';

  // ── Own address (pinned) ──────────────────────────────────────────────────

  /// The address claim signatures bind to. Pinned on first read: if the server
  /// later reports a different one, refuse rather than sign for it, because a
  /// claim signature for someone else's address hands them the money.
  Future<String> _myAddress() async {
    final data = await _api.zlinkGet('/me');
    final reported = normaliseSuiAddress(data['address'] as String);
    final pinned = await _storage.read(key: _pinnedAddressKey);
    if (pinned == null) {
      await _storage.write(key: _pinnedAddressKey, value: reported);
      return reported;
    }
    if (pinned != reported) {
      throw const ZlinkException(
        "Something about your account changed. Sign out and back in.",
      );
    }
    return reported;
  }

  // ── Verification of server-built bytes ────────────────────────────────────

  /// Refuses to sign anything other than a single `zlink::<function>` call
  /// sent by [sender], optionally withdrawing exactly [withdrawBaseUnits].
  void _verify(
    String txBase64, {
    required String sender,
    required String function,
    BigInt? withdrawBaseUnits,
  }) => verifyZlinkTransaction(
    txBase64,
    sender: sender,
    function: function,
    withdrawBaseUnits: withdrawBaseUnits,
  );


  String _txOf(Map<String, dynamic> prepared) =>
      ((prepared['envelope'] as Map)['payload'] as Map)['transaction_data_bcs']
          as String;

  Future<Map<String, dynamic>> _signAndSubmit(String path, String tx) async {
    final signature = await _zkLogin.signPreparedTransaction(
      transactionDataBcsBase64: tx,
    );
    return _api.zlinkPost(path, {
      'transaction_data_bcs': tx,
      'signature': signature,
    });
  }

  // ── Give links ────────────────────────────────────────────────────────────

  /// Creates a give link. Returns the full shareable URL (with the key).
  Future<CreatedGiveLink> createGiveLink({
    required double amountUsd,
    int uses = 1,
    String? memo,
    String? recipientHint,
    int? ngnQuoteKobo,
    Duration? expiresIn,
    String? app,
    String? reference,
  }) async {
    final keyPair = await _ed25519.newKeyPair();
    final seed = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    final publicKey = (await keyPair.extractPublicKey()).bytes;
    final sender = await _myAddress();

    final perClaim = BigInt.from((amountUsd * 1000000).round());
    final prepared = await _api.zlinkPost('/give/prepare', {
      'claim_pubkey': publicKey
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      'amount_usd': amountUsd,
      'uses': uses,
      'memo': ?memo,
      'recipient_hint': ?recipientHint,
      'ngn_quote_kobo': ?ngnQuoteKobo,
      if (expiresIn != null) 'expires_in_secs': expiresIn.inSeconds,
      'app': ?app,
      'reference': ?reference,
    });
    final tx = _txOf(prepared);
    _verify(
      tx,
      sender: sender,
      function: 'create',
      withdrawBaseUnits: perClaim * BigInt.from(uses),
    );
    // Save the key under its public key *before* signing. If anything fails
    // after the money moves, the key is still on this device and My Links can
    // re-attach it once the link shows up.
    final pubHex = publicKey
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: '$_pubPrefix$pubHex', value: base64.encode(seed));
    final result = await _signAndSubmit('/give/submit', tx);
    final id = result['id'] as String?;
    if (id == null) {
      throw const ZlinkException(
        'Your link is being set up. It will appear in My Links in a moment.',
      );
    }
    await _storage.write(key: '$_keyPrefix$id', value: base64.encode(seed));
    await _storage.delete(key: '$_pubPrefix$pubHex');
    return CreatedGiveLink(id: id, seed: seed);
  }

  /// The locally stored key for a link this device created, for re-sharing.
  Future<CreatedGiveLink?> localLink(String id, {String? claimPubkey}) async {
    var raw = await _storage.read(key: '$_keyPrefix$id');
    if (raw == null && claimPubkey != null) {
      // Created while the link was still pending: adopt the key saved by pubkey.
      raw = await _storage.read(key: '$_pubPrefix${claimPubkey.toLowerCase()}');
      if (raw != null) {
        await _storage.write(key: '$_keyPrefix$id', value: raw);
        await _storage.delete(key: '$_pubPrefix${claimPubkey.toLowerCase()}');
      }
    }
    if (raw == null) return null;
    return CreatedGiveLink(
      id: id,
      seed: Uint8List.fromList(base64.decode(raw)),
    );
  }

  Future<Map<String, dynamic>> previewGive(String id) =>
      _api.zlinkGet('/give/$id');

  /// Claims a give link into the signed-in account.
  Future<Map<String, dynamic>> claim({
    required String linkId,
    required Uint8List linkKey,
  }) async {
    final recipient = await _myAddress();
    final keyPair = await _ed25519.newKeyPairFromSeed(linkKey);
    final signature = await _ed25519.sign(
      zlinkClaimMessage(linkId, recipient),
      keyPair: keyPair,
    );
    final prepared = await _api.zlinkPost('/give/$linkId/claim/prepare', {
      'link_signature': base64.encode(signature.bytes),
    });
    final tx = _txOf(prepared);
    _verify(tx, sender: recipient, function: 'claim');
    return _signAndSubmit('/give/$linkId/claim/submit', tx);
  }

  /// Takes back what is left in a give link. Needs no link key.
  Future<void> reclaim(String linkId) async {
    final sender = await _myAddress();
    final prepared = await _api.zlinkPost('/give/$linkId/reclaim/prepare');
    final tx = _txOf(prepared);
    _verify(tx, sender: sender, function: 'reclaim');
    await _signAndSubmit('/give/$linkId/reclaim/submit', tx);
    await _storage.delete(key: '$_keyPrefix$linkId');
  }

  // ── Ask links ─────────────────────────────────────────────────────────────

  Future<String> createAskLink({
    double? amountUsd,
    double? maxAmountUsd,
    int? maxPayments,
    String? memo,
    String? app,
    String? reference,
  }) async {
    final data = await _api.zlinkPost('/ask', {
      'app': ?app,
      'reference': ?reference,
      'amount_usd': ?amountUsd,
      'max_amount_usd': ?maxAmountUsd,
      'max_payments': ?maxPayments,
      'memo': ?memo,
    });
    return data['url'] as String;
  }

  Future<Map<String, dynamic>> previewAsk(String id) =>
      _api.zlinkGet('/ask/$id');

  /// Pays an ask link. The prepared bytes are a plain gasless transfer, checked
  /// with the same verifier the normal send flow uses before signing.
  Future<Map<String, dynamic>> payAsk(
    String id, {
    required double amountUsd,
  }) async {
    final payer = await _myAddress();
    final prepared = await _api.zlinkPost('/ask/$id/pay/prepare', {
      'amount_usd': amountUsd,
    });
    final tx = _txOf(prepared);
    try {
      verifyGaslessUsdcTransfer(
        transactionDataBcsBase64: tx,
        expectation: SuiTransferExpectation(
          amountBaseUnits: usdcBaseUnits(amountUsd),
          senderAddress: payer,
        ),
      );
    } on SuiTransactionVerificationException {
      throw const ZlinkException(_kSafetyStop);
    } on SuiTransactionDecodeException {
      throw const ZlinkException(_kSafetyStop);
    }
    final signature = await _zkLogin.signPreparedTransaction(
      transactionDataBcsBase64: tx,
    );
    return _api.zlinkPost('/ask/$id/pay/submit', {
      'transaction_data_bcs': tx,
      'signature': signature,
      // Return tokens for "Pay with Zend" are issued per platform.
      'platform': defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'android',
    });
  }

  Future<void> cancelAsk(String id) => _api.zlinkPost('/ask/$id/cancel');

  // ── My Links ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> myLinks() async {
    final data = await _api.zlinkGet('');
    return (data['links'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }
}
