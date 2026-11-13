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

  /// Hues spaced far apart so neighbours in a list never look alike. White
  /// initials clear 3.5:1 on every hue except amber, which gets dark
  /// initials instead (see [onSolid]).
  static const palette = <Color>[
    Color(0xFFE04E45), // red
    Color(0xFFD9652A), // orange
    Color(0xFFD9A421), // amber
    Color(0xFF2E9A5E), // green
    Color(0xFF15928F), // teal
    Color(0xFF2F8FCF), // sky
    Color(0xFF4F74E3), // blue
    Color(0xFF8662E8), // violet
    Color(0xFFC95BD6), // orchid
    Color(0xFFE2558E), // pink
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
    colors: [Color.lerp(solid, Colors.white, 0.22)!, solid],
  );

  /// Initials or icons on [solid].
  Color get onSolid => solid.computeLuminance() > 0.4
      ? const Color(0xFF1C1A17)
      : Colors.white;

  /// Quiet card fill in the person's colour, on the off-white page or true
  /// black.
  Color get wash => isDark
      ? Color.lerp(solid, Colors.black, 0.80)!
      : Color.lerp(solid, const Color(0xFFFDFBF7), 0.86)!;

  /// Hairline outline for a [wash] card.
  Color get edge => solid.withValues(alpha: isDark ? 0.40 : 0.30);

  /// Text and icons on [wash] (passes 4.5:1).
  Color get ink => isDark
      ? Color.lerp(solid, Colors.white, 0.45)!
      : Color.lerp(solid, Colors.black, 0.50)!;
}
