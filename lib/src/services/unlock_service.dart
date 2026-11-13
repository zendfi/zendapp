/// Pay-to-read (AppKit primitives R11, R15 pay-and-deliver): buying, gifting
/// and reading items a ZApp sells through `zend::unlock`.
///
/// Every transaction Zend's server prepares is decoded and checked here before
/// the person signs it ([verifyUnlockBuy], [verifyUnlockGift]). Reading goes
/// through [UnlockReader], on this device.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'api_client.dart';
import 'sui_transaction_decoder.dart';
import 'sui_transaction_verifier.dart' show normaliseSuiAddress;
import 'sui_zklogin_service.dart';
import 'unlock_reader.dart';

/// The published `zend_unlock` package (mainnet, Nov 2026). A build can pin
/// another with `--dart-define=UNLOCK_PACKAGE_ID=...`.
const String kUnlockPackageId = String.fromEnvironment(
  'UNLOCK_PACKAGE_ID',
  defaultValue:
      '0x7c07a8df79e3f5b92c3b7352c06bce2b28ba1381d5724af6c3db8d19cef8063d',
);

const String kUnlockSafetyStop =
    "We stopped this because something didn't look right. Your money hasn't moved.";

class UnlockSafetyStop implements Exception {
  const UnlockSafetyStop([this.reason = '']);

  /// For logs and tests; never shown.
  final String reason;
  @override
  String toString() => kUnlockSafetyStop;
}

SuiDecodedTransaction _decode(String txB64) {
  try {
    return decodeSuiTransaction(Uint8List.fromList(base64.decode(txB64)));
  } on Object {
    throw const UnlockSafetyStop('undecodable');
  }
}

SuiInput _input(SuiDecodedTransaction tx, SuiArgument a) {
  if (a.kind != SuiArgumentKind.input ||
      a.index == null ||
      a.index! >= tx.inputs.length) {
    throw const UnlockSafetyStop('argument is not an input');
  }
  return tx.inputs[a.index!];
}

String _pureAddress(SuiDecodedTransaction tx, SuiArgument a) {
  final i = _input(tx, a);
  final addr = i is SuiPureInput ? i.asAddress : null;
  if (addr == null) throw const UnlockSafetyStop('not an address');
  return normaliseSuiAddress(addr);
}

/// The only shape a purchase may have: take exactly [priceBaseUnits] from the
/// buyer's balance, then `unlock::buy_for<T>(listing, that money, recipient)`.
/// The listing pays its payees and mints the receipt in the same transaction.
void verifyUnlockBuy(
  String txB64, {
  required String sender,
  required String listingId,
  required String recipient,
  required BigInt priceBaseUnits,
  String packageId = kUnlockPackageId,
}) {
  final tx = _decode(txB64);
  if (normaliseSuiAddress(tx.sender) != normaliseSuiAddress(sender)) {
    throw const UnlockSafetyStop('sender');
  }
  final calls = tx.commands.whereType<SuiMoveCallCommand>().toList();
  if (calls.length != 2 || tx.commands.length != 2) {
    throw const UnlockSafetyStop('steps');
  }
  final withdrawals = tx.inputs.whereType<SuiFundsWithdrawalInput>().toList();
  if (withdrawals.length != 1 ||
      withdrawals.single.amount != priceBaseUnits ||
      withdrawals.single.source != SuiWithdrawFrom.sender) {
    throw const UnlockSafetyStop('amount');
  }
  final coinType = withdrawals.single.coinType.canonical;

  final redeem = calls[0];
  if (normaliseSuiAddress(redeem.package) != normaliseSuiAddress('0x2') ||
      redeem.module != 'balance' ||
      redeem.function != 'redeem_funds' ||
      redeem.typeArguments.length != 1 ||
      redeem.typeArguments.single.canonical != coinType ||
      redeem.arguments.length != 1 ||
      _input(tx, redeem.arguments.single) is! SuiFundsWithdrawalInput) {
    throw const UnlockSafetyStop('redeem');
  }

  final buy = calls[1];
  if (normaliseSuiAddress(buy.package) != normaliseSuiAddress(packageId) ||
      buy.module != 'unlock' ||
      buy.function != 'buy_for' ||
      buy.typeArguments.length != 1 ||
      buy.typeArguments.single.canonical != coinType ||
      buy.arguments.length != 3) {
    throw const UnlockSafetyStop('buy call');
  }
  final listing = _input(tx, buy.arguments[0]);
  if (listing is! SuiSharedInput ||
      !listing.mutable ||
      normaliseSuiAddress(listing.objectId) != normaliseSuiAddress(listingId)) {
    throw const UnlockSafetyStop('listing');
  }
  final pay = buy.arguments[1];
  if (pay.kind != SuiArgumentKind.result || pay.index != 0) {
    throw const UnlockSafetyStop('payment');
  }
  if (_pureAddress(tx, buy.arguments[2]) != normaliseSuiAddress(recipient)) {
    throw const UnlockSafetyStop('recipient');
  }
}

