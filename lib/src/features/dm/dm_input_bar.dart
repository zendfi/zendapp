import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/zend_tokens.dart';
import '../vibes/vibe_picker_sheet.dart';
import 'package:solar_icons/solar_icons.dart';

class DmInputBar extends StatefulWidget {
  const DmInputBar({
    super.key,
    required this.onSend,
    required this.onTyping,
    required this.roomId,
    this.onSendVibe,
  });

  final ValueChanged<String> onSend;
  final ValueChanged<bool> onTyping;
  final String roomId;
  /// Called when the user confirms a Vibe. Passes the VibeSendResult.
  final ValueChanged<VibeSendResult>? onSendVibe;

  @override
  State<DmInputBar> createState() => _DmInputBarState();
}

class _DmInputBarState extends State<DmInputBar> {
  final _ctrl = TextEditingController();
  Timer? _typingDebounce;
  bool _hasText = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _typingDebounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    // Typing indicator debounce
    widget.onTyping(true);
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      widget.onTyping(false);
    });
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    _ctrl.clear();
    setState(() => _hasText = false);
    widget.onTyping(false);
    _typingDebounce?.cancel();
    widget.onSend(text);
  }

  void _showActions() {
    final zt = ZendTheme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useRootNavigator: false,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewPadding.bottom;
        return Container(
          margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
          decoration: BoxDecoration(
            color: zt.bgSecondary,
            borderRadius: BorderRadius.circular(ZendRadii.xxl),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: zt.border,
                    borderRadius: BorderRadius.circular(ZendRadii.pill),
                  ),
                ),
              ),
              _ActionRow(
                icon: SolarIconsBold.squareArrowRightUp,
                label: 'Request payment',
                onTap: () => Navigator.pop(ctx),
              ),
              _ActionRow(
                icon: SolarIconsBold.gift,
                label: 'Send a Vibe',
                subtitle: 'Stickers with value, \$0.01–\$5',
                onTap: () async {
                  Navigator.pop(ctx);
                  if (widget.onSendVibe == null) return;
                  final result = await showVibePickerSheet(
                    context,
                    roomId: widget.roomId,
                  );
                  if (result != null && mounted) {
                    HapticFeedback.mediumImpact();
                    widget.onSendVibe!(result);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).viewPadding.bottom * 0.5),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: zt.border, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // + button
          GestureDetector(
            onTap: _showActions,
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                shape: BoxShape.circle,
              ),
              child: Icon(SolarIconsBold.addCircle,
                  size: 20, color: zt.textSecondary),
            ),
          ),
          const SizedBox(width: 8),

          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 36, maxHeight: 120),
              decoration: BoxDecoration(
                color: zt.bgSecondary,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: TextField(
                controller: _ctrl,
                onChanged: _onChanged,
                onSubmitted: (_) => _send(),
                maxLines: null,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14.5,
                  color: zt.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Message',
                  hintStyle: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14.5,
                    color: zt.textSecondary,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send button — only when text present
          AnimatedOpacity(
            opacity: _hasText ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: GestureDetector(
              onTap: _hasText ? _send : null,
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: zt.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(SolarIconsBold.plain,
                    size: 18, color: Colors.white),
              ),
            ),
          ),
          if (!_hasText) const SizedBox(width: 36),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: zt.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(ZendRadii.md),
              ),
              child: Icon(icon, size: 18, color: zt.accent),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: zt.textPrimary)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 12,
                          color: zt.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
