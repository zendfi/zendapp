/// Paying without signal, narrow case (R21.0–21.4, test build).
///
/// 1. While online, the payer taps "Get ready": Zend fetches what a payment
///    needs (address, epoch, chain) and captures the signing prefix.
/// 2. The payee shows a receive code (their address and name).
/// 3. The payer, offline, scans it, enters an amount, and Zend builds, checks
///    and signs the payment on the phone. It shows as a payment code.
/// 4. The payee, online, scans the payment code; Zend's server submits it.
///
/// Works only while Zend stays open since step 1, within the session's 24 h.
library;

import 'dart:convert';

import '../core/zend_format.dart' show formatMoney;
import 'api_client.dart';
import 'sui_zklogin_models.dart' show SuiZkLoginSessionExpired;
import 'sui_transaction_builder.dart';
import 'sui_transaction_verifier.dart';
import 'sui_zklogin_service.dart';

const _receivePrefix = 'zendrx1:';
const _payPrefix = 'zendpay1:';

class OfflinePayException implements Exception {
  const OfflinePayException(this.message);
  final String message;
  @override
  String toString() => message;
}

class OfflineParams {
  OfflineParams(Map<String, dynamic> j)
    : address = j['address'] as String,
      coinType = j['coin_type'] as String,
      chainHex = j['chain_identifier_hex'] as String,
      epoch = (j['epoch'] as num).toInt(),
      maxUsd = (j['max_usd'] as num).toDouble(),
      fetchedAt = DateTime.now();
  final String address;
  final String coinType;
  final String chainHex;
  final int epoch;
  final double maxUsd;
  final DateTime fetchedAt;
}

class ReceiveCode {
  const ReceiveCode(this.address, this.username, this.name);
  final String address;
  final String? username;
  final String? name;
  String get label => username != null ? '@$username' : (name ?? 'them');
}

class OfflinePayService {
  OfflinePayService({
    required ApiClient api,
    required SuiZkLoginService zkLogin,
  }) : _api = api,
       _zk = zkLogin;
  final ApiClient _api;
  final SuiZkLoginService _zk;

  /// Kept in memory only: it's only useful while the signing session is.
  static OfflineParams? _params;

  DateTime? get readyUntil => _params == null ? null : _zk.offlineReadyUntil;

  /// Step 1 (online).
  Future<DateTime> getReady() async {
    final p = OfflineParams(await _api.appkit('GET', '/p2p/offline/params'));
    final until = await _zk.prepareOfflineSigning();
    _params = p;
    return until;
  }

  /// Step 2: the payee's receive code. Needs [getReady] (for the address).
  String receiveCode({String? username, String? name}) {
    final p = _requireParams();
    return _receivePrefix +
        base64Url.encode(
          utf8.encode(jsonEncode({'a': p.address, 'u': ?username, 'n': ?name})),
        );
  }

  static ReceiveCode? readReceiveCode(String raw) {
    final t = raw.trim();
    if (!t.startsWith(_receivePrefix)) return null;
    try {
      final j =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(t.substring(_receivePrefix.length)),
                ),
              )
              as Map<String, dynamic>;
      final a = normaliseSuiAddress(j['a'] as String);
      return ReceiveCode(a, j['u'] as String?, j['n'] as String?);
    } catch (_) {
      return null;
    }
  }

  static bool isPaymentCode(String raw) => raw.trim().startsWith(_payPrefix);

  /// Step 3 (offline): a signed payment of [amountUsd] to [to], as a code.
  Future<String> pay(ReceiveCode to, double amountUsd) async {
    final p = _requireParams();
    if (amountUsd <= 0) throw const OfflinePayException('Enter an amount');
    if (amountUsd > p.maxUsd + 1e-9) {
      throw OfflinePayException(
        'Without signal you can send up to ${formatMoney(p.maxUsd)} for now',
      );
    }
    if (to.address == normaliseSuiAddress(p.address)) {
      throw const OfflinePayException("That's your own code");
    }
    final amount = usdcBaseUnits(amountUsd);
    final tx = buildGaslessTransfer(
      sender: p.address,
      recipient: to.address,
      coinType: p.coinType,
      amountBaseUnits: amount,
      chainIdHex: p.chainHex,
      minEpoch: p.epoch,
      maxEpoch: p.epoch + 1,
    );
    // The same check every send gets before signing.
    verifyGaslessUsdcTransfer(
      transactionDataBcsBase64: tx,
      expectation: SuiTransferExpectation(
        amountBaseUnits: amount,
        senderAddress: p.address,
        expectedRecipient: to.address,
        expectedCoinType: p.coinType,
      ),
    );
    try {
      final sig = await _zk.signOffline(tx);
      return '$_payPrefix$tx.$sig';
    } on SuiZkLoginSessionExpired catch (e) {
      throw OfflinePayException(e.message);
    }
  }

  /// Step 4 (online, payee): submits a payment code. Returns the server reply.
  Future<Map<String, dynamic>> collect(String code) {
    final t = code.trim();
    if (!t.startsWith(_payPrefix)) {
      throw const OfflinePayException("That isn't a Zend payment code");
    }
    final body = t.substring(_payPrefix.length);
    final dot = body.indexOf('.');
    if (dot <= 0) {
      throw const OfflinePayException("That payment code is incomplete");
    }
    return _api.appkit('POST', '/p2p/offline/submit', {
      'transaction_data_bcs': body.substring(0, dot),
      'signature': body.substring(dot + 1),
    });
  }

  OfflineParams _requireParams() {
    final p = _params;
    if (p == null || _zk.offlineReadyUntil == null) {
      throw const OfflinePayException(
        'Tap "Get ready" while you have signal first.',
      );
    }
    return p;
  }
}
