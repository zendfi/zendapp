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
  // True neutral gray, not the old green-tinted #6B7A6E — with containers
  // stripped back to hairline dividers, a tinted secondary text color reads
  // as a mistake rather than a choice; there's no card fill left to justify it.
  static const textSecondary = Color(0xFF8C8C86);
  static const textOnDeep = Color(0xFFF0F0F0);

  static const positive = Color(0xFF22C55E);

  /// Negative amounts render in near-black, not red — a deliberate "boring"
  /// choice so a debit doesn't read as an alarm. [destructive] is reserved
  /// for actual destructive actions (delete, remove card), not routine
  /// negative numbers.
  static const negative = Color(0xFF1A1A1A);
  static const destructive = Color(0xFFC94F2A);

  // Lightened from #E5E2DA — this now doubles as a hairline row divider
  // (transaction lists, settings rows), not just an outlined-button stroke,
  // so it needs to sit closer to invisible.
  static const border = Color(0xFFECECE8);
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
    // Slightly less warm than before — with textSecondary and border now
    // true-neutral, a strongly beige secondary surface started to clash.
    bgSecondary: Color(0xFFF4F3EF),
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
    // Darkened from #8C8C86 (~3.3:1) to pass 4.5:1 on bgPrimary.
    textSecondary: Color(0xFF6B6B66),
    border: Color(0xFFECECE8),
    accent: Color(0xFF16A34A),
    accentBright: Color(0xFF22C55E),
    accentPop: Color(0xFFDCFCE7),
    positive: Color(0xFF22C55E),
    destructive: Color(0xFFC94F2A),
    isDark: false,
  );

  // Design revamp palette: green-tinted black with three layers (base,
  // surface 1, surface 2) instead of flat neutral gray. Green only ever means
  // money arriving or the primary action.
  // Neutral near-black layers; green is reserved for money in and the
  // primary action so it reads as a signal, not a wash.
  static const _dark = ZendTheme._(
    bgPrimary: Color(0xFF0E0F10), // Base
    bgSecondary: Color(0xFF17181A), // Surface 1
    bgCard: Color(0xFF17181A),
    bgElevated: Color(0xFF212327), // Surface 2
    bgAccentSurface: Color(0xFF13261A),
    chatBg: Color(0xFF121314),
    bubbleReceived: Color(0xFF212327),
    textPrimary: Color(0xFFF2F3F4),
    textSecondary: Color(0xFFA1A1AA), // passes 4.5:1 on Base
    border: Color(0xFF26282C),
    accent: Color(0xFF1FD16A),
    accentBright: Color(0xFF1FD16A),
    accentPop: Color(0xFF123A22),
    positive: Color(0xFF1FD16A),
    destructive: Color(0xFFFF5A5F),
    isDark: true,
  );

  /// Sent chat bubble fill. Darker than [accent] in dark mode so a long
  /// thread of your own messages doesn't glare; light mode unchanged.
  Color get bubbleSent => isDark ? const Color(0xFF15934B) : accent;

  /// Payment in progress.
  Color get pending =>
      isDark ? const Color(0xFFF5B83D) : const Color(0xFFB7791F);

  /// Sent amounts stay neutral, never red.
  Color get moneyOut => textPrimary;

  /// Received amounts and the primary action.
  Color get moneyIn =>
      isDark ? const Color(0xFF1FD16A) : const Color(0xFF15803D);

  static ZendTheme of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? _dark : _light;
  }
}

class ZendRadii {
  // Revamp scale: chips 8, cards 16, sheets/buttons 24, avatars full.
  static const double chip = 8;
  static const double card = 16;
  static const double sheet = 24;
  static const double button = 24;
  static const double xs = 8;
  static const double sm = 10;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 16;
  static const double xxl = 28;
  static const double pill = 999;
}

class ZendSpacing {
  // Revamp rules on the 4px grid: gutter 16, between cards 12, sections 24.
  static const double gutter = 16;
  static const double betweenCards = 12;
  static const double section = 24;
  static const double s48 = 48;
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

class ZendMotion {
  // Named presets — reuse these, don't tune curves per screen.
  static const Curve springSoft = Curves.easeOutBack;
  static const Curve springSnappy = Curves.easeOutCubic;
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 280);
  static const Duration celebrate = Duration(milliseconds: 700);

  /// True when the OS asks for reduced motion; animations become fades.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  static const Duration tabSwitch = Duration(milliseconds: 240);
  static const Duration amountTick = Duration(milliseconds: 60);
  static const Duration keypadPress = Duration(milliseconds: 80);
  static const Duration sheetEnter = Duration(milliseconds: 380);

  /// Switching between steps inside one sheet (Add Cash, Zend entry).
  /// Fast in, faster out, so the old step is gone before the new one is
  /// noticed, instead of both sitting half-faded for 380ms.
  static const Duration stageIn = Duration(milliseconds: 160);
  static const Duration stageOut = Duration(milliseconds: 90);
  static const Duration splash = Duration(milliseconds: 1400);
}

class ZendTextStyles {
  /// Emoji in notes, tiles and reactions: the bundled set first so a 🍕
  /// looks the same on Android, iOS and the web.
  static const emoji = TextStyle(
    fontFamily: 'ZendEmoji',
    fontFamilyFallback: [
      'Apple Color Emoji',
      'Noto Color Emoji',
      'Segoe UI Emoji',
    ],
    height: 1.2,
  );
  static const _display = 'Geist';
  static const _tabular = [FontFeature.tabularFigures()];

  /// 56/60 heavy — Home balance.
  static const displayXl = TextStyle(
    fontFamily: _display,
    fontSize: 56,
    height: 60 / 56,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    fontFeatures: _tabular,
  );

  /// 40/44 heavy — Receipt and send amount.
  static const displayL = TextStyle(
    fontFamily: _display,
    fontSize: 40,
    height: 44 / 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
    fontFeatures: _tabular,
  );

  /// 24/28 bold — Feed card amounts.
  static const amountM = TextStyle(
    fontFamily: _display,
    fontSize: 24,
    height: 28 / 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    fontFeatures: _tabular,
  );

  static const title = TextStyle(
    fontFamily: 'Geist',
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    fontFamily: 'Geist',
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w400,
  );
  static const caption = TextStyle(
    fontFamily: 'Geist',
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );
  static const micro = TextStyle(
    fontFamily: 'Geist',
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
  );

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
