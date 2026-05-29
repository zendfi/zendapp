import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_models.dart';
import '../send/send_flow_sheet.dart';

/// Opens the transaction receipt as a full-screen bottom sheet.
/// Handles both zend-to-zend transfers (entry != null) and bank sends (bankOrder != null).
Future<void> showTransactionReceipt(
  BuildContext context, {
  required ZendTransaction tx,
}) {
  // Zend-to-zend transfer
  if (tx.entry != null) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReceiptSheet(tx: tx, entry: tx.entry!),
    );
  }

  if (tx.bankOrder != null) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BankSendReceiptSheet(tx: tx, order: tx.bankOrder!),
    );
  }

  return Future.value();
}

class _ReceiptSheet extends StatelessWidget {
  const _ReceiptSheet({required this.tx, required this.entry});

  final ZendTransaction tx;
  final TransferHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final isSent = entry.senderZendtag == model.currentZendtag;
    final counterparty =
        isSent ? entry.recipientZendtag : entry.senderZendtag;
    final isConfirmed = entry.status == 'confirmed';
    final isPending = entry.status == 'pending';

    final statusColor = isConfirmed
        ? ZendColors.positive
        : isPending
            ? ZendColors.accentPop
            : ZendColors.destructive;
    final statusIcon = isConfirmed
        ? Icons.check_rounded
        : isPending
            ? Icons.hourglass_top_rounded
            : Icons.close_rounded;
    final statusLabel = isConfirmed
        ? 'Confirmed'
        : isPending
            ? 'Processing'
            : 'Failed';

