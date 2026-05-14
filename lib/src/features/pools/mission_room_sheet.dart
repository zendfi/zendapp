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
    // Let the sheet resize when the keyboard appears
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
      // Full-screen minus status bar
      height: MediaQuery.of(context).size.height - topPadding,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      // Scaffold inside the sheet handles keyboard insets correctly —
      // resizeToAvoidBottomInset pushes content up when keyboard opens,
      // exactly like WhatsApp/Telegram.
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
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
                          style: const TextStyle(
                            fontFamily: 'InstrumentSerif',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: ZendColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  const Divider(color: ZendColors.border, height: 12),
                ],
              ),
            ),

            // ── Mission Room fills the rest ──────────────────────────────
            Expanded(
              child: MissionRoom(pool: pool),
            ),
          ],
        ),
      ),
    );
  }
}
