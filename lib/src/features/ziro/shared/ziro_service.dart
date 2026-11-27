/// Ziro's app-side flows: the merchant device, the till's talk with the enclave,
/// and the customer's own transactions. Screens call this; it calls core, the
/// enclave and the native plugin. Nothing here keeps a template or a PIN.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ziro_vision/ziro_vision.dart';

import '../../../core/zend_state.dart';
import '../../../services/sui_transaction_verifier.dart';
import 'ziro_api.dart';
import 'ziro_bytes.dart';
import 'ziro_chain.dart';
import 'ziro_copy.dart';
import 'ziro_hpke.dart';
import 'ziro_messages.dart';
import 'ziro_models.dart';

const _kAlias = 'ziro_device';
const _kDeviceId = 'ziro.device_id';
const _kCredential = 'ziro.device_credential';
const _kCredentialExpiry = 'ziro.device_credential_expires';

/// A merchant phone's registration, kept in secure storage.
class ZiroDeviceRecord {
  const ZiroDeviceRecord(this.deviceId, this.credential, this.expiresMs);
  final String deviceId;
  final String credential;
  final int expiresMs;
  bool get fresh => DateTime.now().millisecondsSinceEpoch < expiresMs - 86400000;
}

class ZiroService {
  ZiroService(this.model)
    : api = ZiroApi(model.walletService.apiClient),
      vision = ZiroVision();

