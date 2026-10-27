import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_tokens.dart';

/// Block or report someone (design revamp: trust and safety). Opened from a
/// person's page and the DM overflow menu. Returns true if they were blocked.
Future<bool> showBlockReportSheet(
  BuildContext context, {
  required String userId,
  required String name,
}) async {
  final api = ZendScope.read(context).walletService.apiClient;
  final messenger = ScaffoldMessenger.of(context);
  final action = await showZendModalSheet<String>(
    context: context,
    builder: (ctx) {
      final zt = ZendTheme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name,
                style: ZendTextStyles.title.copyWith(color: zt.textPrimary),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.block, color: zt.destructive),
                title: Text('Block', style: TextStyle(color: zt.destructive)),
                subtitle: const Text(
                  "They won't be able to message you or send you money.",
                ),
                onTap: () => Navigator.of(ctx).pop('block'),
              ),
              for (final r in const [
                ('spam', 'Report spam'),
                ('scam', 'Report a scam'),
                ('harassment', 'Report harassment'),
                ('impersonation', 'Report impersonation'),
              ])
                ListTile(
                  leading: Icon(Icons.flag_outlined, color: zt.textSecondary),
                  title: Text(r.$2),
                  onTap: () => Navigator.of(ctx).pop('report:${r.$1}'),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (action == null) return false;
  try {
    if (action == 'block') {
      await api.blockUser(userId);
      messenger.showSnackBar(SnackBar(content: Text('$name is blocked')));
      return true;
    }
    await api.reportUser(userId, reason: action.substring('report:'.length));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Thanks. Our team will review this report.'),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't complete that. Try again.")),
    );
  }
  return false;
}