/// The only shape a gift may have: move exactly [receiptId] to [recipient].
/// No money moves and nothing is called.
void verifyUnlockGift(
  String txB64, {
  required String sender,
  required String receiptId,
  required String recipient,
}) {
  final tx = _decode(txB64);
  if (normaliseSuiAddress(tx.sender) != normaliseSuiAddress(sender) ||
      tx.commands.length != 1 ||
      tx.inputs.whereType<SuiFundsWithdrawalInput>().isNotEmpty) {
    throw const UnlockSafetyStop('shape');
  }
  final t = tx.commands.single;
  if (t is! SuiTransferObjectsCommand || t.objects.length != 1) {
    throw const UnlockSafetyStop('transfer');
  }
  final obj = _input(tx, t.objects.single);
  if (obj is! SuiObjectInput ||
      obj.kind != SuiObjectInputKind.immutableOrOwned ||
      normaliseSuiAddress(obj.reference.objectId) !=
          normaliseSuiAddress(receiptId)) {
    throw const UnlockSafetyStop('receipt');
  }
  if (_pureAddress(tx, t.address) != normaliseSuiAddress(recipient)) {
    throw const UnlockSafetyStop('recipient');
  }
}

class UnlockService {
  UnlockService({required ApiClient api, required SuiZkLoginService zkLogin})
    : _api = api,
      _zk = zkLogin,
      _reader = UnlockReader(api: api, zkLogin: zkLogin);

  static UnlockService? _shared;

  /// One per signed-in session, so the 30-minute reading session and the
  /// keys it fetched survive ZApp screens being rebuilt.
  static UnlockService shared({
    required ApiClient api,
    required SuiZkLoginService zkLogin,
  }) => _shared ??= UnlockService(api: api, zkLogin: zkLogin);

  /// Sign-out: drops the reading session and every fetched key.
  static Future<void> forgetShared() async {
    final s = _shared;
    _shared = null;
    try {
      await s?.forget();
    } catch (_) {}
  }

  final ApiClient _api;
  final SuiZkLoginService _zk;
  final UnlockReader _reader;

  static String _tx(Map<String, dynamic> p) =>
      ((p['envelope'] as Map)['payload'] as Map)['transaction_data_bcs']
          as String;

  String _path(String app, String rest) => '/apps/by-slug/$app/unlock$rest';

  /// Price, title and whether the person has unlocked it.
  Future<Map<String, dynamic>> get(String app, String item) =>
      _api.appkit('GET', _path(app, '/item/${Uri.encodeComponent(item)}'));

  /// Price, parts and a ticket for the confirm sheet. [forWhom] is
  /// `chat:<user id>` or `@username` when buying for someone else.
  Future<Map<String, dynamic>> check(
    String app,
    String item, {
    String? forWhom,
  }) => _api.appkit('POST', _path(app, '/check'), {
    'item': item,
    'for': ?forWhom,
  });

  /// After the person confirmed [checked]: prepare, check, sign, submit.
  Future<Map<String, dynamic>> buy(
    String app,
    Map<String, dynamic> checked,
  ) async {
    final ticket = checked['ticket'] as String;
    final prepared = await _api.appkit('POST', _path(app, '/prepare'), {
      'ticket': ticket,
    });
    final tx = _tx(prepared);
    final shown = BigInt.from(
      ((checked['amount_usd'] as num) * 1000000).round(),
    );
    if (BigInt.parse(prepared['price_base'] as String) != shown) {
      throw const UnlockSafetyStop('price changed');
    }
    final sender = prepared['sender'] as String;
    // Buying for yourself must deliver to yourself.
    if (checked['for'] == null &&
        normaliseSuiAddress(prepared['recipient'] as String) !=
            normaliseSuiAddress(sender)) {
      throw const UnlockSafetyStop('recipient');
    }
    verifyUnlockBuy(
      tx,
      sender: sender,
      listingId: prepared['listing_id'] as String,
      recipient: prepared['recipient'] as String,
      priceBaseUnits: shown,
    );
    final signature = await _zk.signPreparedTransaction(
      transactionDataBcsBase64: tx,
    );
    return _api.appkit('POST', _path(app, '/submit'), {
      'ticket': ticket,
      'transaction_data_bcs': tx,
      'signature': signature,
    });
  }

  /// Who the gift goes to (`recipient_name`), for the confirm sheet.
  Future<Map<String, dynamic>> giftPrepare(
    String app,
    String item,
    String to,
  ) => _api.appkit('POST', _path(app, '/gift/prepare'), {
    'item': item,
    'to': to,
  });

  Future<Map<String, dynamic>> giftSubmit(
    String app,
    Map<String, dynamic> prepared,
  ) async {
    final tx = _tx(prepared);
    verifyUnlockGift(
      tx,
      sender: prepared['sender'] as String,
      receiptId: prepared['receipt_id'] as String,
      recipient: prepared['recipient'] as String,
    );
    final signature = await _zk.signPreparedTransaction(
      transactionDataBcsBase64: tx,
    );
    return _api.appkit('POST', _path(app, '/gift/submit'), {
      'transaction_data_bcs': tx,
      'signature': signature,
    });
  }

  /// Opens [data] (an encrypted object) from [item] on this device. The
  /// server builds the access check from the receipt the person holds; it
  /// never sees [data] or the result.
  Future<Uint8List> read(String app, String item, Uint8List data) async {
    final id = await _reader.identity(data);
    final r = await _api.appkit('POST', _path(app, '/read'), {
      'item': item,
      'id': id,
    });
    return _reader.open(
      listingId: r['listing_id'] as String,
      txKindB64: r['tx_kind'] as String,
      data: data,
    );
  }

  Future<void> forget() => _reader.forget();
}
