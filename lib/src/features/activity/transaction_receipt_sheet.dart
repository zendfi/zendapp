import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/activity_edge.dart';
import '../../models/api_models.dart';
import '../send/send_flow_sheet.dart';

const _kCuratedEmojis = ['🔥', '💰', '🙏', '👑', '😭', '⚡', '🎯', '💸', '🎉', '👀', '✅', '🚀'];

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

class _ReceiptSheet extends StatefulWidget {
  const _ReceiptSheet({required this.tx, required this.entry});

  final ZendTransaction tx;
  final TransferHistoryEntry entry;

  @override
  State<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<_ReceiptSheet> {
  TransferHistoryEntry get entry => widget.entry;
  ZendTransaction get tx => widget.tx;

  List<EdgeReactionCount> _reactions = const [];
  List<EdgeComment> _comments = const [];
  bool _loadingSocial = true;
  final TextEditingController _commentController = TextEditingController();
  bool _postingComment = false;

  @override
  void initState() {
    super.initState();
    _loadSocial();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadSocial() async {
    final model = ZendScope.of(context);
    try {
      final results = await Future.wait([
        model.activityDataService.getEdgeReactions('zend_transfer', entry.id),
        model.activityDataService.getEdgeComments('zend_transfer', entry.id),
      ]);
      if (mounted) {
        setState(() {
          _reactions = results[0] as List<EdgeReactionCount>;
          _comments = results[1] as List<EdgeComment>;
        });
      }
    } catch (_) {
      // Non-fatal — the receipt still renders without the social section.
    } finally {
      if (mounted) setState(() => _loadingSocial = false);
    }
  }

  Future<void> _toggleReaction(String emoji) async {
    final model = ZendScope.of(context);
    final existing = _reactions.where((r) => r.emoji == emoji).firstOrNull;
    final alreadyReacted = existing?.reactedByMe ?? false;

    setState(() {
      final updated = List<EdgeReactionCount>.of(_reactions);
      final idx = updated.indexWhere((r) => r.emoji == emoji);
      if (alreadyReacted && idx != -1) {
        final newCount = updated[idx].count - 1;
        if (newCount <= 0) {
          updated.removeAt(idx);
        } else {
          updated[idx] = EdgeReactionCount(emoji: emoji, count: newCount, reactedByMe: false);
        }
      } else if (idx != -1) {
        updated[idx] = EdgeReactionCount(emoji: emoji, count: updated[idx].count + 1, reactedByMe: true);
      } else {
        updated.add(EdgeReactionCount(emoji: emoji, count: 1, reactedByMe: true));
      }
      _reactions = updated;
    });

    try {
      if (alreadyReacted) {
        await model.activityDataService.removeEdgeReaction('zend_transfer', entry.id, emoji);
      } else {
        await model.activityDataService.addEdgeReaction('zend_transfer', entry.id, emoji);
      }
    } catch (_) {
      if (mounted) _loadSocial();
    }
  }

  Future<void> _postComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty || _postingComment) return;
    final model = ZendScope.of(context);
    setState(() => _postingComment = true);
    try {
      await model.activityDataService.addEdgeComment('zend_transfer', entry.id, body);
      _commentController.clear();
      await _loadSocial();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not post comment — try again', style: TextStyle(fontFamily: 'DMSans'))),
        );
      }
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  Future<void> _deleteComment(EdgeComment comment) async {
    final model = ZendScope.of(context);
    setState(() => _comments = _comments.where((c) => c.id != comment.id).toList());
    try {
      await model.activityDataService.deleteEdgeComment('zend_transfer', entry.id, comment.id);
    } catch (_) {
      if (mounted) _loadSocial();
    }
  }

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

                  const SizedBox(height: 24),

