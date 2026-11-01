import 'package:flutter/material.dart';

import 'zend_gif.dart';
import 'zend_money.dart';
import 'zend_tokens.dart';

/// Text for a payment note wherever only text fits (list rows, previews,
/// share text). A GIF note becomes "🖼️ GIF" so the raw `gif:<id>` never
/// shows; emoji and text notes pass through unchanged.
String noteText(String? note) {
  final n = note?.trim() ?? '';
  if (gifIdFromNote(n) != null) return '🖼️ GIF';
  return n;
}

/// A payment note at full size: animated stickers for emoji, the GIF for a
/// GIF note, quoted text otherwise. Every detail surface should use this
/// rather than printing the note itself.
class ZendNote extends StatelessWidget {
  const ZendNote(
    this.note, {
    super.key,
    this.stickerSize = 56,
    this.gifHeight = 140,
    this.burst = false,
    this.textStyle,
    this.textAlign = TextAlign.start,
  });

  final String note;
  final double stickerSize;
  final double gifHeight;
  final bool burst;
  final TextStyle? textStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final n = note.trim();
    final gif = gifIdFromNote(n);
    if (gif != null) return ZendGifTile(gif, height: gifHeight);
    if (isEmojiNote(n)) {
      return ZendEmojiTile(n, size: stickerSize, burst: burst);
    }
    final zt = ZendTheme.of(context);
    return Text(
      '“$n”',
      textAlign: textAlign,
      style: textStyle ?? ZendTextStyles.body.copyWith(color: zt.textPrimary),
    );
  }
}
