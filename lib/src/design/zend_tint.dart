import 'package:flutter/material.dart';

/// A person's or a ZApp's own colour, generated from a stable seed (user id,
/// @tag, or app id) the way Telegram colours avatars.
///
/// The app chrome stays neutral; colour on screen comes from the people and
/// activity in it. Use [ZendTint.of] for the colour, then:
/// - [solid] and [gradient] for an avatar disc,
/// - [wash] and [edge] for a card that belongs to that person (a Link card),
/// - [ink] for text or icons sitting on [wash].
@immutable
class ZendTint {
  const ZendTint._(this.solid, this.isDark);

  /// The tint at full strength.
  final Color solid;
  final bool isDark;

  /// Saturated hues spaced far apart so neighbours in a list never look
  /// alike. They're the only strong colour in the app, so they stay vivid.
  /// White initials clear 3:1 (large text) on all but amber, which gets dark
  /// initials (see [onSolid]).
  static const palette = <Color>[
    Color(0xFFEF3B36), // red
    Color(0xFFF25C05), // orange
    Color(0xFFF5A300), // amber
    Color(0xFF0FA958), // green
    Color(0xFF0A9E9A), // teal
    Color(0xFF0A8FE8), // sky
    Color(0xFF4757FF), // blue
    Color(0xFF8650F5), // violet
    Color(0xFFC93AE0), // orchid
    Color(0xFFF0306F), // pink
  ];

  /// Stable tint for [seed] (FNV-1a hash, case-insensitive).
  static ZendTint of(String seed, {bool isDark = false}) =>
      ZendTint._(palette[_hash(seed) % palette.length], isDark);

  /// Same as [of], reading the mode from the current theme.
  static ZendTint ofContext(BuildContext context, String seed) =>
      of(seed, isDark: Theme.of(context).brightness == Brightness.dark);

  static int _hash(String seed) {
    var h = 0x811c9dc5;
    for (final c in seed.trim().toLowerCase().codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// Two-stop avatar gradient: lighter at the top left.
  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.lerp(solid, Colors.white, 0.10)!,
      Color.lerp(solid, Colors.black, 0.10)!,
    ],
  );

  /// Initials or icons on [solid].
  Color get onSolid => solid.computeLuminance() > 0.4
      ? const Color(0xFF0F0F0E)
      : Colors.white;

  /// Quiet card fill in the person's colour, on the off-white page or true
  /// black.
  Color get wash => isDark
      ? Color.lerp(solid, Colors.black, 0.70)!
      : Color.lerp(solid, Colors.white, 0.76)!;

  /// Hairline outline for a [wash] card.
  Color get edge => solid.withValues(alpha: isDark ? 0.55 : 0.45);

  /// Text and icons on [wash] (passes 4.5:1).
  Color get ink => isDark
      ? Color.lerp(solid, Colors.white, 0.45)!
      : Color.lerp(solid, Colors.black, 0.50)!;
}
