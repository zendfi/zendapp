import 'package:flutter/material.dart';

class ZendColors {
  //static const bgPrimary = Color(0xFFFAFAF7);
  static const bgPrimary = Color(0xFFFFFFFF);
  static const bgSecondary = Color(0xFFF2F0EA);
  static const accent = Color(0xFF2D6A4F);
  static const accentBright = Color(0xFF52B788);
  static const accentPop = Color(0xFF95D5B2);
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF6B7A6E);
  static const textOnDeep = Color(0xFFF0F0F0);
  static const positive = Color(0xFF52B788);
  static const negative = Color(0xFF1A1A1A);
  static const destructive = Color(0xFFC94F2A);
  static const border = Color(0xFFE5E2DA);
  static const bgDeep = Color(0xFF122018);
  static const bgAccentSurface = Color(0xFF0A1A0D);
}

class ZendTheme {
  const ZendTheme._({
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgCard,
    required this.bgElevated,
    required this.bgAccentSurface,
    required this.chatBg,
    required this.bubbleReceived,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.accent,
    required this.accentBright,
    required this.accentPop,
    required this.positive,
    required this.destructive,
    required this.isDark,
  });

  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgCard;
  final Color bgElevated;
  final Color bgAccentSurface;
  /// Chat-thread canvas colour — deliberately distinct from [bgPrimary] (the
  /// app-wide scaffold background) and from [bubbleReceived], so a message
  /// thread reads as its own surface with bubbles sitting visibly *on* it
  /// rather than blending into a near-identical background. Mirrors the
  /// WhatsApp/iMessage pattern where the chat canvas and the bubble fill are
  /// always a few percent apart in luminance.
  final Color chatBg;
  /// Fill colour for incoming (received) text/payment bubbles. Kept separate
  /// from [bgSecondary] — which is reused all over the app for cards, input
  /// fills, sheets, etc — so bumping bubble contrast never risks regressing
  /// any of those unrelated surfaces.
  final Color bubbleReceived;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color accent;
  final Color accentBright;
  final Color accentPop;
  final Color positive;
  final Color destructive;
  final bool isDark;

  static const _light = ZendTheme._(
    //bgPrimary: Color(0xFFFAFAF7),
    bgPrimary: Color(0xFFFFFFFF),
    bgSecondary: Color(0xFFF2F0EA),
    bgCard: Color(0xFFF2F0EA),
    bgElevated: Color(0xFFFFFFFF),
    bgAccentSurface: Color(0xFFF2F0EA),
    // Warm beige canvas (WhatsApp-style wallpaper tone) with a crisp white
    // bubble on top — the ~7% luminance gap is what makes bubbles read as
    // distinct objects instead of blending into the page.
    chatBg: Color(0xFFEDE8DC),
    bubbleReceived: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF6B7A6E),
    border: Color(0xFFE5E2DA),
    accent: Color(0xFF2D6A4F),
    accentBright: Color(0xFF52B788),
    accentPop: Color(0xFF95D5B2),
    positive: Color(0xFF52B788),
    destructive: Color(0xFFC94F2A),
    isDark: false,
  );

  static const _dark = ZendTheme._(
    // bgPrimary: Color(0xFF0D0D0D),
    bgPrimary: Color(0xFF000000),
    bgSecondary: Color(0xFF161616),
    bgCard: Color(0xFF1E1E1E),
    bgElevated: Color(0xFF252525),
    bgAccentSurface: Color(0xFF0A1A0D),
    // Near-black canvas with a clearly lighter, elevated bubble fill —
    // matches iMessage/WhatsApp dark mode's "bubble sits above the canvas"
    // depth instead of the ~3% gap bgPrimary/bgSecondary gave it before.
    chatBg: Color(0xFF101010),
    bubbleReceived: Color(0xFF262626),
    textPrimary: Color(0xFFF0F0F0),
    textSecondary: Color(0xFF8A8A8A),
    border: Color(0xFF2A2A2A),
    accent: Color(0xFF52B788),
    // accentBright in dark is deliberately quieter than light — the #52B788
    // / #6FCF97 values were too vivid against the dark background, clashing
    // with the muted dark palette. A slightly desaturated mid-green reads as
    // "branded" without the visual shout.
    accentBright: Color(0xFF4A9E72),
    accentPop: Color(0xFF7BC4A0),
    positive: Color(0xFF4A9E72),
    destructive: Color(0xFFE05C3A),
    isDark: true,
  );

  static ZendTheme of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? _dark : _light;
  }
}

class ZendRadii {
  static const double xs = 8;
  static const double sm = 10;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 16;
  static const double xxl = 28;
  static const double pill = 999;
}

class ZendSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

class ZendMotion {
  static const Duration tabSwitch = Duration(milliseconds: 240);
  static const Duration amountTick = Duration(milliseconds: 60);
  static const Duration keypadPress = Duration(milliseconds: 80);
  static const Duration sheetEnter = Duration(milliseconds: 380);
  static const Duration splash = Duration(milliseconds: 1400);
}

class ZendTextStyles {
  /// Use anywhere digits need to stay a fixed width — OTP boxes, PIN dots,
  /// balances, phone number input. Replaces the old DMMono usage.
  static const TextStyle tabularNumeric = TextStyle(
    fontFamily: 'Geist',
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class ZendScale {
  /// Returns a width-relative scale factor based on the device's screen width
  /// divided by the 375dp reference width (iPhone SE / standard design frame).
  /// Use this to scale padding, spacing, icon sizes, and other layout values
  /// so the UI adapts proportionally across different device widths.
  ///
  /// The result is clamped to (0.85, 1.3) so that tablets and very narrow
  /// devices don't produce extreme scaling values that break layouts.
  static double of(BuildContext context) {
    return (MediaQuery.sizeOf(context).width / 375.0).clamp(0.85, 1.3);
  }

  /// Convenience method: returns [base] multiplied by the width-relative scale
  /// factor. Useful for inline scaled-value lookups in widget trees, e.g.
  /// `ZendScale.value(context, 16)` for a 16dp reference spacing.
  static double value(BuildContext context, double base) {
    return base * of(context);
  }
}
