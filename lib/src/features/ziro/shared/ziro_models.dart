/// Typed views of Ziro's core API shapes (contracts.md §5) and enclave
/// responses (§2.2). Amounts stay [BigInt] base units; labels are already
/// formatted by core and are shown as they are.
library;

BigInt _big(Object? v) {
  if (v == null) return BigInt.zero;
  if (v is int) return BigInt.from(v);
  return BigInt.tryParse('$v') ?? BigInt.zero;
}

BigInt? _bigOrNull(Object? v) => v == null ? null : _big(v);

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Base units (6 decimals) to dollars, for [formatMoney]. Display only.
double ziroUsd(BigInt base) => base.toDouble() / 1000000;

/// Dollars to base units, exactly, through the 6-decimal string.
BigInt ziroBase(double usd) {
  final s = usd.toStringAsFixed(6).split('.');
  return BigInt.parse(s[0]) * BigInt.from(1000000) + BigInt.parse(s[1]);
}

class ZiroLimits {
  const ZiroLimits({
    required this.perPaymentMax,
    required this.noPinMax,
    required this.dailyMax,
  });
  final BigInt perPaymentMax;
  final BigInt noPinMax;
  final BigInt dailyMax;

  factory ZiroLimits.fromJson(Map<String, dynamic> j) => ZiroLimits(
    perPaymentMax: _big(j['per_payment_max_base']),
    noPinMax: _big(j['no_pin_max_base']),
    dailyMax: _big(j['daily_max_base']),
  );

  Map<String, dynamic> toJson() => {
    'per_payment_max_base': '$perPaymentMax',
    'no_pin_max_base': '$noPinMax',
    'daily_max_base': '$dailyMax',
  };

  ZiroLimits copyWith({BigInt? perPaymentMax, BigInt? noPinMax, BigInt? dailyMax}) =>
      ZiroLimits(
        perPaymentMax: perPaymentMax ?? this.perPaymentMax,
        noPinMax: noPinMax ?? this.noPinMax,
        dailyMax: dailyMax ?? this.dailyMax,
      );
}

class ZiroConfig {
  ZiroConfig(this.raw);
  final Map<String, dynamic> raw;

  bool get enabled => raw['enabled'] == true;
  bool get testMode => raw['test_mode'] == true;
  String get packageId => raw['package_id'] as String? ?? '';
  String get registryId => raw['registry_id'] as String? ?? '';
  String get relayer => raw['relayer'] as String? ?? '';
  String get coinType => raw['coin_type'] as String? ?? '';
  int get feeBps => (raw['fee_bps'] as num?)?.toInt() ?? 0;
  BigInt get feeMin => _big(raw['fee_min_base']);
  BigInt get minCharge => _big(raw['min_charge_base']);
  BigInt get noPinCeiling => _big(raw['no_pin_ceiling_base']);
  ZiroLimits get defaults => ZiroLimits.fromJson(_map(raw['defaults']));
  String get suiGraphqlUrl => raw['sui_graphql_url'] as String? ?? '';

  /// "0.1%" for 10 basis points. A rate, not money.
  String get feePercent {
    final pct = feeBps / 100;
    var s = pct.toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$s%';
  }
}

class ZiroEnclaveRef {
  const ZiroEnclaveRef({
    required this.url,
    required this.ed25519Pk,
    required this.x25519Pk,
  });
  final String url;

  /// Base64, as core sends them.
  final String ed25519Pk;
  final String x25519Pk;

  factory ZiroEnclaveRef.fromJson(Map<String, dynamic> j) => ZiroEnclaveRef(
    url: j['url'] as String? ?? '',
    ed25519Pk: j['ed25519_pk'] as String? ?? '',
    x25519Pk: j['x25519_pk'] as String? ?? '',
  );
}

class ZiroCampus {
  const ZiroCampus(this.id, this.name);
  final String id;
  final String name;
}

