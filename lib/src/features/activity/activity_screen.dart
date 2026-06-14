import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_country_flag.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/email_intent.dart';
import '../../models/payment_request_item.dart';
import '../../models/qr_payment_intent.dart';
import '../send/qr_payment_sheet.dart';
import 'transaction_receipt_sheet.dart';

// ── Unified activity item ─────────────────────────────────────────────────────

sealed class _ActivityItem {
  DateTime get createdAt;
}

class _TxItem extends _ActivityItem {
  final ZendTransaction tx;
  _TxItem(this.tx);
  @override
  DateTime get createdAt => tx.createdAt;
}

class _IntentItem extends _ActivityItem {
  final EmailIntent intent;
  _IntentItem(this.intent);
  @override
  DateTime get createdAt => intent.createdAt;
}

class _RequestItem extends _ActivityItem {
  final PaymentRequestItem request;
  _RequestItem(this.request);
  @override
  DateTime get createdAt => request.createdAt;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _activeFilter = 'All';

  static const _filters = ['All', 'Received', 'Sent', 'Pending', 'Requests'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZendScope.of(context).fetchHistory();
    });
  }

  bool _intentIsRenderable(EmailIntent intent) {
    return intent.recipientHint.isNotEmpty &&
        intent.amountUsdc > 0 &&
        intent.expiry.isAfter(DateTime.fromMillisecondsSinceEpoch(0));
  }

  List<_ActivityItem> _buildItems(
    List<ZendTransaction> txs,
    List<EmailIntent> intents,
    List<PaymentRequestItem> outbound,
    List<PaymentRequestItem> inbound,
  ) {
    final renderableIntents =
        intents.where((i) => i.isPending && _intentIsRenderable(i)).toList();

    final List<_ActivityItem> items;

    switch (_activeFilter) {
      case 'Received':
        items = txs
            .where((t) => t.amount.startsWith('+'))
            .map<_ActivityItem>((t) => _TxItem(t))
            .toList();
      case 'Sent':
        items = txs
            .where((t) => t.amount.startsWith('-'))
            .map<_ActivityItem>((t) => _TxItem(t))
            .toList();
      case 'Pending':
        final pendingTxs = txs
            .where((t) => t.isPending)
            .map<_ActivityItem>((t) => _TxItem(t));
        items = [
          ...pendingTxs,
          ...renderableIntents.map<_ActivityItem>((i) => _IntentItem(i)),
        ];
      case 'Requests':
        // Show all inbound (pending only) + all outbound requests
        items = [
          ...inbound
              .where((r) => r.isPending)
              .map<_ActivityItem>((r) => _RequestItem(r)),
          ...outbound
              .where((r) => r.amountUsdc > 0)
              .map<_ActivityItem>((r) => _RequestItem(r)),
        ];
      default: // 'All'
        items = [
          ...txs.map<_ActivityItem>((t) => _TxItem(t)),
          ...renderableIntents.map<_ActivityItem>((i) => _IntentItem(i)),
          // In "All": inbound pending requests + all outbound requests
          ...inbound
              .where((r) => r.isPending)
              .map<_ActivityItem>((r) => _RequestItem(r)),
          ...outbound
              .where((r) => r.amountUsdc > 0)
              .map<_ActivityItem>((r) => _RequestItem(r)),
        ];
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final items = _buildItems(
      model.recentTransactions,
      model.pendingEmailIntents,
      model.outboundPaymentRequests,
      model.inboundPaymentRequests,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Activity',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: null,
                    icon: Icon(Icons.search,
                        color: zt.textSecondary.withValues(alpha: 0.4)),
                  ),
                  IconButton(
                    onPressed: null,
                    icon: Icon(Icons.notifications_none,
                        color: zt.textSecondary.withValues(alpha: 0.4)),
                  ),
                ],
              ),
            ),

            // ── Filter pills ──
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final label = _filters[i];
                  final active = _activeFilter == label;
                  return GestureDetector(
                    onTap: () => setState(() => _activeFilter = label),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: active ? zt.accent : zt.bgSecondary,
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          color: active
                              ? ZendColors.textOnDeep
                              : zt.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Content ──
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => model.fetchHistory(),
                child: model.historyLoading && model.recentTransactions.isEmpty
                    ? const Center(child: ZendLoader(size: 24))
                    : items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 200,
                                child: Center(
                                  child: Text(
                                    _emptyLabel,
                                    style: TextStyle(
                                      fontFamily: 'DMSans',
                                      fontSize: 14,
                                      color: zt.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                Divider(color: zt.border, height: 1),
                            itemBuilder: (context, i) {
                              final item = items[i];
                              final isFirst = i == 0;
                              final isLast = i == items.length - 1;

                              return switch (item) {
                                _TxItem(:final tx) => _ActivityTile(
                                    avatarLabel: tx.avatarLabel,
                                    avatarUrl: tx.avatarUrl,
                                    countryCode: tx.countryCode,
                                    name: tx.name,
                                    note: tx.note,
                                    amount: tx.amount,
                                    time: tx.time,
                                    amountColor: tx.amountColor,
                                    isFirst: isFirst,
                                    isLast: isLast,
                                    onTap: tx.entry != null ||
                                            tx.bankOrder != null
                                        ? () => showTransactionReceipt(
                                              context,
                                              tx: tx,
                                            )
                                        : null,
                                  ),
                                _IntentItem(:final intent) => _ActivityTile(
                                    avatarLabel: intent.recipientHint.isNotEmpty
                                        ? intent.recipientHint[0].toUpperCase()
                                        : '?',
                                    name: intent.recipientHint,
                                    note: _expiryLabel(intent),
                                    amount: '-${intent.amountFormatted}',
                                    time: 'pending claim',
                                    isFirst: isFirst,
                                    isLast: isLast,
                                    onTap: () => _showIntentDetail(
                                        context, intent, model),
                                  ),
                                _RequestItem(:final request) =>
                                  _buildRequestTile(
                                      context, request, isFirst, isLast),
                              };
                            },
                          ),
              ),
            ),
            if (model.lastHistoryError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Could not load latest activity',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: zt.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String get _emptyLabel {
    switch (_activeFilter) {
      case 'Requests':
        return 'No payment requests';
      case 'All':
        return 'No transactions yet';
      default:
        return 'No ${_activeFilter.toLowerCase()} transactions';
    }
  }

  Widget _buildRequestTile(
    BuildContext context,
    PaymentRequestItem request,
    bool isFirst,
    bool isLast,
  ) {
    final statusColor = switch (request.status) {
      'paid' => ZendColors.positive,
      'expired' || 'cancelled' => ZendTheme.of(context).textSecondary,
      _ => request.isInbound
          ? ZendColors.destructive // inbound pending = you owe
          : ZendTheme.of(context).accent, // outbound pending = they owe you
    };

    final statusLabel = switch (request.status) {
      'paid' => 'Paid',
      'expired' => 'Expired',
      'cancelled' => 'Cancelled',
      _ => request.isInbound ? 'Pay now' : 'Pending',
    };

    final note = request.description?.isNotEmpty == true
        ? request.description!
        : request.isInbound
            ? 'Payment request'
            : 'Sent request';

    return _ActivityTile(
      avatarLabel: request.avatarInitial,
      name: request.counterpartyLabel,
      note: note,
      amount: request.isInbound
          ? '-${request.formattedAmount}'
          : '+${request.formattedAmount}',
      time: statusLabel,
      amountColor: statusColor,
      isFirst: isFirst,
      isLast: isLast,
      statusDot: request.isPending
          ? _StatusDot(color: statusColor)
          : null,
      onTap: () {
        if (request.isInbound && request.isPending) {
          // Open QR pay sheet so the user can pay immediately
          final intent = QrPaymentIntent(
            zendtag: request.requesterZendtag ?? '',
            amountUsdc: request.amountUsdc,
            note: request.description,
            requestLinkId: request.requestLinkId,
          );
          showQrPaymentSheet(context, intent: intent);
        } else {
          // Show outbound request detail (share/copy/status)
          _showOutboundRequestDetail(context, request);
        }
      },
    );
  }

  static String _expiryLabel(EmailIntent intent) {
    final days = intent.daysRemaining;
    if (days == 0) return 'Expires today';
    if (days == 1) return 'Expires in 1 day';
    return 'Expires in $days days';
  }

  void _showIntentDetail(
    BuildContext context,
    EmailIntent intent,
    ZendAppModel model,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PendingIntentSheet(
        intent: intent,
        onCancel: () async {
          try {
            await model.cancelEmailIntent(intent.id);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Could not cancel — please try again',
                    style: TextStyle(fontFamily: 'DMSans'),
                  ),
                  backgroundColor: ZendColors.destructive,
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _showOutboundRequestDetail(
      BuildContext context, PaymentRequestItem request) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OutboundRequestSheet(request: request),
    );
  }
}

// ── Outbound request detail sheet ─────────────────────────────────────────────

class _OutboundRequestSheet extends StatelessWidget {
  const _OutboundRequestSheet({required this.request});

  final PaymentRequestItem request;

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: request.linkUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied!',
            style: TextStyle(fontFamily: 'DMSans')),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    // Respect the system bottom inset so the sheet never hides behind
    // the gesture bar or system navigation bar.
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    final statusColor = switch (request.status) {
      'paid' => ZendColors.positive,
      'expired' || 'cancelled' => zt.textSecondary,
      _ => zt.accent,
    };
    final statusLabel = switch (request.status) {
      'paid' => 'Paid',
      'expired' => 'Expired',
      'cancelled' => 'Cancelled',
      _ => 'Pending',
    };

    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xxl),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: zt.border,
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
              ),
            ),

            // Status badge
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Amount
            Center(
              child: Text(
                '+${request.formattedAmount}',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 42,
                  fontStyle: FontStyle.italic,
                  color: zt.textPrimary,
                ),
              ),
            ),

            const SizedBox(height: 4),

            if (request.description?.isNotEmpty == true) ...[
              Center(
                child: Text(
                  request.description!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    color: zt.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 8),

            // Recipient row
            _DetailRow(label: 'To', value: request.counterpartyLabel, zt: zt),
            const SizedBox(height: 12),
            _DetailRow(
              label: 'Created',
              value: _formatDate(request.createdAt),
              zt: zt,
            ),

            const SizedBox(height: 20),

            // Link row
            GestureDetector(
              onTap: () => _copyLink(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: zt.bgPrimary,
                  borderRadius: BorderRadius.circular(ZendRadii.lg),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        request.linkUrl,
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 11,
                          color: zt.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.copy_outlined, size: 14, color: zt.accent),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Share button
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => Share.share(request.linkUrl),
                style: OutlinedButton.styleFrom(
                  foregroundColor: zt.textPrimary,
                  side: BorderSide(color: zt.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                  ),
                ),
                child: const Text(
                  'Share link',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Done',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: zt.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ── Pending intent detail sheet ───────────────────────────────────────────────

class _PendingIntentSheet extends StatefulWidget {
  const _PendingIntentSheet({
    required this.intent,
    required this.onCancel,
  });

  final EmailIntent intent;
  final Future<void> Function() onCancel;

  @override
  State<_PendingIntentSheet> createState() => _PendingIntentSheetState();
}

class _PendingIntentSheetState extends State<_PendingIntentSheet> {
  bool _cancelling = false;

  String _formatExpiry(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final zt = ZendTheme.of(ctx);
        return AlertDialog(
          backgroundColor: zt.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZendRadii.xl),
          ),
          title: Text(
            'Cancel this send?',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: zt.textPrimary,
            ),
          ),
          content: Text(
            'The reserved funds will be returned to your spendable balance.',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              color: zt.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Keep',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontWeight: FontWeight.w600,
                  color: zt.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Cancel send',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontWeight: FontWeight.w600,
                  color: ZendColors.destructive,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await widget.onCancel();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final intent = widget.intent;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xxl),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: zt.border,
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
              ),
            ),

            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: zt.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
                child: Text(
                  'pending claim',
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: zt.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            Center(
              child: Text(
                '-${intent.amountFormatted}',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 42,
                  fontStyle: FontStyle.italic,
                  color: zt.textPrimary,
                ),
              ),
            ),

            const SizedBox(height: 24),

            _DetailRow(label: 'To', value: intent.recipientHint, zt: zt),
            const SizedBox(height: 12),
            _DetailRow(
              label: 'Expires',
              value: _formatExpiry(intent.expiry),
              zt: zt,
            ),

            const SizedBox(height: 28),

            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _cancelling ? null : _confirmCancel,
                style: FilledButton.styleFrom(
                  backgroundColor: ZendColors.destructive,
                  foregroundColor: ZendColors.textOnDeep,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                  ),
                ),
                child: _cancelling
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ZendColors.textOnDeep,
                        ),
                      )
                    : const Text(
                        'Cancel send',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.zt,
  });

  final String label;
  final String value;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                color: zt.textSecondary)),
        Text(value,
            style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 13,
                color: zt.textPrimary)),
      ],
    );
  }
}

