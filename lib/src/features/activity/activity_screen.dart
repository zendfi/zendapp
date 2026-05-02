import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

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
        // Pending transfers show "Just now" and have no sign prefix yet
        return all.where((t) => t.time == 'Just now').toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final filtered = _filtered(model.recentTransactions);

    return Scaffold(
      backgroundColor: ZendColors.bgPrimary,
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
                    child: const Text(
                      'Activity',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: ZendColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.search, color: ZendColors.textSecondary),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_none, color: ZendColors.textSecondary),
                  ),
                ],
              ),
            ),

            // ── Filter pills ──
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        color: active ? ZendColors.accent : ZendColors.bgSecondary,
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          color: active ? ZendColors.textOnDeep : ZendColors.textSecondary,
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
                child: ZendScrollPage(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (model.historyLoading && model.recentTransactions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(child: ZendLoader(size: 24)),
                          )
                        else if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: Text(
                                _activeFilter == 'All'
                                    ? 'No transactions yet'
                                    : 'No ${_activeFilter.toLowerCase()} transactions',
                                style: const TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 14,
                                  color: ZendColors.textSecondary,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: ZendColors.bgPrimary,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < filtered.length; i++) ...[
                                  _ActivityTile(
                                    avatarLabel: filtered[i].avatarLabel,
                                    name: filtered[i].name,
                                    note: filtered[i].note,
                                    amount: filtered[i].amount,
                                    time: filtered[i].time,
                                    amountColor: filtered[i].amountColor,
                                  ),
                                  if (i < filtered.length - 1)
                                    const Divider(color: ZendColors.border, height: 1),
                                ],
                              ],
                            ),
                          ),
                        if (model.lastHistoryError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Could not load latest activity',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 12,
                                color: ZendColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
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

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.avatarLabel,
    required this.name,
    required this.note,
    required this.amount,
    required this.time,
    this.amountColor = ZendColors.textPrimary,
  });

  final String avatarLabel;
  final String name;
  final String note;
  final String amount;
  final String time;
  final Color amountColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: ZendColors.bgSecondary,
            child: Text(avatarLabel,
                style: const TextStyle(color: ZendColors.textPrimary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      color: ZendColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 22,
                  fontStyle: FontStyle.italic,
                  color: amountColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: const TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 11,
                  color: ZendColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
