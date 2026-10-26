/// Models for the Add Cash flow — funding a Zend balance from outside Zend.
///
/// Both rails deliberately return *instructions* rather than a payment
/// session: crypto gives an address, NGN gives bank transfer details. Nothing
/// here collects card data or drives a redirect, which is why this flow lives
/// in the app rather than on a hosted page.
library;

import '../core/zend_format.dart';

/// One fundable chain, from `GET /api/v1/public/chains`.
class DepositChain {
  const DepositChain({
    required this.chainId,
    required this.symbol,
    required this.blockchainName,
    required this.displayName,
    required this.isStablecoin,
  });

  final int chainId;
  final String symbol;
  final String blockchainName;
  final String displayName;

  /// Stablecoin chains get a *static* per-user deposit address that can be
  /// reused indefinitely. Non-stablecoin chains route through the user's own
  /// wallet address instead — see [DepositAddress.isStatic].
  final bool isStablecoin;

  factory DepositChain.fromJson(Map<String, dynamic> json) => DepositChain(
    chainId: (json['chain_id'] as num).toInt(),
    symbol: json['symbol'] as String? ?? '',
    blockchainName: json['blockchain_name'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    isStablecoin: json['is_stablecoin'] as bool? ?? false,
  );
}

/// A deposit address for one chain, from
/// `GET /api/v1/public/zend/:zendtag/crypto-deposit-address?chain_id=`.
class DepositAddress {
  const DepositAddress({
    required this.depositAddress,
    required this.symbol,
    required this.blockchainName,
    required this.displayName,
    required this.isStatic,
    this.expiresAt,
  });

  final String depositAddress;
  final String symbol;
  final String blockchainName;
  final String displayName;

  /// True when this address is permanent and safe to reuse. False means it
  /// was minted for this deposit and may carry an [expiresAt] — the UI has
  /// to say so rather than inviting the user to save it.
  final bool isStatic;

  final DateTime? expiresAt;

  factory DepositAddress.fromJson(Map<String, dynamic> json) => DepositAddress(
    depositAddress: json['deposit_address'] as String,
    symbol: json['symbol'] as String? ?? '',
    blockchainName: json['blockchain_name'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    isStatic: json['is_static'] as bool? ?? false,
    expiresAt: (json['expires_at'] as String?) != null
        ? DateTime.tryParse(json['expires_at'] as String)
        : null,
  );
}

/// Money that arrived from outside Zend, from the `funds_added` SSE event.
///
/// Emitted alongside `balance_update` — that one drives the balance refresh,
/// this one carries the detail needed to tell the user *what* landed.
class FundsArrivedNotification {
  const FundsArrivedNotification({
    required this.amountUsdc,
    required this.source,
    required this.sourceLabel,
    this.originAmount,
    this.originCurrency,
  });

  /// Credited to the Zend balance, in USD.
  final double amountUsdc;

  /// Machine-readable rail: `crypto` or `bank_transfer`.
  final String source;

  /// Human label for the UI, e.g. "USDC deposit" or "Bank transfer".
  final String sourceLabel;

  /// What the user actually parted with, when it differs from [amountUsdc] —
  /// e.g. 50000 with [originCurrency] `NGN`. Null for USD-denominated
  /// deposits, where repeating the same figure twice would just be noise.
  final double? originAmount;
  final String? originCurrency;

  bool get isBankTransfer => source == 'bank_transfer';

  /// "$32.40", the amount added to the balance.
  String get amountLabel => formatUsd(amountUsdc);

  /// "₦50,000" when the deposit came in another currency, else null.
  String? get originLabel {
    final amount = originAmount;
    final currency = originCurrency;
    if (amount == null || currency == null || currency.isEmpty) return null;
    final symbol = switch (currency.toUpperCase()) {
      'NGN' => '₦',
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '',
    };
    final whole = amount.round().toString();
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }
    return symbol.isEmpty
        ? '$grouped ${currency.toUpperCase()}'
        : '$symbol$grouped';
  }

  factory FundsArrivedNotification.fromJson(Map<String, dynamic> json) {
    double? parse(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
    return FundsArrivedNotification(
      amountUsdc: parse(json['amount_usdc']) ?? 0,
      source: json['source'] as String? ?? '',
      sourceLabel: json['source_label'] as String? ?? 'Added',
      originAmount: parse(json['origin_amount']),
      originCurrency: json['origin_currency'] as String?,
    );
  }
}

/// Bank transfer instructions for an NGN pay-in, from
/// `POST /api/v1/public/zend/:zendtag/ngn-payin/prepare`.
///
/// The user moves [fiatAmount] naira to [accountNumber] from their own bank,
/// and the provider webhook credits [usdcAmount] once it settles. Nothing is
/// charged by the app.
class NgnPayinInstructions {
  const NgnPayinInstructions({
    required this.orderId,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
    required this.fiatAmount,
    required this.exchangeRate,
    required this.usdcAmount,
    required this.recipientZendtag,
    required this.recipientDisplayName,
  });

  final String orderId;
  final String bankName;
  final String accountNumber;
  final String accountName;

  /// Amount to transfer, in naira.
  final double fiatAmount;

  /// NGN per USD used for this quote.
  final double exchangeRate;

  /// What lands in the Zend balance once the transfer settles.
  final double usdcAmount;

  final String recipientZendtag;
  final String recipientDisplayName;

  factory NgnPayinInstructions.fromJson(Map<String, dynamic> json) =>
      NgnPayinInstructions(
        orderId: json['order_id'] as String,
        bankName: json['bank_name'] as String? ?? '',
        accountNumber: json['account_number'] as String? ?? '',
        accountName: json['account_name'] as String? ?? '',
        fiatAmount: (json['fiat_amount'] as num?)?.toDouble() ?? 0,
        exchangeRate: (json['exchange_rate'] as num?)?.toDouble() ?? 0,
        usdcAmount: (json['usdc_amount'] as num?)?.toDouble() ?? 0,
        recipientZendtag: json['recipient_zendtag'] as String? ?? '',
        recipientDisplayName: json['recipient_display_name'] as String? ?? '',
      );
}
