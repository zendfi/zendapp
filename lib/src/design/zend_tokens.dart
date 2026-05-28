import 'package:flutter/material.dart';

class ZendColors {
  static const bgPrimary = Color(0xFFFAFAF7);
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
    bgPrimary: Color(0xFFFAFAF7),
    bgSecondary: Color(0xFFF2F0EA),
    bgCard: Color(0xFFF2F0EA),
    bgElevated: Color(0xFFFFFFFF),
    bgAccentSurface: Color(0xFFF2F0EA),
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
    bgPrimary: Color(0xFF0D0D0D),
    bgSecondary: Color(0xFF161616),
    bgCard: Color(0xFF1E1E1E),
    bgElevated: Color(0xFF252525),
    bgAccentSurface: Color(0xFF0A1A0D),
    textPrimary: Color(0xFFF0F0F0),
    textSecondary: Color(0xFF8A8A8A),
    border: Color(0xFF2A2A2A),
    accent: Color(0xFF52B788),
    accentBright: Color(0xFF6FCF97),
    accentPop: Color(0xFF95D5B2),
    positive: Color(0xFF52B788),
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
