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
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MissionRoomSheet(pool: pool),
  );
}

class _MissionRoomSheet extends StatelessWidget {
  const _MissionRoomSheet({required this.pool});
  final Pool pool;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZendRadii.xxl),
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 4, 0),
                child: Column(
                  children: [
                    const ZendSheetHandle(),
                    const SizedBox(height: ZendSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pool.name,
                            style: TextStyle(
                              fontFamily: 'InstrumentSerif',
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: ZendTheme.of(context).textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: ZendTheme.of(context).textSecondary, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    Divider(color: ZendTheme.of(context).border, height: 12),
                  ],
                ),
              ),
              Expanded(
                child: MissionRoom(pool: pool),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