  final ZendAppModel model;
  final ZiroApi api;
  final ZiroVision vision;
  final _storage = const FlutterSecureStorage();
  final _http = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
      validateStatus: (_) => true,
    ),
  );
  ZiroConfig? _config;
  ZiroTrust? _trust;

  Future<ZiroConfig> config({bool refresh = false}) async {
    if (_config != null && !refresh) return _config!;
    final c = await api.config();
    _config = c;
    _trust = c.enabled ? ZiroTrust.from(c) : null;
    return c;
  }

  ZiroConfig? get cachedConfig => _config;

  Future<ZiroTrust> trust() async {
    await config();
    final t = _trust;
    if (t == null) throw const ZiroException("Palm pay isn't available right now");
    return t;
  }

  ZiroChainReader _reader(ZiroTrust t) => ZiroChainReader(t);

  // ===================== merchant device =====================

  Future<ZiroDeviceRecord?> savedDevice() async {
    final id = await _storage.read(key: _kDeviceId);
    final cred = await _storage.read(key: _kCredential);
    final exp = int.tryParse(await _storage.read(key: _kCredentialExpiry) ?? '');
    if (id == null || cred == null || exp == null) return null;
    return ZiroDeviceRecord(id, cred, exp);
  }

  /// Makes the hardware key, has the enclave check it, and stores the credential.
  Future<ZiroDeviceRecord> registerThisPhone() async {
    final challenge = zB64(await api.deviceChallenge());
    final key = await vision.deviceKeyCreate(alias: _kAlias, challenge: challenge);
    final reg = {...key.toRegisterJson(), 'challenge': zToB64(challenge)};
    final r = await api.registerDevice(reg);
    final rec = ZiroDeviceRecord(
      r['device_id'] as String,
      r['device_credential'] as String,
      int.tryParse('${r['expires_ms']}') ?? 0,
    );
    await _storage.write(key: _kDeviceId, value: rec.deviceId);
    await _storage.write(key: _kCredential, value: rec.credential);
    await _storage.write(key: _kCredentialExpiry, value: '${rec.expiresMs}');
    return rec;
  }

  Future<void> forgetThisPhone() async {
    await _storage.delete(key: _kDeviceId);
    await _storage.delete(key: _kCredential);
    await _storage.delete(key: _kCredentialExpiry);
  }

  // ===================== enclave =====================

  /// The enclave must be the one the on-chain Registry lists, read directly
  /// from the chain (not through core).
  Future<void> verifyEnclave(ZiroEnclaveRef e) async => _reader(await trust()).verifyEnclave(e);

  Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> body) async {
    final Response<dynamic> r;
    try {
      r = await _http.post<dynamic>(url, data: jsonEncode(body));
    } on DioException {
      throw const ZiroException(ZiroCopy.failed);
    }
    final data = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
    final status = r.statusCode ?? 0;
    if (status >= 200 && status < 300) return data;
    final msg = data['message'] as String?;
    throw ZiroException(
      status < 500 && msg != null && msg.isNotEmpty ? msg : ZiroCopy.failed,
      code: data['error'] as String?,
    );
  }

  /// HPKE-seals [payload] to the enclave and signs the envelope with the device key.
  Future<Map<String, dynamic>> _envelope(
    ZiroEnclaveRef e,
    ZiroDeviceRecord device,
    String op,
    String? challengeId,
    Map<String, dynamic> payload,
  ) async {
    final pt = zUtf8(jsonEncode(payload));
    final sealed = await Hpke().seal(
      recipientPublicKey: zB64(e.x25519Pk),
      info: zUtf8(kZiroHpkeInfo),
      aad: ziroAad(op, challengeId),
      plaintext: pt,
    );
    zWipe(pt);
    final digest = await ziroDeviceDigest(op, challengeId, sealed.enc, sealed.ciphertext);
    final sig = await vision.deviceKeySign(alias: _kAlias, data: digest);
    return _post('${e.url}/v1/$op', {
      'device_id': device.deviceId,
      'device_credential': device.credential,
      'challenge_id': challengeId,
      'enc': zToB64(sealed.enc),
      'ciphertext': zToB64(sealed.ciphertext),
      'device_sig': zToB64(sig),
    });
  }

  /// Asks the charge's enclave for the colour challenge and checks its signature.
  Future<ZiroChallenge> challenge(ZiroCharge charge, ZiroDeviceRecord device, String merchantAddress) async {
    final e = charge.enclave;
    await verifyEnclave(e);
    final payload = {
      'charge_id': charge.chargeId,
      'merchant_address': merchantAddress,
      'amount_base': '${charge.amountBase}',
    };
    final r = ZiroChallenge(await _envelope(e, device, 'challenge', null, payload));
    final msg = await ziroChallengeMessage(r.challengeId, zB64(r.nonceB64), zUtf8(jsonEncode(payload)));
    final ok = await ziroEd25519Verify(publicKey: zB64(e.ed25519Pk), message: msg, signature: zB64(r.enclaveSig));
    if (!ok) throw const ZiroSafetyStop('challenge signature');
    return r;
  }

  /// Sends the capture for matching. Integrity is over sha256(challenge_id || nonce).
  Future<ZiroScanResult> scan(ZiroCharge charge, ZiroDeviceRecord device, ZiroChallenge ch, CapturedEvent cap) async {
    final hash = await ziroRequestHash(ch.challengeId, zB64(ch.nonceB64));
    final integrity = await vision.integrityToken(requestHash: hash);
    final payload = {
      'model_version': cap.modelVersion,
      'palms': [for (final p in cap.palms) p.toJson()],
      'geometry': cap.geometry,
      'face': cap.face,
      'flash': cap.flash?.toJson(),
      'integrity': integrity.toScanJson(),
    };
    final r = await _envelope(charge.enclave, device, 'scan', ch.challengeId, payload);
    return _checked(ZiroScanResult.fromJson(r), charge);
  }

  Future<ZiroScanResult> pin(ZiroCharge charge, ZiroDeviceRecord device, ZiroChallenge ch, String scanId, String pin) async {
    final r = await _envelope(charge.enclave, device, 'pin', ch.challengeId, {'scan_id': scanId, 'pin': pin});
    return _checked(ZiroScanResult.fromJson(r), charge);
  }

  /// An approval must be signed by the charge's enclave over exactly this charge's amount.
  Future<ZiroScanResult> _checked(ZiroScanResult r, ZiroCharge charge) async {
    if (r is! ZiroApproved) return r;
    final a = r.approval;
    if (a.chargeId != charge.chargeId || a.amountBase != charge.amountBase || a.enclavePk != charge.enclave.ed25519Pk) {
      throw const ZiroSafetyStop('approval does not match the charge');
    }
    final msg = ziroPayMessage(
      allowanceId: a.allowanceId,
      accountId: a.accountId,
      merchant: a.merchantAddress,
      amount: a.amountBase,
      fee: a.feeBase,
      seq: a.seq,
      expiresMs: a.expiresMs,
      pinUsed: a.pinUsed,
    );
    final ok = await ziroEd25519Verify(publicKey: zB64(a.enclavePk), message: msg, signature: zB64(a.signature));
    if (!ok) throw const ZiroSafetyStop('approval signature');
    return r;
  }

  // ===================== customer =====================

  Future<String> myAddress() async =>
      normaliseSuiAddress((await model.walletService.apiClient.zlinkGet('/me'))['address'] as String);

  Future<ZiroTxExpectation> expectation() async {
    final t = await trust();
    return ZiroTxExpectation(
      sender: await myAddress(),
      packageId: t.packageId,
      registryId: t.registryId,
      relayer: t.relayer,
      coinType: t.coinType,
    );
  }

  /// Seals an enrollment (or record update) to the enclave and checks its receipt.
  Future<ZiroReceipt> sendRecord(ZiroEnrollStart start, Map<String, dynamic> record, {bool update = false}) async {
    final e = start.enclave;
    await verifyEnclave(e);
    final op = update ? 'records/update' : 'enroll';
    final pt = zUtf8(jsonEncode(record));
    final sealed = await Hpke().seal(
      recipientPublicKey: zB64(e.x25519Pk),
      info: zUtf8(kZiroHpkeInfo),
      aad: ziroAad(op, null),
      plaintext: pt,
    );
    zWipe(pt);
    final Map<String, dynamic> r;
    try {
      r = await _post('${e.url}/v1/$op', {
        'ticket': start.ticket,
        'enc': zToB64(sealed.enc),
        'ciphertext': zToB64(sealed.ciphertext),
      });
    } on ZiroException catch (x) {
      if (x.code == 'DUPLICATE_PALM') throw ZiroException(ZiroCopy.duplicatePalm, code: x.code);
      rethrow;
    }
    final receipt = ZiroReceipt(r);
    // The commitment the chain will hold is the hash of exactly what we sent.
    final commitment = await zSha256(sealed.ciphertext);
    if (receipt.commitmentHex != zHex(commitment) || receipt.enclavePk != e.ed25519Pk) {
      throw const ZiroSafetyStop('receipt commitment');
    }
    final ok = await ziroEd25519Verify(
      publicKey: zB64(receipt.enclavePk),
      message: ziroReceiptMessage(zUuidBytes(receipt.recordId), commitment),
      signature: zB64(receipt.receiptSig),
    );
    if (!ok) throw const ZiroSafetyStop('receipt signature');
    return receipt;
  }

  /// Checks [tx] with [verify] (throws on anything unexpected), signs with
  /// zkLogin and submits it.
  Future<ZiroCustomerStatus?> signAndSubmit(
    ZiroSponsoredTx tx,
    String purpose,
    void Function(String txB64) verify,
  ) async {
    try {
      verify(tx.transactionDataBcs);
    } on SuiTransactionVerificationException {
      throw const ZiroSafetyStop('transaction shape');
    } on Exception {
      throw const ZiroSafetyStop('transaction decode');
    }
    final sig = await model.zkLoginService.signPreparedTransaction(transactionDataBcsBase64: tx.transactionDataBcs);
    final (_, status) = await api.submitTx(tx: tx, purpose: purpose, userSignature: sig);
    return status;
  }

  /// Refund from the merchant's own balance: a plain gasless send to the customer.
  Future<void> refund(String paymentId, {BigInt? amountBase}) async {
    final p = await api.refundPrepare(paymentId, amountBase: amountBase);
    final tx = p['transaction_data_bcs'] as String;
    final summary = Map<String, dynamic>.from(p['summary'] as Map);
    try {
      verifyGaslessUsdcTransfer(
        transactionDataBcsBase64: tx,
        expectation: SuiTransferExpectation(
          amountBaseUnits: BigInt.parse('${summary['amount_base']}'),
          senderAddress: await myAddress(),
          expectedRecipient: summary['to'] as String,
        ),
      );
    } on Exception {
      throw const ZiroSafetyStop('refund shape');
    }
    final sig = await model.zkLoginService.signPreparedTransaction(transactionDataBcsBase64: tx);
    await api.refundSubmit(paymentId, transactionDataBcs: tx, userSignature: sig);
  }
}

/// Bytes for a record field the enclave expects as base64.
String ziroB64(Uint8List b) => base64.encode(b);
