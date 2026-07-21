import 'package:flutter/material.dart';

import '../../design/zend_tokens.dart';

/// A Vibe message bubble rendered inside [DmThreadScreen].
/// Shows sticker emoji large + amount in a pill below.
class VibeMessageBubble extends StatelessWidget {
  const VibeMessageBubble({
    super.key,
    required this.emoji,
    required this.amountUsdc,
    required this.senderLabel,
    required this.isMine,
    this.createdAt,
  });

  final String emoji;
  final double amountUsdc;
  final String senderLabel;
  final bool isMine;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    final bubble = Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sticker emoji
        Text(emoji, style: const TextStyle(fontSize: 48)),
        const SizedBox(height: 4),
        // Amount pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isMine
                ? zt.accent.withValues(alpha: 0.18)
                : zt.bgSecondary,
            borderRadius: BorderRadius.circular(ZendRadii.pill),
            border: Border.all(
              color: isMine
                  ? zt.accent.withValues(alpha: 0.5)
                  : zt.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '✨',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 4),
              Text(
                '\$${amountUsdc.toStringAsFixed(2)}',
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isMine ? zt.accent : zt.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (createdAt != null) ...[
          const SizedBox(height: 2),
          Text(
            _timeLabel(createdAt!),
            style: TextStyle(
              fontFamily: 'DMMono',
              fontSize: 10,
              color: zt.textSecondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMine ? 60 : 12,
          right: isMine ? 12 : 60,
          top: 4,
          bottom: 4,
        ),
        child: bubble,
      ),
    );
  }

  String _timeLabel(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
