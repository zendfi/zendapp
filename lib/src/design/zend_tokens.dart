import 'package:flutter/material.dart';

/// Raw, non-mode-aware brand colors. Prefer [ZendTheme.of] for anything that
/// needs to react to light/dark mode — this class exists for the rare spot
/// that genuinely wants one fixed value regardless of mode (e.g. a splash
/// screen that renders before Theme is available).
///
/// Identity: warm neutrals, ink as the action colour, and colour that comes
/// from people (see `zend_tint.dart`), not from the brand. The one brand hue
/// left is [signal], kept to dots and badges.
class ZendColors {
  /// Barely-warm off-white page, never pure #FFF.
  static const bgPrimary = Color(0xFFF2F1ED);
  static const bgSecondary = Color(0xFFE8E6E1);

  /// Ink. Primary actions are soft black on light surfaces. Screens with a
  /// permanently dark background use [textOnDeep] fills instead.
  static const accent = Color(0xFF0F0F0E);

  /// Same ink as [accent]. Mode-aware code should use [ZendTheme.accent].
  static const accentBright = Color(0xFF0F0F0E);

  /// Light-on-dark highlight for permanently dark surfaces (PIN dots, the
  /// in-app banners, the Zend button).
  static const accentPop = Color(0xFFF7F6F3);

  /// Soft black, never pure #000.
  static const textPrimary = Color(0xFF0F0F0E);
  static const textSecondary = Color(0xFF5C5B57);
  static const textOnDeep = Color(0xFFF7F6F3);

  /// Success ticks and online dots only. Amounts never use it: a `+` sign
  /// carries direction.
  static const positive = Color(0xFF12A150);

  /// Negative amounts render in ink, not red, so a debit doesn't read as an
  /// alarm. [destructive] is for delete/remove actions and errors.
  static const negative = Color(0xFF0F0F0E);
  static const destructive = Color(0xFFD92D20);

  /// The single small signal: unread badges, notification dots, and Links
  /// nobody has collected yet. Dots and badges only, never fills or text.
  static const signal = Color(0xFFFF4D1A);
  static const onSignal = Color(0xFF0F0F0E);

  static const border = Color(0xFFE2E0DA);

