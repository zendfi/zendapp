import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';
import 'zapp_card.dart';

/// Cards that connected ZApps have posted to the feed (match results and so on),
/// drawn by core templates. Shown above the activity list on the Feed tab.
class ZAppFeedSection extends StatelessWidget {
  const ZAppFeedSection({super.key, required this.cards});

  final List<Map<String, dynamic>> cards;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              'From your apps',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: zt.textSecondary,
              ),
            ),
          ),
          for (final c in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ZAppCard(key: ValueKey(c['id']), card: c),
            ),
        ],
      ),
    );
  }
}