                  // ── Reactions + comments (Req: sender/recipient-only
                  // comment writes, anyone-authorized-to-view reads) ──
                  if (!_loadingSocial) _ReactionRow(reactions: _reactions, onTap: _toggleReaction),
                  const SizedBox(height: 16),
                  if (!_loadingSocial)
                    _CommentsSection(
                      comments: _comments,
                      currentUserId: model.currentUserId,
                      controller: _commentController,
                      posting: _postingComment,
                      onSubmit: _postComment,
                      onDelete: _deleteComment,
                    ),

                  const SizedBox(height: 24),

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

// ── Reactions row ────────────────────────────────────────────────────────────

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.reactions, required this.onTap});

  final List<EdgeReactionCount> reactions;
  final void Function(String emoji) onTap;

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final zt = ZendTheme.of(sheetContext);
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(color: zt.bgSecondary, borderRadius: BorderRadius.circular(ZendRadii.xxl)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: zt.border, borderRadius: BorderRadius.circular(ZendRadii.pill)),
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final emoji in _kCuratedEmojis)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onTap(emoji);
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: zt.bgPrimary, borderRadius: BorderRadius.circular(ZendRadii.lg)),
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final r in reactions)
          GestureDetector(
            onTap: () => onTap(r.emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: r.reactedByMe ? zt.accent.withValues(alpha: 0.18) : zt.bgSecondary,
                borderRadius: BorderRadius.circular(ZendRadii.pill),
                border: r.reactedByMe ? Border.all(color: zt.accent.withValues(alpha: 0.5)) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text('${r.count}', style: TextStyle(fontFamily: 'DMMono', fontSize: 12, color: zt.textSecondary)),
                ],
              ),
            ),
          ),
        GestureDetector(
          onTap: () => _showPicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: zt.bgSecondary, borderRadius: BorderRadius.circular(ZendRadii.pill)),
            child: Icon(Icons.add_reaction_outlined, size: 16, color: zt.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ── Comments section (sender/recipient-only writes) ─────────────────────────

class _CommentsSection extends StatelessWidget {
  const _CommentsSection({
    required this.comments,
    required this.currentUserId,
    required this.controller,
    required this.posting,
    required this.onSubmit,
    required this.onDelete,
  });

  final List<EdgeComment> comments;
  final String? currentUserId;
  final TextEditingController controller;
  final bool posting;
  final VoidCallback onSubmit;
  final void Function(EdgeComment) onDelete;

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (comments.isNotEmpty) ...[
          Text(
            'Comments',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: zt.textSecondary),
          ),
          const SizedBox(height: 8),
          for (final comment in comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '@${comment.authorZendtag}',
                              style: TextStyle(fontFamily: 'DMSans', fontSize: 12.5, fontWeight: FontWeight.w700, color: zt.textPrimary),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _relativeTime(comment.createdAt),
                              style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5, color: zt.textSecondary.withValues(alpha: 0.8)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          comment.body,
                          style: TextStyle(fontFamily: 'DMSans', fontSize: 13.5, color: zt.textPrimary.withValues(alpha: 0.9)),
                        ),
                      ],
                    ),
                  ),
                  if (comment.authorUserId == currentUserId)
                    GestureDetector(
                      onTap: () => onDelete(comment),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline, size: 16, color: zt.textSecondary.withValues(alpha: 0.6)),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
        ],
        // Composer — only sender/recipient can post (enforced server-side;
        // shown to everyone here since a non-participant viewer only ever
        // sees this sheet via their own transfer, so this path is unreachable
        // for a Shared_Network_Viewer in practice).
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLength: 280,
                maxLines: 3,
                minLines: 1,
                style: TextStyle(fontFamily: 'DMSans', fontSize: 13.5, color: zt.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Add a comment…',
                  hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 13.5, color: zt.textSecondary),
                  filled: true,
                  fillColor: zt.bgSecondary,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZendRadii.lg), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: posting ? null : onSubmit,
              icon: posting
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: zt.accent))
                  : Icon(Icons.send_rounded, color: zt.accent),
            ),
          ],
        ),
      ],
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
