class CryptoSendQuote {
  const CryptoSendQuote({
    required this.quoteId,
    required this.dextopusDepositAddress,
    required this.estimatedReceiveAmount,
    required this.estimatedFeeUsdc,
    required this.expiresAt,
    required this.destinationChainDisplay,
    required this.isNativeSolana,
    required this.blockhash,
    required this.feePayer,
  });

  final String quoteId;
  final String dextopusDepositAddress;
  final String estimatedReceiveAmount;
  final double estimatedFeeUsdc;
  final DateTime expiresAt;
  final String destinationChainDisplay;
  final bool isNativeSolana;
  /// Recent Solana blockhash — used to build the user-signed transfer transaction.
  final String blockhash;
  /// Fee-payer public key — included in the transaction as the fee-payer account.
  final String feePayer;

  factory CryptoSendQuote.fromJson(Map<String, dynamic> json) => CryptoSendQuote(
        quoteId: json['quote_id'] as String,
        dextopusDepositAddress: json['dextopus_deposit_address'] as String,
        estimatedReceiveAmount: json['estimated_receive_amount'] as String,
        estimatedFeeUsdc: (json['estimated_fee_usdc'] as num).toDouble(),
        expiresAt: DateTime.parse(json['expires_at'] as String),
        destinationChainDisplay: json['destination_chain_display'] as String,
        isNativeSolana: json['is_native_solana'] as bool? ?? false,
        blockhash: json['blockhash'] as String,
        feePayer: json['fee_payer'] as String,
      );
}

class CryptoSendResult {
  const CryptoSendResult({
    required this.sendId,
    this.solanaTxSignature,
    required this.status,
  });

  final String sendId;
  final String? solanaTxSignature;
  final String status;

  factory CryptoSendResult.fromJson(Map<String, dynamic> json) => CryptoSendResult(
        sendId: json['send_id'] as String,
        solanaTxSignature: json['solana_tx_signature'] as String?,
        status: json['status'] as String,
      );
}
