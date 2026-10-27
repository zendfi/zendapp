import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/zend_format.dart';
import 'zend_tokens.dart';

/// Direction of a money movement, for colour and sign.
enum MoneyDirection { incoming, outgoing, neutral }

/// The one way an amount is drawn: display face, tabular figures, and a
/// direction colour plus a `+`/`−` sign (never colour alone).
class ZendAmount extends StatelessWidget {
  const ZendAmount(
    this.amount, {
    super.key,
    this.direction = MoneyDirection.neutral,
    this.style = ZendTextStyles.amountM,
    this.hidden = false,
  });

  final double amount;
  final MoneyDirection direction;
  final TextStyle style;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final color = switch (direction) {
      MoneyDirection.incoming => zt.moneyIn,
      MoneyDirection.outgoing => zt.moneyOut,
      MoneyDirection.neutral => zt.textPrimary,
    };
    final text = hidden
        ? '•••'
        : direction == MoneyDirection.neutral
        ? formatUsd(amount)
        : formatUsd(
            direction == MoneyDirection.incoming ? amount.abs() : -amount.abs(),
            signed: true,
          );
    return Text(
      text,
      maxLines: 1,
      semanticsLabel: hidden
          ? 'Amount hidden'
          : '${direction == MoneyDirection.incoming
                ? 'Received '
                : direction == MoneyDirection.outgoing
                ? 'Sent '
                : ''}${formatUsd(amount.abs())}',
      style: style.copyWith(color: color),
    );
  }
}

/// Balance that rolls to its new value instead of jumping (doc: "Balance
/// changes — digits roll"). Respects Reduce Motion.
class ZendRollingAmount extends StatelessWidget {
  const ZendRollingAmount(
    this.amount, {
    super.key,
    this.style = ZendTextStyles.displayXl,
    this.hidden = false,
  });

  final double amount;
  final TextStyle style;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final s = style.copyWith(color: zt.textPrimary);
    if (hidden) return Text('•••', style: s, semanticsLabel: 'Balance hidden');
    if (ZendMotion.reduced(context)) {
      return Text(formatUsd(amount), style: s);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: amount),
      duration: ZendMotion.celebrate,
      curve: ZendMotion.springSnappy,
      builder: (context, v, _) =>
          Text(formatUsd(v), style: s, semanticsLabel: formatUsd(amount)),
    );
  }
}

/// True when a note is (only) emoji — those get the big tile.
bool isEmojiNote(String? note) {
  final n = note?.trim() ?? '';
  if (n.startsWith('gif:')) return false;
  if (n.isEmpty || n.runes.length > 8) return false;
  return !RegExp(r'[A-Za-z0-9]').hasMatch(n);
}

/// A payment's emoji note, shown as animated stickers.
///
/// Each emoji maps to its Noto Animated Emoji sticker (Google, free under
/// CC BY 4.0), loaded from Google's CDN. Combinations render as a tight row
/// of stickers that pop in one after another (the "sticker action"). If a
/// sticker doesn't exist or can't load, the static emoji glyph shows instead.
/// No container: stickers sit directly on the card, sized to content.
class ZendEmojiTile extends StatelessWidget {
  const ZendEmojiTile(
    this.emoji, {
    super.key,
    this.size = 48,
    this.burst = false,
  });

  final String emoji;
  final double size;
  final bool burst;

  @override
  Widget build(BuildContext context) {
    final parts = splitEmoji(emoji).take(5).toList();
    // Shrink stickers as the combination grows so a row never sprawls.
    final each = parts.length <= 1
        ? size
        : size * (parts.length <= 3 ? 0.8 : 0.65);
    final reduced = ZendMotion.reduced(context);
    return Semantics(
      label: 'Note: $emoji',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < parts.length; i++)
            _Popped(
              enabled: burst && !reduced,
              delay: Duration(milliseconds: 90 * i),
              child: ZendSticker(parts[i], size: each),
            ),
        ],
      ),
    );
  }
}

/// Splits a note into emoji clusters, keeping ZWJ sequences and
/// variation selectors attached (👨‍👩‍👧, ❤️).
List<String> splitEmoji(String s) {
  final out = <String>[];
  final runes = s.trim().runes.toList();
  var cur = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    if (r == 0x20) continue;
    final joins = r == 0x200D || r == 0xFE0F || (r >= 0x1F3FB && r <= 0x1F3FF);
    final prevZwj = cur.isNotEmpty && cur.toString().runes.last == 0x200D;
    if (cur.isNotEmpty && !joins && !prevZwj) {
      out.add(cur.toString());
      cur = StringBuffer();
    }
    cur.writeCharCode(r);
  }
  if (cur.isNotEmpty) out.add(cur.toString());
  return out;
}

/// One animated sticker for one emoji.
class ZendSticker extends StatelessWidget {
  const ZendSticker(this.emoji, {super.key, this.size = 48});

  final String emoji;
  final double size;

  static String urlFor(String emoji) {
    final code = emoji.runes
        .where((r) => r != 0xFE0F)
        .map((r) => r.toRadixString(16))
        .join('_');
    return 'https://fonts.gstatic.com/s/e/notoemoji/latest/$code/512.webp';
  }

  @override
  Widget build(BuildContext context) {
    final glyph = Center(
      child: Text(
        emoji,
        style: ZendTextStyles.emoji.copyWith(fontSize: size * 0.8),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: Image.network(
        urlFor(emoji),
        width: size,
        height: size,
        gaplessPlayback: true,
        // Static glyph while loading and on any failure.
        frameBuilder: (_, child, frame, _) => frame == null ? glyph : child,
        errorBuilder: (_, _, _) => glyph,
      ),
    );
  }
}

class _Popped extends StatelessWidget {
  const _Popped({
    required this.enabled,
    required this.delay,
    required this.child,
  });

  final bool enabled;
  final Duration delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final total = ZendMotion.celebrate + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      builder: (context, t, child) {
        final local = ((t - start) / (1 - start)).clamp(0.0, 1.0);
        return Transform.scale(
          scale: 0.4 + 0.6 * Curves.elasticOut.transform(local),
          child: child,
        );
      },
      child: child,
    );
  }
}

/// Haptics for the doc's motion table, named by moment so screens don't pick
/// impact strengths ad hoc.
abstract final class ZendFeel {
  static void keypadTap() => HapticFeedback.selectionClick();
  static void reaction() => HapticFeedback.lightImpact();
  static void received() => HapticFeedback.mediumImpact();
  static Future<void> sendConfirmed() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.lightImpact();
  }

  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await HapticFeedback.heavyImpact();
  }
}

/// Soft green glow behind a key moment (balance, received payment, status
/// check) — used instead of gradients everywhere.
class ZendGlow extends StatelessWidget {
  const ZendGlow({super.key, required this.child, this.radius = 120});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 0.5,
          colors: [
            zt.moneyIn.withValues(alpha: zt.isDark ? 0.16 : 0.10),
            zt.moneyIn.withValues(alpha: 0),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// True for notes shown as a tile (emoji or GIF), never as plain text.
bool isMediaNote(String? note) =>
    isEmojiNote(note) || (note?.trim().startsWith('gif:') ?? false);