class ZiroMerchant {
  ZiroMerchant(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id'] as String;
  String get businessName => raw['business_name'] as String? ?? '';
  String get category => raw['category'] as String? ?? '';
  String? get campusId => raw['campus_id'] as String?;
  String get payoutAddress => raw['payout_address'] as String? ?? '';
  String get status => raw['status'] as String? ?? 'active';
  bool get active => status == 'active';
  int get feeBps => (raw['fee_bps'] as num?)?.toInt() ?? 0;
  bool get sound => _map(raw['settings'])['sound'] != false;
  bool get haptics => _map(raw['settings'])['haptics'] != false;
}

class ZiroDevice {
  ZiroDevice(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id'] as String;
  String get platform => raw['platform'] as String? ?? '';
  DateTime? get createdAt => DateTime.tryParse('${raw['created_at']}');
  DateTime? get lastSeenAt => DateTime.tryParse('${raw['last_seen_at']}');
}

class ZiroCharge {
  ZiroCharge(this.raw);
  final Map<String, dynamic> raw;
  String get chargeId => raw['charge_id'] as String;
  BigInt get amountBase => _big(raw['amount_base']);
  String get amountLabel => raw['amount_label'] as String? ?? '';
  ZiroEnclaveRef get enclave => ZiroEnclaveRef.fromJson(_map(raw['enclave']));
}

class ZiroChallenge {
  ZiroChallenge(this.raw);
  final Map<String, dynamic> raw;
  String get challengeId => raw['challenge_id'] as String;
  List<String> get colours => (raw['colours'] as List? ?? []).cast<String>();
  int get colourMs => (raw['colour_ms'] as num?)?.toInt() ?? 120;
  String get nonceB64 => raw['nonce'] as String? ?? '';
  BigInt get expiresMs => _big(raw['expires_ms']);
  String get enclaveSig => raw['enclave_sig'] as String? ?? '';
}

/// The enclave's signed approval. Kept as the raw map: it goes to core
/// exactly as received.
class ZiroApproval {
  ZiroApproval(this.raw);
  final Map<String, dynamic> raw;
  String get chargeId => raw['charge_id'] as String? ?? '';
  String get merchantAddress => raw['merchant_address'] as String? ?? '';
  String get allowanceId => raw['allowance_id'] as String? ?? '';
  String get accountId => raw['account_id'] as String? ?? '';
  BigInt get amountBase => _big(raw['amount_base']);
  BigInt get feeBase => _big(raw['fee_base']);
  BigInt get seq => _big(raw['seq']);
  BigInt get expiresMs => _big(raw['expires_ms']);
  bool get pinUsed => raw['pin_used'] == true;
  String get enclavePk => raw['enclave_pk'] as String? ?? '';
  String get signature => raw['signature'] as String? ?? '';
}

class ZiroDisplay {
  const ZiroDisplay({required this.firstName, this.avatarUrl});
  final String firstName;
  final String? avatarUrl;
}

/// `/v1/scan` and `/v1/pin` outcomes, discriminated by `result`.
sealed class ZiroScanResult {
  const ZiroScanResult();

  factory ZiroScanResult.fromJson(Map<String, dynamic> j) {
    switch (j['result']) {
      case 'approved':
        return ZiroApproved(ZiroApproval(_map(j['approval'])));
      case 'pin_required':
        final d = j['display'];
        return ZiroPinRequired(
          scanId: j['scan_id'] as String,
          reason: j['reason'] as String? ?? '',
          display: d is Map && (d['first_name'] as String?)?.isNotEmpty == true
              ? ZiroDisplay(
                  firstName: d['first_name'] as String,
                  avatarUrl: d['avatar_url'] as String?,
                )
              : null,
        );
      case 'not_found':
        return ZiroNotFound(retryAllowed: j['retry_allowed'] == true);
      case 'pin_wrong':
        return ZiroPinWrong((j['attempts_left'] as num?)?.toInt() ?? 0);
      case 'refused':
        return ZiroRefused(
          code: j['code'] as String? ?? '',
          message: j['message'] as String? ?? '',
        );
      default:
        return const ZiroRefused(code: 'UNAVAILABLE', message: '');
    }
  }
}

final class ZiroApproved extends ZiroScanResult {
  const ZiroApproved(this.approval);
  final ZiroApproval approval;
}

final class ZiroPinRequired extends ZiroScanResult {
  const ZiroPinRequired({
    required this.scanId,
    required this.reason,
    required this.display,
  });
  final String scanId;
  final String reason;