    final rawAmount = entry.amountUsdc;
    final amountDouble = double.tryParse(rawAmount) ?? 0.0;
    final amountStr = '\$${amountDouble.toStringAsFixed(2)}';
    final directionLabel = isSent ? 'Sent to' : 'Received from';

    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      // Full screen height
      height: screenHeight,
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          const ZendSheetHandle(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Status icon ──
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 30),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Amount ──
                  Center(
                    child: Text(
                      amountStr,
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 48,
                        fontStyle: FontStyle.italic,
                        height: 1.0,
                        color: isSent ? zt.textPrimary : ZendColors.positive,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // ── Direction ──
                  Center(
                    child: Text(
                      '$directionLabel @$counterparty',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        color: zt.textSecondary,
                      ),
                    ),
                  ),

                  // ── Note ──
                  if (entry.note != null && entry.note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: zt.bgSecondary,
                          borderRadius:
                              BorderRadius.circular(ZendRadii.pill),
                        ),
                        child: Text(
                          '"${entry.note}"',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: zt.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // ── Details card ──
                  Container(
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(ZendRadii.xxl),
                    ),
                    child: Column(
                      children: [
                        _DetailRow(
                          label: 'From',
                          value: '@${entry.senderZendtag}',
                          mono: true,
                        ),
                        Divider(color: zt.border, height: 1),
                        _DetailRow(
                          label: 'To',
                          value: '@${entry.recipientZendtag}',
                          mono: true,
                        ),
                        Divider(color: zt.border, height: 1),
                        _DetailRow(
                          label: 'Date',
                          value: _formatDate(entry.createdAt),
                        ),
                        Divider(color: zt.border, height: 1),
                        _DetailRow(
                          label: 'Status',
                          value: statusLabel,
                          valueColor: statusColor,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  if (isSent) ...[
                    PrimaryButton(
                      label: 'Send again',
                      onPressed: () {
                        Navigator.of(context).pop();
                        showSendFlowSheet(
                          context,
                          amount: amountDouble,
                          prefilledRecipient: entry.recipientZendtag,
                          prefilledNote: entry.note,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  OutlineActionButton(
                    label: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '${months[local.month - 1]} ${local.day}, ${local.year} · $hour:$minute $period';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool mono;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              color: zt.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: mono ? 'DMMono' : 'DMSans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? zt.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bank Send Receipt ─────────────────────────────────────────────────────────

class _BankSendReceiptSheet extends StatelessWidget {
  const _BankSendReceiptSheet({required this.tx, required this.order});

  final ZendTransaction tx;
  final Map<String, dynamic> order;

  /// Human-readable rail label.
  /// NGN → NIBSS, intl rails → ACH / Faster Payments / SEPA
  String _railLabel(String rail, String? paymentRail) {
    if (rail == 'ngn') return 'NIBSS';
    // intl — use the bridge payment_rail if available
    return switch (paymentRail?.toLowerCase()) {
      'ach' => 'ACH',
      'faster_payments' => 'Faster Payments',
      'sepa' => 'SEPA',
      _ => 'International',
    };
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    final amountUsdc = (order['amount_usdc'] as num?)?.toDouble() ?? 0.0;
    final fiatAmount = (order['fiat_amount'] as num?)?.toDouble();
    final fiatCurrency = order['fiat_currency'] as String? ?? '';
    final bankName = order['bank_name'] as String? ?? '';
    final accountName = order['account_name'] as String?;
    final accountMasked = order['account_number_masked'] as String?;
    final rail = order['rail'] as String? ?? 'ngn';
    final paymentRail = order['payment_rail'] as String?;
    final status = order['status'] as String? ?? '';
    final createdAtStr = order['created_at'] as String? ?? '';
    final createdAt = DateTime.tryParse(createdAtStr) ?? tx.createdAt;

    // Once funds are sent on-chain (status = 'paid' or 'completed'),
    // show green tick — the user's obligation is fulfilled.
    final isSent = status == 'paid' || status == 'completed';
    final statusColor = isSent
        ? ZendColors.positive
        : status == 'failed'
            ? ZendColors.destructive
            : ZendColors.accentPop;
    final statusIcon = isSent
        ? Icons.check_rounded
        : status == 'failed'
            ? Icons.close_rounded
            : Icons.hourglass_top_rounded;
    final statusLabel = switch (status) {
      'completed' => 'Delivered',
      'paid' => 'Sent',
      'processing' => 'Processing',
      'failed' => 'Failed',
      'expired' => 'Expired',
      _ => 'Processing',
    };

    final amountStr = amountUsdc == amountUsdc.roundToDouble()
        ? '\$${amountUsdc.toStringAsFixed(0)}'
        : '\$${amountUsdc.toStringAsFixed(2)}';

    final fiatSymbol = switch (fiatCurrency) {
      'NGN' => '₦',
      'GBP' => '£',
      'EUR' => '€',
      _ => '\$',
    };

    final railLabel = _railLabel(rail, paymentRail);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      // Full screen height
      height: screenHeight,
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          const ZendSheetHandle(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Status icon ──
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 30),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Amount ──
                  Center(
                    child: Text(
                      amountStr,
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 48,
                        fontStyle: FontStyle.italic,
                        height: 1.0,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),

                  // ── Fiat equivalent ──
                  if (fiatAmount != null && fiatAmount > 0) ...[
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        '$fiatSymbol${_formatFiatValue(fiatAmount, fiatCurrency)} $fiatCurrency',
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 15,
                          color: zt.textSecondary,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      accountName != null && accountName.isNotEmpty
                          ? 'Sent to $accountName'
                          : bankName.isNotEmpty
                              ? 'Sent to $bankName'
                              : 'Bank transfer',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        color: zt.textSecondary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Details card ──
                  Container(
                    decoration: BoxDecoration(
                      color: zt.bgSecondary,
                      borderRadius: BorderRadius.circular(ZendRadii.xxl),
                    ),
                    child: Column(
                      children: [
                        // Account holder
                        if (accountName != null && accountName.isNotEmpty) ...[
                          _DetailRow(label: 'To', value: accountName),
                          Divider(color: zt.border, height: 1),
                        ],
                        // Bank
                        if (bankName.isNotEmpty) ...[
                          _DetailRow(label: 'Bank', value: bankName),
                          Divider(color: zt.border, height: 1),
                        ],
                        // Account number
                        if (accountMasked != null && accountMasked.isNotEmpty) ...[
                          _DetailRow(label: 'Account', value: accountMasked, mono: true),
                          Divider(color: zt.border, height: 1),
                        ],
                        // Rail
                        _DetailRow(label: 'Rail', value: railLabel),
                        Divider(color: zt.border, height: 1),
                        // Currency
                        if (fiatCurrency.isNotEmpty) ...[
                          _DetailRow(label: 'Currency', value: fiatCurrency),
                          Divider(color: zt.border, height: 1),
                        ],
                        // Date
                        _DetailRow(label: 'Date', value: _formatDate(createdAt)),
                        Divider(color: zt.border, height: 1),
                        // Status
                        _DetailRow(
                          label: 'Status',
                          value: statusLabel,
                          valueColor: statusColor,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  OutlineActionButton(
                    label: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFiatValue(double value, String currency) {
    if (currency == 'NGN') {
      final rounded = value.round();
      final text = rounded.toString();
      final buf = StringBuffer();
      for (var i = 0; i < text.length; i++) {
        final fromEnd = text.length - i;
        buf.write(text[i]);
        if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
      }
      return buf.toString();
    }
    return value.toStringAsFixed(2);
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '${months[local.month - 1]} ${local.day}, ${local.year} · $hour:$minute $period';
  }
}
