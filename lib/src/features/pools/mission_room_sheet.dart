import 'package:flutter/material.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import 'mission_room.dart';
import 'pool.dart';

Future<void> showMissionRoomSheet(
  BuildContext context, {
  required Pool pool,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MissionRoomSheet(pool: pool),
  );
}

class _MissionRoomSheet extends StatelessWidget {
  const _MissionRoomSheet({required this.pool});
  final Pool pool;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      height: MediaQuery.of(context).size.height - topPadding,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              children: [
                const ZendSheetHandle(),
                const SizedBox(height: ZendSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pool.name,
                            style: const TextStyle(
                              fontFamily: 'InstrumentSerif',
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: ZendColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Mission Room',
                            style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 12,
                              color: ZendColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: ZendColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(color: ZendColors.border, height: 16),
              ],
            ),
          ),

          Expanded(
            child: MissionRoom(pool: pool),
          ),
        ],
      ),
    );
  }
}