  /// Null when the PIN is choosing between close matches: no name then.
  final ZiroDisplay? display;
}

final class ZiroNotFound extends ZiroScanResult {
  const ZiroNotFound({required this.retryAllowed});
  final bool retryAllowed;
}

final class ZiroPinWrong extends ZiroScanResult {
  const ZiroPinWrong(this.attemptsLeft);
  final int attemptsLeft;
}

final class ZiroRefused extends ZiroScanResult {
  const ZiroRefused({required this.code, required this.message});
  final String code;
  final String message;
}

class ZiroSettled {
  ZiroSettled(this.raw);
  final Map<String, dynamic> raw;
  String get status => raw['status'] as String? ?? '';
  String get paymentId => raw['payment_id'] as String? ?? '';
  String get amountLabel => raw['amount_label'] as String? ?? '';
  String get feeLabel => raw['fee_label'] as String? ?? '';
  String get netLabel => raw['net_label'] as String? ?? '';
  String? get customerFirstName => raw['customer_first_name'] as String?;
}

class ZiroMerchantPayment {
  ZiroMerchantPayment(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id'] as String;
  String get amountLabel => raw['amount_label'] as String? ?? '';
  String get feeLabel => raw['fee_label'] as String? ?? '';
  String get netLabel => raw['net_label'] as String? ?? '';
  String get customer => raw['customer'] as String? ?? '';
  bool get pinUsed => raw['pin_used'] == true;
  DateTime? get createdAt => DateTime.tryParse('${raw['created_at']}');
  String get status => raw['status'] as String? ?? '';
  String? get refundedLabel => raw['refunded_label'] as String?;

  /// Not in contracts §5; read when core sends it, to cap a refund.
  BigInt? get amountBase => _bigOrNull(raw['amount_base']);
}

class ZiroMerchantPayments {
  ZiroMerchantPayments(this.raw);
  final Map<String, dynamic> raw;
  String get todayTotalLabel => _map(raw['today'])['total_label'] as String? ?? '';
  int get todayCount => (_map(raw['today'])['count'] as num?)?.toInt() ?? 0;
  List<ZiroMerchantPayment> get payments => (raw['payments'] as List? ?? [])
      .map((p) => ZiroMerchantPayment(_map(p)))
      .toList();
}

class ZiroCustomerPayment {
  ZiroCustomerPayment(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id'] as String;
  String get merchant => raw['merchant'] as String? ?? '';
  String get amountLabel => raw['amount_label'] as String? ?? '';
  bool get pinUsed => raw['pin_used'] == true;
  DateTime? get createdAt => DateTime.tryParse('${raw['created_at']}');
  String get status => raw['status'] as String? ?? '';
  bool get disputed => raw['disputed'] == true;
}

class ZiroCustomerStatus {
  ZiroCustomerStatus(this.raw);
  final Map<String, dynamic> raw;

  /// none | enrolling | active | paused | deleted
  String get status => raw['status'] as String? ?? 'none';
  bool get isOn => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isSetUp => status == 'active' || status == 'paused';
  bool get faceOptIn => raw['face_opt_in'] == true;
  ZiroLimits get limits => ZiroLimits.fromJson(raw);
  DateTime? get allowanceExpiresAt =>
      DateTime.tryParse('${raw['allowance_expires_at']}');
  String? get pausedReason => raw['paused_reason'] as String?;
  Map<String, dynamic> get _labels => _map(raw['labels']);
  String get perPaymentMaxLabel => _labels['per_payment_max'] as String? ?? '';
  String get noPinMaxLabel => _labels['no_pin_max'] as String? ?? '';
  String get dailyMaxLabel => _labels['daily_max'] as String? ?? '';
}

/// A customer transaction core built and sponsored, for this phone to check
/// and sign.
class ZiroSponsoredTx {
  ZiroSponsoredTx(this.raw);
  final Map<String, dynamic> raw;
  String get purpose => raw['purpose'] as String? ?? '';
  String get transactionDataBcs => raw['transaction_data_bcs'] as String;
  String get sponsorSignature => raw['sponsor_signature'] as String? ?? '';
  Map<String, dynamic> get summary => _map(raw['summary']);

  static ZiroSponsoredTx? maybe(Object? v) =>
      v is Map && v['transaction_data_bcs'] is String
      ? ZiroSponsoredTx(_map(v))
      : null;
}

class ZiroEnrollStart {
  ZiroEnrollStart(this.raw);
  final Map<String, dynamic> raw;
  String get ticket => raw['ticket'] as String;
  ZiroEnclaveRef get enclave => ZiroEnclaveRef.fromJson(_map(raw['enclave']));
  ZiroConfig? get config =>
      raw['config'] is Map ? ZiroConfig(_map(raw['config'])) : null;
}

/// `/v1/enroll` and `/v1/records/update` response.
class ZiroReceipt {
  ZiroReceipt(this.raw);
  final Map<String, dynamic> raw;
  String get recordId => raw['record_id'] as String;
  String get commitmentHex => (raw['commitment_hex'] as String).toLowerCase();
  String get receiptSig => raw['receipt_sig'] as String;
  String get enclavePk => raw['enclave_pk'] as String;
}
