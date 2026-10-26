import '../services/payment_rail_models.dart';

class CryptoSendQuote {
  const CryptoSendQuote({
    required this.quoteId,
    required this.rail,
    required this.dextopusDepositAddress,
    required this.estimatedReceiveAmount,
    required this.estimatedFeeUsdc,
    required this.expiresAt,
    required this.destinationChainDisplay,
    required this.isNativeSolana,
    this.blockhash,
    this.feePayer,
    this.envelope,
  });

  final String quoteId;

  /// On-chain rail the client funds the send with: "sui" or "solana".
  final String rail;

  final String dextopusDepositAddress;
  final String estimatedReceiveAmount;
  final double estimatedFeeUsdc;
  final DateTime expiresAt;
  final String destinationChainDisplay;
  final bool isNativeSolana;

  /// Solana rail: recent blockhash used to build the user-signed transfer.
  final String? blockhash;

  /// Solana rail: fee-payer public key included as the transaction fee-payer.
  final String? feePayer;

  /// Sui rail: the unsigned gasless-transfer envelope the client must sign.
  final RailEnvelope? envelope;

  bool get isSui => rail == 'sui';

  factory CryptoSendQuote.fromJson(Map<String, dynamic> json) {
    final envelopeJson = json['envelope'];
    return CryptoSendQuote(
      quoteId: json['quote_id'] as String,
      rail: json['rail'] as String? ?? 'solana',
      dextopusDepositAddress: json['dextopus_deposit_address'] as String,
      estimatedReceiveAmount: json['estimated_receive_amount'] as String,
      estimatedFeeUsdc: (json['estimated_fee_usdc'] as num).toDouble(),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      destinationChainDisplay: json['destination_chain_display'] as String,
      isNativeSolana: json['is_native_solana'] as bool? ?? false,
      blockhash: json['blockhash'] as String?,
      feePayer: json['fee_payer'] as String?,
      envelope: envelopeJson is Map<String, dynamic>
          ? RailEnvelope.fromJson(envelopeJson)
          : null,
    );
  }
}

class CryptoSendResult {
  const CryptoSendResult({
    required this.sendId,
    this.txSignature,
    this.solanaTxSignature,
    required this.status,
  });

  final String sendId;

  /// Rail-neutral settlement transaction id (Solana signature or Sui digest).
  final String? txSignature;

  /// Retained for backward compatibility; populated only on the Solana rail.
  final String? solanaTxSignature;
  final String status;

  factory CryptoSendResult.fromJson(Map<String, dynamic> json) =>
      CryptoSendResult(
        sendId: json['send_id'] as String,
        txSignature:
            json['tx_signature'] as String? ??
            json['solana_tx_signature'] as String?,
        solanaTxSignature: json['solana_tx_signature'] as String?,
        status: json['status'] as String,
      );
}
