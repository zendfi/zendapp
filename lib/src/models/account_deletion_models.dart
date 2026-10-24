/// Models for the account deletion flow.
///
/// Deletion is gated server-side on the wallet being empty, because the salt
/// that controls a zkLogin address is destroyed as part of it and for some
/// accounts the server holds the only copy. The readiness probe exists so the
/// UI can explain that up front instead of surfacing it as a failed attempt.
library;

/// What the signed-in user still holds on one rail.
class DeletionHolding {
  const DeletionHolding({
    required this.rail,
    required this.address,
    required this.usdcBalance,
    required this.awaitingDeposit,
  });

  factory DeletionHolding.fromJson(Map<String, dynamic> json) {
    return DeletionHolding(
      rail: json['rail'] as String? ?? '',
      address: json['address'] as String? ?? '',
      // Amounts cross this boundary as strings, matching the rest of the money
      // surface, so a balance is never put through a JSON float on the way in.
      usdcBalance: double.tryParse(json['usdc_balance'] as String? ?? '') ?? 0,
      awaitingDeposit:
          double.tryParse(json['awaiting_deposit'] as String? ?? '') ?? 0,
    );
  }

  final String rail;
  final String address;
  final double usdcBalance;

  /// Value sitting in coin objects that the gasless path can't move yet. Still
  /// the user's money, so the server counts it when deciding whether the wallet
  /// is empty.
  final double awaitingDeposit;

  String get railLabel => switch (rail) {
    'sui' => 'Sui',
    'solana' => 'Solana',
    _ => rail,
  };
}

/// Whether deletion can proceed, and what's stopping it if not.
class DeletionReadiness {
  const DeletionReadiness({
    required this.canDelete,
    required this.blockers,
    required this.holdings,
    required this.pendingTransferCount,
    required this.retentionYears,
  });

  factory DeletionReadiness.fromJson(Map<String, dynamic> json) {
    return DeletionReadiness(
      canDelete: json['can_delete'] as bool? ?? false,
      blockers:
          (json['blockers'] as List?)?.map((e) => e as String).toList() ??
          const [],
      holdings:
          (json['holdings'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map(DeletionHolding.fromJson)
              .toList() ??
          const [],
      pendingTransferCount: json['pending_transfer_count'] as int? ?? 0,
      retentionYears: json['retention_years'] as int? ?? 0,
    );
  }

  final bool canDelete;
  final List<String> blockers;
  final List<DeletionHolding> holdings;
  final int pendingTransferCount;

  /// How long transfer and identity records are kept for AML. Read from the
  /// server rather than hardcoded, so the figure the user is shown is the one
  /// actually applied.
  final int retentionYears;

  bool get blockedByBalance => blockers.contains('balance_not_empty');
  bool get blockedByPendingTransfers => blockers.contains('pending_transfers');

  /// Total still held across every rail.
  double get totalHeldUsdc =>
      holdings.fold(0, (sum, h) => sum + h.usdcBalance);
}
