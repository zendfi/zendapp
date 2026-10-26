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
  if (n.isEmpty || n.runes.length > 8) return false;
  return !RegExp(r'[A-Za-z0-9]').hasMatch(n);
}

/// A payment's emoji note, shown large (about 48px) on a tinted tile.
/// [burst] plays a one-off pop when the tile first appears (received notes).
class ZendEmojiTile extends StatelessWidget {
  const ZendEmojiTile(
    this.emoji, {
    super.key,
    this.size = 56,
    this.burst = false,
  });

  final String emoji;
  final double size;
  final bool burst;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: zt.bgElevated,
        borderRadius: BorderRadius.circular(ZendRadii.card),
      ),
      child: Text(
        emoji,
        style: TextStyle(fontSize: size * 0.6, height: 1),
        semanticsLabel: 'Note: $emoji',
      ),
    );
    if (!burst || ZendMotion.reduced(context)) return tile;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: ZendMotion.celebrate,
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: tile,
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
          radius: 0.9,
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
