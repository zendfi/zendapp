import 'package:flutter/material.dart';

/// Raw, non-mode-aware brand colors. Prefer [ZendTheme.of] for anything that
/// needs to react to light/dark mode — this class exists for the rare spot
/// that genuinely wants one fixed value regardless of mode (e.g. a splash
/// screen that renders before Theme is available).
class ZendColors {
  static const bgPrimary = Color(0xFFFAFAF8);
  static const bgSecondary = Color(0xFFF2F0EA);

  /// Restrained-accent rule: this green is only for a primary CTA fill, a
  /// sent-message bubble, or a positive-state indicator (a completed
  /// transfer, a success tick). It never fills chrome, nav, icons, or cards.
  /// Everything else in the app stays neutral so these moments stay legible
  /// as "this needs your attention" rather than becoming wallpaper.
  static const accent = Color(0xFF16A34A);
  static const accentBright = Color(0xFF22C55E);
  static const accentPop = Color(0xFFDCFCE7);

  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF6B7A6E);
  static const textOnDeep = Color(0xFFF0F0F0);

  static const positive = Color(0xFF22C55E);
  /// Negative amounts render in near-black, not red — a deliberate "boring"
  /// choice so a debit doesn't read as an alarm. [destructive] is reserved
  /// for actual destructive actions (delete, remove card), not routine
  /// negative numbers.
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
  /// any of those unrelated surfaces. Always neutral: only the *sent* side
  /// of a thread carries [accentBright].
  final Color bubbleReceived;

  final Color textPrimary;
  final Color textSecondary;
  final Color border;

  /// Text/icon-safe brand green — passes AA contrast on [bgPrimary]/[bgCard],
  /// so it's the one to reach for on links, active tab labels, or an icon
  /// that needs to read as "on-brand" without a filled background behind it.
  final Color accent;

  /// Higher-chroma green for filled surfaces: the primary CTA button, the
  /// sent-message bubble, a positive/success indicator. Never used for body
  /// text directly — pair it with a dark-on-fill text colour, not white.
  final Color accentBright;

  /// Soft, low-chroma green wash for chips, badges, and success banners —
  /// a background tint, never a text colour.
  final Color accentPop;

  final Color positive;
  final Color destructive;
  final bool isDark;

  static const _light = ZendTheme._(
    bgPrimary: Color(0xFFFAFAF8),
    bgSecondary: Color(0xFFF2F0EA),
    // Cards render pure white against the warm off-white page — that small
    // luminance gap is what makes a card read as an object sitting *on* the
    // page rather than a tinted rectangle blending into it.
    bgCard: Color(0xFFFFFFFF),
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
    accent: Color(0xFF16A34A),
    accentBright: Color(0xFF22C55E),
    accentPop: Color(0xFFDCFCE7),
    positive: Color(0xFF22C55E),
    destructive: Color(0xFFC94F2A),
    isDark: false,
  );

  static const _dark = ZendTheme._(
    // Off-black, not pure black — true #000000 causes light-text halation
    // on OLED and reads harsher than it needs to for a screen people look
    // at for minutes at a time.
    bgPrimary: Color(0xFF101010),
    bgSecondary: Color(0xFF161616),
    bgCard: Color(0xFF1E1E1E),
    bgElevated: Color(0xFF252525),
    bgAccentSurface: Color(0xFF0A1A0D),
    // A step lighter than bgPrimary — same "canvas distinct from scaffold"
    // logic as light mode, just compressed since dark-mode luminance steps
    // are smaller to begin with.
    chatBg: Color(0xFF141414),
    bubbleReceived: Color(0xFF262626),
    // Off-white, not pure white — mirrors the bgPrimary reasoning: full
    // #FFFFFF text on a near-black surface glows/smears for a lot of eyes.
    textPrimary: Color(0xFFF0F0F0),
    textSecondary: Color(0xFF8A8A8A),
    border: Color(0xFF2A2A2A),
    // Brighter than the light-mode accent on purpose — dark surfaces can
    // carry more saturated color before it feels aggressive, so this still
    // reads calm rather than muted-to-the-point-of-invisible.
    accent: Color(0xFF22C55E),
    accentBright: Color(0xFF4ADE80),
    // Dark, low-chroma wash rather than a pale one — a light mint chip would
    // float awkwardly bright against a near-black card.
    accentPop: Color(0xFF14532D),
    positive: Color(0xFF4ADE80),
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