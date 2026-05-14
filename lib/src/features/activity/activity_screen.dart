import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'transaction_receipt_sheet.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _activeFilter = 'All';

  static const _filters = ['All', 'Received', 'Sent', 'Pending'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZendScope.of(context).fetchHistory();
    });
  }

  List<ZendTransaction> _filtered(List<ZendTransaction> all) {
    switch (_activeFilter) {
      case 'Received':
        return all.where((t) => t.amount.startsWith('+')).toList();
      case 'Sent':
        return all.where((t) => t.amount.startsWith('-')).toList();
      case 'Pending':
        return all.where((t) => t.time == 'Just now').toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final filtered = _filtered(model.recentTransactions);

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
                    onPressed: () {},
                    icon: Icon(Icons.search, color: zt.textSecondary),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: Icon(Icons.notifications_none,
                        color: zt.textSecondary),
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
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final label = _filters[i];
                  final active = _activeFilter == label;
                  return GestureDetector(
                    onTap: () => setState(() => _activeFilter = label),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: active
                            ? zt.accent
                            : zt.bgSecondary,
                        borderRadius:
                            BorderRadius.circular(ZendRadii.pill),
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
                    : filtered.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 200,
                                child: Center(
                                  child: Text(
                                    _activeFilter == 'All'
                                        ? 'No transactions yet'
                                        : 'No ${_activeFilter.toLowerCase()} transactions',
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
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) =>
                                Divider(color: zt.border, height: 1),
                            itemBuilder: (context, i) {
                              final tx = filtered[i];
                              return _ActivityTile(
                                avatarLabel: tx.avatarLabel,
                                name: tx.name,
                                note: tx.note,
                                amount: tx.amount,
                                time: tx.time,
                                amountColor: tx.amountColor,
                                isFirst: i == 0,
                                isLast: i == filtered.length - 1,
                                onTap: tx.entry != null || tx.bankOrder != null
                                    ? () => showTransactionReceipt(
                                          context,
                                          tx: tx,
                                        )
                                    : null,
                              );
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
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.avatarLabel,
    required this.name,
    required this.note,
    required this.amount,
    required this.time,
    this.amountColor,
    this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  final String avatarLabel;
  final String name;
  final String note;
  final String amount;
  final String time;
  final Color? amountColor;
  final VoidCallback? onTap;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(24) : Radius.zero,
      bottom: isLast ? const Radius.circular(24) : Radius.zero,
    );
    return Material(
      color: zt.bgSecondary,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: zt.bgPrimary,
                child: Text(avatarLabel, style: TextStyle(color: zt.textPrimary)),
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
        ),
      ),
    );
  }
}
