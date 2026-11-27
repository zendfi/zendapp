/// Zend core's Ziro routes (contracts.md §5), under `/api/zend/v2/ziro`.
library;

import '../../../services/api_client.dart';
import 'ziro_models.dart';

class ZiroApi {
  ZiroApi(this._api);
  final ApiClient _api;

  ApiClient get client => _api;

  Future<Map<String, dynamic>> _call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) => _api.appkit(method, '/ziro$path', body);

  String _before(String path, String? before) => before == null
      ? path
      : '$path?before=${Uri.encodeQueryComponent(before)}';

  // ── Shared ────────────────────────────────────────────────────────────────

  Future<ZiroConfig> config() async => ZiroConfig(await _call('GET', '/config'));

  Future<List<ZiroCampus>> campuses() async {
    final r = await _call('GET', '/campuses');
    return (r['campuses'] as List? ?? [])
        .cast<Map>()
        .map((c) => ZiroCampus('${c['id']}', '${c['name']}'))
        .toList();
  }

  // ── Merchant ──────────────────────────────────────────────────────────────

  Future<ZiroMerchant> registerMerchant({
    required String businessName,
    required String category,
    required String campusId,
  }) async => ZiroMerchant(
    await _call('POST', '/merchants', {
      'business_name': businessName,
      'category': category,
      'campus_id': campusId,
    }),
  );

  Future<ZiroMerchant?> myMerchant() async {
    final m = (await _call('GET', '/merchants/me'))['merchant'];
    return m is Map ? ZiroMerchant(Map<String, dynamic>.from(m)) : null;
  }

  Future<ZiroMerchant> updateMerchantSettings({bool? sound, bool? haptics}) async =>
      ZiroMerchant(
        await _call('PATCH', '/merchants/me/settings', {
          'sound': ?sound,
          'haptics': ?haptics,
        }),
      );

  /// Today's 32-byte registration challenge (base64) for a new device key.
  Future<String> deviceChallenge() async =>
      (await _call('GET', '/devices/challenge'))['challenge'] as String;

  /// [registration] is `{device_pk, platform, challenge, android?, ios?}`.
  /// Returns `{device_id, device_credential, expires_ms}`.
  Future<Map<String, dynamic>> registerDevice(Map<String, dynamic> registration) =>
      _call('POST', '/devices', registration);

  Future<List<ZiroDevice>> devices() async =>
      ((await _call('GET', '/devices'))['devices'] as List? ?? [])
          .map((d) => ZiroDevice(Map<String, dynamic>.from(d as Map)))
          .toList();

  Future<void> removeDevice(String id) async {
    await _call('DELETE', '/devices/${Uri.encodeComponent(id)}');
  }

  Future<ZiroCharge> createCharge({
    required String deviceId,
    required String currency,
    required String value,
    String? note,
  }) async => ZiroCharge(
    await _call('POST', '/charges', {
      'device_id': deviceId,
      'amount': {'currency': currency, 'value': value},
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }),
  );

  Future<void> cancelCharge(String chargeId) async {
    await _call('POST', '/charges/${Uri.encodeComponent(chargeId)}/cancel');
  }

  Future<ZiroSettled> settle(String chargeId, ZiroApproval approval) async =>
      ZiroSettled(
        await _call('POST', '/charges/${Uri.encodeComponent(chargeId)}/settle', {
          'approval': approval.raw,
        }),
      );

  Future<ZiroMerchantPayments> merchantPayments({String? before}) async =>
      ZiroMerchantPayments(
        await _call('GET', _before('/merchant/payments', before)),
      );

  /// A gasless send back to the customer: `{transaction_data_bcs, summary}`.
  Future<Map<String, dynamic>> refundPrepare(String paymentId, {BigInt? amountBase}) =>
      _call(
        'POST',
        '/merchant/payments/${Uri.encodeComponent(paymentId)}/refund/prepare',
        {if (amountBase != null) 'amount_base': '$amountBase'},
      );

  Future<Map<String, dynamic>> refundSubmit(
    String paymentId, {
    required String transactionDataBcs,
    required String userSignature,
  }) => _call(
    'POST',
    '/merchant/payments/${Uri.encodeComponent(paymentId)}/refund/submit',
    {'transaction_data_bcs': transactionDataBcs, 'user_signature': userSignature},
  );

  // ── Customer ──────────────────────────────────────────────────────────────

  Future<ZiroCustomerStatus> me() async =>
      ZiroCustomerStatus(await _call('GET', '/me'));

  Future<ZiroEnrollStart> enrollStart({
    required String consentVersion,
    required bool faceOptIn,
  }) async => ZiroEnrollStart(
    await _call('POST', '/enroll/start', {
      'consent_version': consentVersion,
      'face_opt_in': faceOptIn,
    }),
  );

  Future<ZiroSponsoredTx> enrollPrepare({
    required ZiroReceipt receipt,
    required ZiroLimits limits,
  }) async => ZiroSponsoredTx(
    await _call('POST', '/enroll/prepare', {
      'record_id': receipt.recordId,
      'commitment_hex': receipt.commitmentHex,
      'receipt_sig': receipt.receiptSig,
      'enclave_pk': receipt.enclavePk,
      ...limits.toJson(),
    }),
  );

  Future<ZiroSponsoredTx> limitsPrepare(ZiroLimits limits) async =>
      ZiroSponsoredTx(await _call('POST', '/me/limits/prepare', limits.toJson()));

  Future<ZiroEnrollStart> pinStart() async =>
      ZiroEnrollStart(await _call('POST', '/me/pin/start'));

  Future<ZiroSponsoredTx> commitmentPrepare(ZiroReceipt receipt) async =>
      ZiroSponsoredTx(
        await _call('POST', '/me/commitment/prepare', {
          'record_id': receipt.recordId,
          'commitment_hex': receipt.commitmentHex,
          'receipt_sig': receipt.receiptSig,
          'enclave_pk': receipt.enclavePk,
        }),
      );

  /// `{status, tx}`; `tx` is null when nothing needs signing.
  Future<(String, ZiroSponsoredTx?)> setPaused(bool paused) async {
    final r = await _call('POST', '/me/pause', {'paused': paused});
    return ('${r['status']}', ZiroSponsoredTx.maybe(r['tx']));
  }

  Future<ZiroSponsoredTx> deletePrepare() async =>
      ZiroSponsoredTx(await _call('POST', '/me/delete/prepare'));

  Future<(String, ZiroCustomerStatus?)> submitTx({
    required ZiroSponsoredTx tx,
    required String purpose,
    required String userSignature,
    String? ref,
  }) async {
    final r = await _call('POST', '/tx/submit', {
      'purpose': purpose,
      'ref': ?ref,
      'transaction_data_bcs': tx.transactionDataBcs,
      'sponsor_signature': tx.sponsorSignature,
      'user_signature': userSignature,
    });
    final s = r['status'];
    return (
      '${r['digest'] ?? ''}',
      s is Map ? ZiroCustomerStatus(Map<String, dynamic>.from(s)) : null,
    );
  }

  Future<List<ZiroCustomerPayment>> myPayments({String? before}) async =>
      ((await _call('GET', _before('/me/payments', before)))['payments']
                  as List? ??
              [])
          .map((p) => ZiroCustomerPayment(Map<String, dynamic>.from(p as Map)))
          .toList();

  /// `{paused: true, tx}`: palm pay is paused off-chain at once; [tx] makes
  /// it a hard stop once signed.
  Future<ZiroSponsoredTx?> dispute(String paymentId) async {
    final r = await _call(
      'POST',
      '/payments/${Uri.encodeComponent(paymentId)}/dispute',
    );
    return ZiroSponsoredTx.maybe(r['tx']);
  }
}
