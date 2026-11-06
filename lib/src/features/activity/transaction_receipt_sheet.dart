import '../../design/zend_mark.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_note.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../design/zend_money.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/api_models.dart';
import '../send/send_flow_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../design/zend_modal.dart';
import '../../core/zend_format.dart';

/// Opens the transaction receipt as a full-screen bottom sheet.
/// Handles both zend-to-zend transfers (entry != null) and bank sends (bankOrder != null).
///
/// This is now a purely formal receipt — no reactions/comments here. Those
/// live in `activity_comment_sheet.dart`'s Twitter-style comment sheet,
/// which is the primary destination when an activity is tapped; this
/// receipt is one tap further in via that sheet's "Receipt" header button
/// (or reachable directly from flows that don't have a social angle, e.g.
/// Send_Flow's own confirmation).
Future<void> showTransactionReceipt(
  BuildContext context, {
  required ZendTransaction tx,
}) {
  // Zend-to-zend transfer
  if (tx.entry != null) {
    return showZendModalSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      inDetailPane: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReceiptSheet(tx: tx, entry: tx.entry!),
    );
  }

  if (tx.bankOrder != null) {
    return showZendModalSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      inDetailPane: true,
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

/// The receipt as a Zend moment rather than a bank statement: the note
/// (sticker, GIF or words) leads, then who paid whom as one sentence, the
/// amount, the two people, and the record tucked behind "Details".
class _ReceiptSheetState extends State<_ReceiptSheet> {
  final _cardKey = GlobalKey();
  bool _showDetails = false;
  bool _sharing = false;

  TransferHistoryEntry get entry => widget.entry;

  Future<void> _share(String fallbackText) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    await shareCaptured(_cardKey, fallbackText);
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final isSent = entry.senderZendtag == model.currentZendtag;
    final status = entry.status;
    final isDone = status == 'confirmed';
    final isPending = status == 'pending';
    final amount = double.tryParse(entry.amountUsdc) ?? 0.0;

    final me = personName(
      displayName: model.currentDisplayName,
      handle: model.currentZendtag,
    );
    final them = personName(
      displayName: isSent
          ? entry.recipientDisplayName
          : entry.senderDisplayName,
      handle: isSent ? entry.recipientZendtag : entry.senderZendtag,
    );
    final themTag = isSent ? entry.recipientZendtag : entry.senderZendtag;
    final themAvatar = isSent
        ? entry.recipientAvatarUrl
        : entry.senderAvatarUrl;
    final sentence = isSent ? 'You paid $them' : '$them paid you';
    final note = entry.note?.trim() ?? '';
    final hasNote = note.isNotEmpty;

    final statusLine = isDone
        ? null
        : isPending
        ? ('Still on its way', zt.pending)
        : ("That didn't go through. Try again.", zt.destructive);

    final shareText = [
      '$sentence ${formatMoney(amount)} on Zend',
      if (hasNote) noteText(note),
    ].join(' · ');

    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.sheet),
        ),
      ),
      child: Stack(
        children: [
          // Off-screen share card: rendered for capture, never seen here.
          Positioned(
            left: -2000,
            top: 0,
            child: RepaintBoundary(
              key: _cardKey,
              child: _ShareCard(
                sentence: sentence,
                amount: amount,
                note: hasNote ? note : null,
                seed: themTag,
              ),
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 14),
              const ZendSheetHandle(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── The note leads ──
                      Center(
                        child: hasNote
                            ? ZendNote(
                                note,
                                stickerSize: 88,
                                gifHeight: 200,
                                burst: !isSent,
                                textAlign: TextAlign.center,
                                textStyle: ZendTextStyles.title.copyWith(
                                  color: zt.textPrimary,
                                ),
                              )
                            : _PeoplePair(
                                meInitial: model.selfInitial,
                                meAvatar: model.currentAvatarUrl,
                                themName: them,
                                themAvatar: themAvatar,
                                themSeed: themTag,
                                outgoing: isSent,
                                size: 36,
                              ),
                      ),
                      const SizedBox(height: 24),
                      // ── Who paid whom, then how much ──
                      Text(
                        sentence,
                        textAlign: TextAlign.center,
                        style: ZendTextStyles.title.copyWith(
                          color: zt.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: ZendGlow(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 4,
                            ),
                            child: ZendAmount(
                              amount,
                              style: ZendTextStyles.displayL,
                              direction: isSent
                                  ? MoneyDirection.outgoing
                                  : MoneyDirection.incoming,
                            ),
                          ),
                        ),
                      ),
                      if (statusLine != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          statusLine.$1,
                          textAlign: TextAlign.center,
                          style: ZendTextStyles.caption.copyWith(
                            color: statusLine.$2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        formatRelativeTime(entry.createdAt),
                        textAlign: TextAlign.center,
                        style: ZendTextStyles.caption.copyWith(
                          color: zt.textSecondary,
                        ),
                      ),
                      if (hasNote) ...[
                        const SizedBox(height: 20),
                        Center(
                          child: _PeoplePair(
                            meInitial: model.selfInitial,
                            meAvatar: model.currentAvatarUrl,
                            themName: them,
                            themAvatar: themAvatar,
                            themSeed: themTag,
                            outgoing: isSent,
                            size: 22,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      // ── Actions ──
                      Row(
                        children: [
                          Expanded(
                            child: PrimaryButton(
                              label: isSent ? 'Zend again' : 'Zend back',
                              onPressed: () {
                                Navigator.of(context).pop();
                                showSendFlowSheet(
                                  context,
                                  amount: isSent ? amount : 0,
                                  prefilledRecipient: themTag,
                                  prefilledNote: isSent ? entry.note : null,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlineActionButton(
                              label: _sharing ? 'Sharing…' : 'Share',
                              onPressed: () => _share(shareText),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // ── The record, for support, folded away ──
                      Center(
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _showDetails = !_showDetails),
                          child: Text(
                            _showDetails ? 'Hide details' : 'Details',
                            style: ZendTextStyles.caption.copyWith(
                              color: zt.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      if (_showDetails)
                        Container(
                          decoration: BoxDecoration(
                            color: zt.bgSecondary,
                            borderRadius: BorderRadius.circular(ZendRadii.card),
                          ),
                          child: Column(
                            children: [
                              _DetailRow(
                                label: 'From',
                                value: isSent ? me : them,
                              ),
                              Divider(color: zt.border, height: 1),
                              _DetailRow(
                                label: 'To',
                                value: isSent ? them : me,
                              ),
                              Divider(color: zt.border, height: 1),
                              _DetailRow(
                                label: 'When',
                                value: formatDateTime(entry.createdAt),
                              ),
                              Divider(color: zt.border, height: 1),
                              _DetailRow(
                                label: 'Status',
                                value: isDone
                                    ? 'Done'
                                    : isPending
                                    ? 'On its way'
                                    : "Didn't go through",
                              ),
                              Divider(color: zt.border, height: 1),
                              _DetailRow(
                                label: 'Reference',
                                value: entry.id.length > 8
                                    ? entry.id.substring(0, 8).toUpperCase()
                                    : entry.id.toUpperCase(),
                                mono: true,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two avatars with a soft arrow between them: who the money went from and to.
class _PeoplePair extends StatelessWidget {
  const _PeoplePair({
    required this.meInitial,
    required this.meAvatar,
    required this.themName,
    required this.themAvatar,
    required this.themSeed,
    required this.outgoing,
    required this.size,
  });

  final String meInitial;
  final String? meAvatar;
  final String themName;
  final String? themAvatar;
  final String themSeed;
  final bool outgoing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final me = ZendAvatar(
      radius: size,
      photoUrl: meAvatar,
      initials: meInitial,
    );
    final them = ZendAvatar(
      radius: size,
      photoUrl: themAvatar,
      initials: themName.isEmpty ? '?' : themName[0].toUpperCase(),
      seed: themSeed,
    );
    return Semantics(
      label: outgoing ? 'From you to $themName' : 'From $themName to you',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          outgoing ? me : them,
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.4),
            child: Icon(
              PhosphorIconsRegular.arrowRight,
              size: size * 0.7,
              color: zt.textSecondary,
            ),
          ),
          outgoing ? them : me,
        ],
      ),
    );
  }
}

/// The image people share: a card tinted with the other person's colour,
/// the note, the sentence and the amount, with the Zend mark. Captured to
/// PNG; never shown on screen.
class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.sentence,
    required this.amount,
    required this.note,
    required this.seed,
  });

  final String sentence;
  final double amount;
  final String? note;
  final String seed;

  @override
  Widget build(BuildContext context) {
    final tint = ZendAvatar.colorFor(seed);
    const fg = Colors.white;
    return MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(tint, Colors.black, 0.15)!,
                Color.lerp(tint, Colors.black, 0.55)!,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (note != null) ...[
                ZendNote(
                  note!,
                  stickerSize: 96,
                  gifHeight: 180,
                  textAlign: TextAlign.center,
                  textStyle: ZendTextStyles.title.copyWith(color: fg),
                ),
                const SizedBox(height: 24),
              ],
              Text(
                sentence,
                textAlign: TextAlign.center,
                style: ZendTextStyles.title.copyWith(color: fg),
              ),
              const SizedBox(height: 6),
              Text(
                formatMoney(amount),
                style: ZendTextStyles.displayL.copyWith(color: fg),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const ZendMark(size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Zend!',
                    style: ZendTextStyles.body.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
              fontFamily: 'Geist',
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
              style: mono
                  ? ZendTextStyles.tabularNumeric.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: valueColor ?? zt.textPrimary,
                    )
                  : TextStyle(
                      fontFamily: 'Geist',
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

class _BankSendReceiptSheet extends StatefulWidget {
  const _BankSendReceiptSheet({required this.tx, required this.order});

  final ZendTransaction tx;
  final Map<String, dynamic> order;

  @override
  State<_BankSendReceiptSheet> createState() => _BankSendReceiptSheetState();
}

class _BankSendReceiptSheetState extends State<_BankSendReceiptSheet> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  ZendTransaction get tx => widget.tx;
  Map<String, dynamic> get order => widget.order;

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
        ? PhosphorIconsRegular.checkCircle
        : status == 'failed'
        ? PhosphorIconsRegular.xCircle
        : PhosphorIconsRegular.hourglass;
    final statusLabel = switch (status) {
      'completed' => 'Delivered',
      'paid' => 'Sent',
      'processing' => 'Processing',
      'failed' => 'Failed',
      'expired' => 'Expired',
      _ => 'Processing',
    };

    final amountStr = amountUsdc == amountUsdc.roundToDouble()
        ? formatUsd(amountUsdc)
        : formatUsd(amountUsdc);

    final fiatSymbol = switch (fiatCurrency) {
      'NGN' => '₦',
      'GBP' => '£',
      'EUR' => '€',
      _ => '\$',
    };

    final railLabel = _railLabel(rail, paymentRail);
    final screenHeight = MediaQuery.of(context).size.height;
    final recipient = accountName != null && accountName.isNotEmpty
        ? accountName
        : bankName.isNotEmpty
        ? bankName
        : 'a bank account';
    final fiatLine = fiatAmount != null && fiatAmount > 0
        ? '$fiatSymbol${_formatFiatValue(fiatAmount, fiatCurrency)}'
        : null;
    final cardStatus = switch (status) {
      'completed' => 'Delivered',
      'failed' => "Didn't go through",
      'expired' => 'Expired, money returned',
      _ => 'On its way',
    };
    final shareText = [
      'Sent ${fiatLine ?? amountStr} to $recipient with Zend',
      if (bankName.isNotEmpty && bankName != recipient) bankName,
    ].join(' · ');

    return Container(
      // Full screen height
      height: screenHeight,
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      child: Stack(
        children: [
          // Off-screen share card: rendered for capture, never seen here.
          Positioned(
            left: -2000,
            top: 0,
            child: RepaintBoundary(
              key: _cardKey,
              child: _BankShareCard(
                recipient: recipient,
                bankName: bankName,
                accountMasked: accountMasked,
                fiatLine: fiatLine,
                usdLine: amountStr,
                status: cardStatus,
                done: status == 'completed',
                when: formatDateTime(createdAt),
              ),
            ),
          ),
          Column(
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
                            fontFamily: 'Geist',
                            fontWeight: FontWeight.w700,
                            fontSize: 48,
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
                            style: ZendTextStyles.tabularNumeric.copyWith(
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
                            fontFamily: 'Geist',
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
                            if (accountName != null &&
                                accountName.isNotEmpty) ...[
                              _DetailRow(label: 'To', value: accountName),
                              Divider(color: zt.border, height: 1),
                            ],
                            // Bank
                            if (bankName.isNotEmpty) ...[
                              _DetailRow(label: 'Bank', value: bankName),
                              Divider(color: zt.border, height: 1),
                            ],
                            // Account number
                            if (accountMasked != null &&
                                accountMasked.isNotEmpty) ...[
                              _DetailRow(
                                label: 'Account',
                                value: accountMasked,
                                mono: true,
                              ),
                              Divider(color: zt.border, height: 1),
                            ],
                            // Rail
                            _DetailRow(label: 'Rail', value: railLabel),
                            Divider(color: zt.border, height: 1),
                            // Currency
                            if (fiatCurrency.isNotEmpty) ...[
                              _DetailRow(
                                label: 'Currency',
                                value: fiatCurrency,
                              ),
                              Divider(color: zt.border, height: 1),
                            ],
                            // Date
                            _DetailRow(
                              label: 'Date',
                              value: _formatDate(createdAt),
                            ),
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
                      Row(
                        children: [
                          Expanded(
                            child: PrimaryButton(
                              label: _sharing ? 'Sharing…' : 'Share',
                              onPressed: () async {
                                if (_sharing) return;
                                setState(() => _sharing = true);
                                await shareCaptured(_cardKey, shareText);
                                if (mounted) setState(() => _sharing = false);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlineActionButton(
                              label: 'Close',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '${months[local.month - 1]} ${local.day}, ${local.year} · $hour:$minute $period';
  }
}

/// Captures the widget under [key] as a PNG and opens the share sheet.
/// Falls back to sharing [fallbackText] when image share isn't available
/// (some browsers).
Future<void> shareCaptured(GlobalKey key, String fallbackText) async {
  try {
    // Let the card's images settle before capture.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final image = await boundary?.toImage(pixelRatio: 3);
    final data = await image?.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('capture failed');
    await Share.shareXFiles([
      XFile.fromData(
        data.buffer.asUint8List(),
        mimeType: 'image/png',
        name: 'zend-receipt.png',
      ),
    ], text: fallbackText);
  } catch (_) {
    await Share.share(fallbackText);
  }
}

/// Share card for a bank send. The local-currency amount leads (₦ for Naira
/// sends) with the dollar amount under it, then who and which bank it went
/// to and where it stands. Only the masked account tail ever appears.
class _BankShareCard extends StatelessWidget {
  const _BankShareCard({
    required this.recipient,
    required this.bankName,
    required this.accountMasked,
    required this.fiatLine,
    required this.usdLine,
    required this.status,
    required this.done,
    required this.when,
  });

  final String recipient;
  final String bankName;
  final String? accountMasked;
  final String? fiatLine;
  final String usdLine;
  final String status;
  final bool done;
  final String when;

  @override
  Widget build(BuildContext context) {
    const fg = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.72);
    final bankLine = [
      if (bankName.isNotEmpty && bankName != recipient) bankName,
      if (accountMasked != null && accountMasked!.isNotEmpty) accountMasked!,
    ].join(' · ');
    return MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF14532D), Color(0xFF0A1A0D)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  PhosphorIconsRegular.bank,
                  color: fg,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Sent to $recipient',
                textAlign: TextAlign.center,
                style: ZendTextStyles.title.copyWith(color: fg),
              ),
              const SizedBox(height: 6),
              Text(
                fiatLine ?? usdLine,
                style: ZendTextStyles.displayL.copyWith(color: fg),
              ),
              if (fiatLine != null)
                Text(
                  usdLine,
                  style: ZendTextStyles.caption.copyWith(color: dim),
                ),
              if (bankLine.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  bankLine,
                  textAlign: TextAlign.center,
                  style: ZendTextStyles.caption.copyWith(color: dim),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: done
                      ? const Color(0xFF1FD16A).withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
                child: Text(
                  status,
                  style: ZendTextStyles.micro.copyWith(color: fg),
                ),
              ),
              const SizedBox(height: 6),
              Text(when, style: ZendTextStyles.micro.copyWith(color: dim)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const ZendMark(size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Zend!',
                    style: ZendTextStyles.body.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
