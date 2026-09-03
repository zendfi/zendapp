import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/dm_message.dart';
import '../../services/dm_service.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Shows the "Message info" sheet — mirrors WhatsApp's message-info screen:
/// the bubble itself at the top, then a Sent/Read timeline below it.
/// Only meaningful for the current user's own sent messages (received
/// messages don't have a read receipt to show from the recipient's side —
/// there's nothing to display there, so callers should only wire the
/// "Info" action for isMe messages, matching WhatsApp's own behavior).
void showDmMessageInfoSheet(
  BuildContext context, {
  required String roomId,
  required DmMessage message,
  required WidgetBuilder previewBuilder,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DmMessageInfoSheet(
      roomId: roomId,
      message: message,
      previewBuilder: previewBuilder,
    ),
  );
}

class _DmMessageInfoSheet extends StatefulWidget {
  const _DmMessageInfoSheet({
    required this.roomId,
    required this.message,
    required this.previewBuilder,
  });

  final String roomId;
  final DmMessage message;
  final WidgetBuilder previewBuilder;

  @override
  State<_DmMessageInfoSheet> createState() => _DmMessageInfoSheetState();
}

class _DmMessageInfoSheetState extends State<_DmMessageInfoSheet> {
  DmMessageInfo? _info;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final model = ZendScope.read(context);
    try {
      final info = await model.dmService.getMessageInfo(widget.roomId, widget.message.id);
      if (mounted) setState(() { _info = info; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = true; _loading = false; });
    }
  }

  String _formatFull(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final isMe = widget.message.senderUserId == ZendScope.read(context).currentUserId;

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 20),
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          const ZendSheetHandle(),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Message info',
                    style: TextStyle(fontFamily: 'Geist', fontSize: 18, fontWeight: FontWeight.w700, color: zt.textPrimary),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(PhosphorIconsRegular.xCircle, color: zt.textSecondary, size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // The bubble itself, non-interactive, on the chat canvas so it
          // renders exactly as it does in the thread.
          Container(
            width: double.infinity,
            color: zt.chatBg,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: IgnorePointer(child: widget.previewBuilder(context)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: InlineRowsSkeleton(count: 2),
                  )
                : _error
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          "Couldn't load message info",
                          style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isMe)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Read receipts are only available for messages you sent.',
                                style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textSecondary),
                              ),
                            ),
                          if (isMe && _info?.readAt != null)
                            _InfoRow(
                              icon: PhosphorIconsRegular.checks,
                              iconColor: ZendColors.accentPop,
                              label: 'Read',
                              time: _formatFull(_info!.readAt!),
                              zt: zt,
                            ),
                          if (isMe)
                            _InfoRow(
                              icon: PhosphorIconsRegular.check,
                              iconColor: zt.textSecondary,
                              label: 'Delivered',
                              time: _formatFull(_info?.sentAt ?? widget.message.createdAt),
                              zt: zt,
                            ),
                          _InfoRow(
                            icon: PhosphorIconsRegular.paperPlaneTilt,
                            iconColor: zt.textSecondary,
                            label: 'Sent',
                            time: _formatFull(_info?.sentAt ?? widget.message.createdAt),
                            zt: zt,
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.time,
    required this.zt,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String time;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textPrimary),
            ),
          ),
          Text(
            time,
            style: ZendTextStyles.tabularNumeric.copyWith(fontSize: 13, color: zt.textSecondary),
          ),
        ],
      ),
    );
  }
}