  /// Permanently dark surfaces (PIN setup, QR, onboarding success).
  static const bgDeep = Color(0xFF111111);
  static const bgAccentSurface = Color(0xFF1E1E1D);
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
    required this.onAccent,
    required this.accentBright,
    required this.accentPop,
    required this.positive,
    required this.destructive,
    required this.signal,
    required this.onSignal,
    required this.isDark,
  });

  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgCard;
  final Color bgElevated;
  final Color bgAccentSurface;

  /// Chat-thread canvas colour, a few percent apart from [bubbleReceived] so
  /// bubbles read as objects sitting on it.
  final Color chatBg;

  /// Fill for incoming (received) text and payment bubbles.
  final Color bubbleReceived;

  final Color textPrimary;
  final Color textSecondary;
  final Color border;

  /// Ink: the primary action fill, active states, selected chips. Soft black
  /// in light mode, warm off-white in dark mode. Always pair a fill with
  /// [onAccent], never a hardcoded white.
  final Color accent;

  /// Text and icons on an [accent] fill.
  final Color onAccent;

  /// Same ink as [accent]; kept so existing call sites keep compiling.
  final Color accentBright;

  /// Low-contrast warm wash for chips and "selected by me" states. A
  /// background, never a text colour.
  final Color accentPop;

  /// Success ticks and online dots. Not used for amounts.
  final Color positive;
  final Color destructive;

  /// The one small brand signal: unread badges, notification dots, Links
  /// nobody has collected yet. Keep it to dots and badges (well under 1% of
  /// the screen) so it stays a signal.
  final Color signal;

  /// Text on a [signal] badge.
  final Color onSignal;

  final bool isDark;

  static const _light = ZendTheme._(
    // Barely-warm off-white page with near-white cards on top. The page sits
    // a step darker (1.13:1) so cards, bubbles and chips visibly lift off it;
    // with no brand colour, that separation is what keeps it from looking flat.
    bgPrimary: Color(0xFFF2F1ED),
    bgSecondary: Color(0xFFE8E6E1),
    bgCard: Color(0xFFFFFEFC),
    bgElevated: Color(0xFFFFFEFC),
    bgAccentSurface: Color(0xFFE8E6E1),
    chatBg: Color(0xFFE8E6E0),
    bubbleReceived: Color(0xFFFFFEFC),
    // Soft black (17:1 on the page) and a near-neutral grey (6:1).
    textPrimary: Color(0xFF0F0F0E),
    textSecondary: Color(0xFF5C5B57),
    border: Color(0xFFE2E0DA),
    accent: Color(0xFF0F0F0E),
    onAccent: Color(0xFFFFFEFC),
    accentBright: Color(0xFF0F0F0E),
    accentPop: Color(0xFFE3E1DB),
    positive: Color(0xFF12A150),
    destructive: Color(0xFFD92D20),
    signal: Color(0xFFFF4D1A),
    onSignal: Color(0xFF0F0F0E),
    isDark: false,
  );

  // True black base: native on OLED phones and saves battery there. Raised
  // surfaces are warm near-blacks so sheets and cards still separate.
  static const _dark = ZendTheme._(
    bgPrimary: Color(0xFF000000),
    bgSecondary: Color(0xFF141414),
    bgCard: Color(0xFF141414),
    bgElevated: Color(0xFF1F1F1E),
    bgAccentSurface: Color(0xFF1F1F1E),
    chatBg: Color(0xFF000000),
    bubbleReceived: Color(0xFF1F1F1E),
    // Off-white (19:1 on black) and a neutral grey (8.3:1).
    textPrimary: Color(0xFFF7F6F3),
    textSecondary: Color(0xFFA3A3A0),
    border: Color(0xFF2A2A28),
    accent: Color(0xFFF7F6F3),
    onAccent: Color(0xFF0A0A0A),
    accentBright: Color(0xFFF7F6F3),
    accentPop: Color(0xFF2A2A28),
    positive: Color(0xFF2FD27A),
    destructive: Color(0xFFFF5A4F),
    signal: Color(0xFFFF5C2B),
    onSignal: Color(0xFF0A0A0A),
    isDark: true,
  );

  /// Sent chat bubble: solid ink, inverted per mode (black on light,
  /// off-white on true black). Text on it uses [onBubbleSent].
  Color get bubbleSent => accent;
  Color get onBubbleSent => onAccent;

  /// Payment in progress.
  Color get pending =>
      isDark ? const Color(0xFFF5B83D) : const Color(0xFFB7791F);

  /// Sent amounts stay neutral, never red.
  Color get moneyOut => textPrimary;

  /// Received amounts are ink too. The `+` sign carries the direction, and
  /// the receive moment (haptics, motion, the note) carries the feeling.
  Color get moneyIn => textPrimary;

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

  // Type is the brand: amounts are the loudest thing on any screen. Tight
  // negative tracking at these sizes is what makes Geist read as confident
  // rather than generic. Draw them through ZendAmount/ZendRollingAmount,
  // which also shrink the currency sign so the digits lead.

  /// 72/72 bold: Home balance and the receive moment.
  static const displayXl = TextStyle(
    fontFamily: _display,
    fontSize: 72,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -3.2,
    fontFeatures: _tabular,
  );

  /// [displayXl] for an amount being typed: steps down as the figure grows
  /// so "1,000,000" still fits a 360dp phone without the field scrolling.
  static TextStyle amountInput(String text) {
    final n = text.length;
    final size = n <= 6
        ? 72.0
        : n <= 8
        ? 60.0
        : 48.0;
    return displayXl.copyWith(fontSize: size, letterSpacing: -size * 0.044);
  }

  /// 52/56 bold: receipt and send amount.
  static const displayL = TextStyle(
    fontFamily: _display,
    fontSize: 52,
    height: 56 / 52,
    fontWeight: FontWeight.w700,
    letterSpacing: -2.2,
    fontFeatures: _tabular,
  );

  /// 24/28 bold: feed card amounts.
  static const amountM = TextStyle(
    fontFamily: _display,
    fontSize: 24,
    height: 28 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
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
