class SavingsMetrics {
  final double apy;
  final double apy7d;
  final double apy30d;
  final double tvlUsd;
  final int totalHolders;
  final double monthlyYieldUsd;

  const SavingsMetrics({
    required this.apy,
    required this.apy7d,
    required this.apy30d,
    required this.tvlUsd,
    required this.totalHolders,
    this.monthlyYieldUsd = 0.0,
  });

  factory SavingsMetrics.fromJson(Map<String, dynamic> json) {
    return SavingsMetrics(
      apy: (json['apy'] as num).toDouble(),
      apy7d: (json['apy_7d'] as num).toDouble(),
      apy30d: (json['apy_30d'] as num).toDouble(),
      tvlUsd: (json['tvl_usd'] as num).toDouble(),
      totalHolders: json['total_holders'] as int,
      monthlyYieldUsd: (json['monthly_yield_usd'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SavingsPosition {
  final bool hasPosition;
  final double principalUsd;
  final double currentValueUsd;
  final double grossYieldUsd;
  final double netYieldUsd;
  final double feeUsd;
  final int feeBps;

  const SavingsPosition({
    required this.hasPosition,
    required this.principalUsd,
    required this.currentValueUsd,
    required this.grossYieldUsd,
    required this.netYieldUsd,
    required this.feeUsd,
    required this.feeBps,
  });

  factory SavingsPosition.fromJson(Map<String, dynamic> json) {
    return SavingsPosition(
      hasPosition: json['has_position'] as bool,
      principalUsd: (json['principal_usd'] as num).toDouble(),
      currentValueUsd: (json['current_value_usd'] as num).toDouble(),
      grossYieldUsd: (json['gross_yield_usd'] as num).toDouble(),
      netYieldUsd: (json['net_yield_usd'] as num).toDouble(),
      feeUsd: (json['fee_usd'] as num).toDouble(),
      feeBps: json['fee_bps'] as int,
    );
  }
}

class SavingsPrepareResponse {
  final String txBytesB64;
  final String blockhash;

  const SavingsPrepareResponse({
    required this.txBytesB64,
    required this.blockhash,
  });

  factory SavingsPrepareResponse.fromJson(Map<String, dynamic> json) {
    return SavingsPrepareResponse(
      txBytesB64: json['tx_bytes'] as String,
      blockhash: json['blockhash'] as String,
    );
  }
}

class SavingsSubmitResult {
  final bool success;
  final String transactionSignature;
  final String explorerUrl;

  const SavingsSubmitResult({
    required this.success,
    required this.transactionSignature,
    required this.explorerUrl,
  });

  factory SavingsSubmitResult.fromJson(Map<String, dynamic> json) {
    return SavingsSubmitResult(
      success: json['success'] as bool,
      transactionSignature: json['transaction_signature'] as String,
      explorerUrl: json['explorer_url'] as String,
    );
  }
}