// ── Status dot badge ──────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ── Activity tile ─────────────────────────────────────────────────────────────

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.avatarLabel,
    required this.name,
    required this.note,
    required this.amount,
    required this.time,
    this.avatarUrl,
    this.countryCode,
    this.amountColor,
    this.statusDot,
    this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  final String avatarLabel;
  final String? avatarUrl;
  final String? countryCode;
  final String name;
  final String note;
  final String amount;
  final String time;
  final Color? amountColor;
  final Widget? statusDot;
  final VoidCallback? onTap;
  final bool isFirst;
  final bool isLast;

  ZendCountry? get _country {
    return switch (countryCode) {
      'ng' => ZendCountry.ng,
      'us' => ZendCountry.us,
      'gb' => ZendCountry.gb,
      'eu' => ZendCountry.eu,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(24) : Radius.zero,
      bottom: isLast ? const Radius.circular(24) : Radius.zero,
    );
    final country = _country;

    return Material(
      color: zt.bgSecondary,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              country != null
                  ? ZendCountryFlag(country: country, size: 48)
                  : ZendAvatar(
                      radius: 26,
                      photoUrl: avatarUrl,
                      initials: avatarLabel,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: zt.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: zt.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    amount,
                    style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 22,
                      fontStyle: FontStyle.italic,
                      color: amountColor ?? zt.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (statusDot != null) ...[
                        statusDot!,
                        const SizedBox(width: 4),
                      ],
                      Text(
                        time,
                        style: TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 11,
                          color: zt.textSecondary,
                        ),
                      ),
                    ],
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
