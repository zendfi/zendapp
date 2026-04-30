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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZendScope.of(context).fetchHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);

    return Scaffold(
      backgroundColor: ZendColors.bgPrimary,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Activity',
                      style: const TextStyle(
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
            Expanded(
              child: ZendScrollPage(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: const [
                            _FilterPill(label: 'All', active: true),
                            SizedBox(width: 12),
                            _FilterPill(label: 'Received'),
                            SizedBox(width: 12),
                            _FilterPill(label: 'Sent'),
                            SizedBox(width: 12),
                            _FilterPill(label: 'Pending'),
                            SizedBox(width: 12),
                            _FilterPill(label: 'External'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (model.historyLoading && model.recentTransactions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: ZendLoader(size: 24)),
                        )
                      else if (model.recentTransactions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              'No transactions yet',
                              style: TextStyle(
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
                              for (var i = 0; i < model.recentTransactions.length; i++) ...[
                                _ActivityTile(
                                  avatarLabel: model.recentTransactions[i].avatarLabel,
                                  name: model.recentTransactions[i].name,
                                  note: model.recentTransactions[i].note,
                                  amount: model.recentTransactions[i].amount,
                                  amountColor: model.recentTransactions[i].amountColor,
                                ),
                                if (i < model.recentTransactions.length - 1)
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
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
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
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.avatarLabel, required this.name, required this.note, required this.amount, this.amountColor = ZendColors.textPrimary});

  final String avatarLabel;
  final String name;
  final String note;
  final String amount;
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
            child: Text(avatarLabel, style: const TextStyle(color: ZendColors.textPrimary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, color: ZendColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 24,
              fontStyle: FontStyle.italic,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}
