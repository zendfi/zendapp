import 'api_client.dart';
import 'sui_transaction_verifier.dart' show normaliseSuiAddress;
import 'sui_zklogin_service.dart';
import 'zlink_service.dart' show verifyZlinkTransaction;

/// Optional pin for the published `zend::prize` package.
const String kPrizePackageId = String.fromEnvironment('PRIZE_PACKAGE_ID');

/// Host-funded prizes (`zend::prize`). Hosts create and may cancel during the
/// dispute window; players join. Every prepared transaction is decoded and
/// checked before the user approves it.
class PrizeService {
  PrizeService({required ApiClient api, required SuiZkLoginService zkLogin})
    : _api = api,
      _zkLogin = zkLogin;

  final ApiClient _api;
  final SuiZkLoginService _zkLogin;

  Future<String> _me() async =>
      normaliseSuiAddress((await _api.zlinkGet('/me'))['address'] as String);

  /// Same check as links (a prize is funded the same way), for `prize::<function>`.
  void _verify(
    String txB64, {
    required String sender,
    required String function,
    BigInt? withdraw,
  }) => verifyZlinkTransaction(
    txB64,
    sender: sender,
    function: function,
    withdrawBaseUnits: withdraw,
    packageId: kPrizePackageId,
    module: 'prize',
  );

  String _tx(Map<String, dynamic> p) =>
      ((p['envelope'] as Map)['payload'] as Map)['transaction_data_bcs']
          as String;

  Future<Map<String, dynamic>> _signSubmit(String path, String tx) async {
    final sig = await _zkLogin.signPreparedTransaction(
      transactionDataBcsBase64: tx,
    );
    return _api.appkit('POST', path, {
      'transaction_data_bcs': tx,
      'signature': sig,
    });
  }

  Future<Map<String, dynamic>> create({
    required String app,
    required double amountUsd,
    double? priceNgn,
    required int joinInSecs,
    required int resolveInSecs,
    required int maxPlayers,
    int? disputeSecs,
    String? reference,
    String? interactionId,
  }) async {
    final me = await _me();
    final prepared = await _api.appkit('POST', '/apps/prizes/prepare', {
      'app': app,
      'amount_usd': amountUsd,
      'price_ngn': ?priceNgn,
      'join_in_secs': joinInSecs,
      'resolve_in_secs': resolveInSecs,
      'max_players': maxPlayers,
      'dispute_secs': ?disputeSecs,
      'reference': ?reference,
      'interaction_id': ?interactionId,
    });
    final tx = _tx(prepared);
    _verify(
      tx,
      sender: me,
      function: 'create',
      withdraw: BigInt.from((amountUsd * 1000000).round()),
    );
    return _signSubmit('/apps/prizes/submit', tx);
  }

  Future<Map<String, dynamic>> _simple(String id, String op) async {
    final me = await _me();
    final prepared = await _api.appkit('POST', '/apps/prizes/$id/$op/prepare');
    final tx = _tx(prepared);
    _verify(tx, sender: me, function: op);
    return _signSubmit('/apps/prizes/$id/$op/submit', tx);
  }

  Future<Map<String, dynamic>> join(String id) => _simple(id, 'join');
  Future<Map<String, dynamic>> veto(String id) => _simple(id, 'veto');
  Future<Map<String, dynamic>> get(String id) =>
      _api.appkit('GET', '/apps/prizes/$id');
}
