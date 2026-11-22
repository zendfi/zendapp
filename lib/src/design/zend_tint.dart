import 'package:flutter/material.dart';

/// A person's or a ZApp's own colour, generated from a stable seed (user id,
/// @tag, or app id) the way Telegram colours avatars.
///
/// The app chrome stays neutral; colour on screen comes from the people and
/// activity in it. Use [ZendTint.of] for the colour, then:
/// - [pastel] with [onPastel] initials for an avatar disc (the same discs
///   zend-site draws, so a person looks the same on the site and in the app),
/// - [wash] and [edge] for a card that belongs to that person (a Link card),
/// - [ink] for text or icons sitting on [wash].
@immutable
class ZendTint {
  const ZendTint._(this.solid, this.pastel, this.isDark);

  /// The tint at full strength. The source for [name], [ink], [wash] and
  /// [edge]; not drawn as a fill on its own.
  final Color solid;

  /// Soft avatar fill, from zend-site's people tints (`lib/people.ts`). Same
  /// in both modes so a person keeps one face. Initials go on it in
  /// [onPastel].
  final Color pastel;
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

  /// Avatar fills, one per [palette] hue in the same order, so a person's
  /// pastel disc and their name colour stay the same family.
  static const pastels = <Color>[
    Color(0xFFEBA3A3), // red
    Color(0xFFF2A08B), // orange (coral)
    Color(0xFFF4B740), // amber
    Color(0xFF93CBA0), // green
    Color(0xFF9ED9CC), // teal
    Color(0xFF8DBDEB), // sky
    Color(0xFFA9C4F5), // blue
    Color(0xFFC9AAF0), // violet
    Color(0xFFD7B4F3), // orchid
    Color(0xFFF5C3D2), // pink
  ];

  /// Stable tint for [seed] (FNV-1a hash, case-insensitive).
  static ZendTint of(String seed, {bool isDark = false}) {
    final i = _hash(seed) % palette.length;
    return ZendTint._(palette[i], pastels[i], isDark);
  }

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

  /// Initials or icons on [pastel]: always ink. Every pastel clears 7:1
  /// against it.
  Color get onPastel => const Color(0xFF0F0F0E);

  /// Quiet card fill in the person's colour, on the off-white page or true
  /// black.
  Color get wash => isDark
      ? Color.lerp(solid, Colors.black, 0.62)!
      : Color.lerp(solid, Colors.white, 0.76)!;

  /// Hairline outline for a [wash] card.
  Color get edge => solid.withValues(alpha: isDark ? 0.55 : 0.45);

  /// The person's name drawn on a neutral card (the Telegram move: names
  /// carry the person's colour). 4.2:1 or better on cards in both modes.
  Color get name => isDark
      ? Color.lerp(solid, Colors.white, 0.30)!
      : Color.lerp(solid, Colors.black, 0.32)!;

  /// Fill for something that person said (a payment note), lighter than
  /// [wash] so body text in ink reads at 15:1.
  Color get noteFill => isDark
      ? Color.lerp(solid, Colors.black, 0.72)!
      : Color.lerp(solid, Colors.white, 0.82)!;

  /// Text and icons on [wash] (passes 4.5:1).
  Color get ink => isDark
      ? Color.lerp(solid, Colors.white, 0.45)!
      : Color.lerp(solid, Colors.black, 0.50)!;
}
