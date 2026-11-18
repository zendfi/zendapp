import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'zend_tokens.dart';

/// The check mark shown next to a person's name when a real, unique person controls the account.
///
/// It is drawn, not typed into a string: `handleLabel` and `personName` stay plain text so a badge
/// can never leak into share text, notifications or sentences built from names.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 15});

  final double size;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Semantics(
      label: 'Verified',
      child: Icon(PhosphorIconsFill.sealCheck, size: size, color: zt.accent),
    );
  }
}

/// Marks an automated (bot) account. A neutral robot, deliberately not the check mark, so it can
/// never be read as verification.
class AutomatedBadge extends StatelessWidget {
  const AutomatedBadge({super.key, this.size = 15});
  final double size;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Semantics(
      label: 'Automated account',
      child: Icon(PhosphorIconsRegular.robot, size: size, color: zt.textSecondary),
    );
  }
}

/// A name with the badge after it when [verified]. Single line, ellipsised, so a long name (an
/// email-style handle, say) shortens instead of pushing the badge off the row.
class PersonName extends StatelessWidget {
  const PersonName(
    this.name, {
    super.key,
    this.verified = false,
    this.automated = false,
    this.style,
    this.badgeSize,
    this.maxLines = 1,
    this.textAlign,
  });

  final String name;
  final bool verified;
  final bool automated;
  final TextStyle? style;
  final double? badgeSize;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
    if (!verified && !automated) return text;
    final fontSize = style?.fontSize ?? 14;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: text),
        const SizedBox(width: 4),
        if (automated)
          AutomatedBadge(size: badgeSize ?? (fontSize * 1.05).clamp(12.0, 22.0))
        else
          VerifiedBadge(size: badgeSize ?? (fontSize * 1.05).clamp(12.0, 22.0)),
      ],
    );
  }
}

/// The badge as an inline span, for names inside a `RichText` or `Text.rich` sentence.
InlineSpan verifiedBadgeSpan({double size = 14}) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Padding(
    padding: const EdgeInsets.only(left: 3),
    child: VerifiedBadge(size: size),
  ),
);

/// The automated-account mark as an inline span, for names inside a `RichText`.
InlineSpan automatedBadgeSpan({double size = 14}) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Padding(
    padding: const EdgeInsets.only(left: 3),
    child: AutomatedBadge(size: size),
  ),
);
