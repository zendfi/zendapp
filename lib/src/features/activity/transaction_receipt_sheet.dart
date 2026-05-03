import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_models.dart';
import '../send/send_flow_sheet.dart';

/// Opens the transaction receipt as a bottom sheet.
Future<void> showTransactionReceipt(
  BuildContext context, {
  required ZendTransaction tx,
}) {
  final entry = tx.entry;
  if (entry == null) return Future.value();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReceiptSheet(tx: tx, entry: entry),
  );
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

    // Status visuals
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

    // Amount — strip sign, format cleanly
    final rawAmount = entry.amountUsdc;
    final amountDouble = double.tryParse(rawAmount) ?? 0.0;
    final amountStr = '\$${amountDouble.toStringAsFixed(2)}';
    final directionLabel = isSent ? 'Sent to' : 'Received from';

    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.72,
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
                      child: Icon(statusIcon,
                          color: statusColor, size: 30),
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
                        color: isSent
                            ? zt.textPrimary
                            : ZendColors.positive,
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

                  // ── Send again (only for sent transactions) ──
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

                  // ── Close ──
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
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              color: zt.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: mono ? 'DMMono' : 'DMSans',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? zt.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
