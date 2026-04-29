import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                      Container(
                        decoration: BoxDecoration(
                          color: ZendColors.bgPrimary,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Column(
                          children: [
                            _DateMarker(label: 'TUE'),
                            _ActivityTile(
                              avatarLabel: 'C',
                              name: 'Carissa Thompson',
                              note: 'Concert',
                              amount: '+\$65.00',
                              amountColor: ZendColors.positive,
                            ),
                            Divider(color: ZendColors.border, height: 1),
                            _ActivityTile(
                              avatarLabel: 'B',
                              name: 'GTBank ••• 4465',
                              note: 'External send',
                              amount: '-\$42.00',
                            ),
                            Divider(color: ZendColors.border, height: 1),
                            _ActivityTile(
                              avatarLabel: 'J',
                              name: 'Josh Hues',
                              note: 'Lunch',
                              amount: '-\$12.00',
                            ),
                            _DateMarker(label: 'MON'),
                            _ActivityTile(
                              avatarLabel: 'W',
                              name: 'Whole Foods',
                              note: 'Groceries',
                              amount: '-\$145.20',
                            ),
                          ],
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

class _DateMarker extends StatelessWidget {
  const _DateMarker({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'DMSans',
          color: ZendColors.textSecondary,
          fontSize: 12,
          letterSpacing: 1.2,
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
