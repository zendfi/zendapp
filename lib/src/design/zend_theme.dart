import 'package:flutter/material.dart';
import 'zend_tokens.dart';

ThemeData buildZendTheme() {
  final base = ThemeData.light(useMaterial3: true);
  final textTheme = base.textTheme
      .apply(
        fontFamily: 'Geist',
        bodyColor: ZendColors.textPrimary,
        displayColor: ZendColors.textPrimary,
      )
      .copyWith(
        // Geist renders slightly looser than DM Sans/Instrument Serif at
        // the same sizes — a small negative letterSpacing tightens tracking
        // without looking cramped, at DISPLAY/HEADLINE/TITLE sizes (18px+)
        // only. bodyLarge/bodyMedium/labelLarge below deliberately stay at
        // neutral (0) tracking: most small Text widgets across the app
        // (badges, timestamps, captions — many well under 12px) never set
        // their own letterSpacing, so they inherit whatever these three
        // styles specify via DefaultTextStyle/TextStyle.merge. Negative
        // tracking that reads as "tightened" at 32px reads as genuinely
        // jagged/cramped at 9-11px, since there's less room between glyphs
        // for anti-aliasing to smooth their edges.
        displayLarge: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 56,
          height: 1.04,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: ZendColors.textPrimary,
        ),
        displayMedium: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 32,
          height: 1.08,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: ZendColors.textPrimary,
        ),
        headlineMedium: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 28,
          height: 1.08,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: ZendColors.textPrimary,
        ),
        headlineSmall: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 24,
          height: 1.1,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: ZendColors.textPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: ZendColors.textPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: ZendColors.textPrimary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 15,
          height: 1.35,
          letterSpacing: 0,
          color: ZendColors.textPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13,
          height: 1.35,
          letterSpacing: 0,
          color: ZendColors.textSecondary,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: ZendColors.textPrimary,
        ),
      );

  return ThemeData(
    // Desktop/web hover: the defaults were a near-white tooltip box popping
    // over the hovered control (covering it) and a strong hover wash. Small,
    // dark, offset tooltips and faint overlays keep buttons clickable.
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      preferBelow: false,
      verticalOffset: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 12,
        color: Colors.white,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    hoverColor: const Color(0x0A000000),
    highlightColor: Colors.transparent,
    splashColor: const Color(0x14000000),
    focusColor: const Color(0x0A000000),
    useMaterial3: true,
    fontFamily: 'Geist',
    colorScheme: const ColorScheme.light(
      primary: ZendColors.accent,
      secondary: ZendColors.accentBright,
      surface: ZendColors.bgPrimary,
      onPrimary: ZendColors.textOnDeep,
      onSurface: ZendColors.textPrimary,
      error: ZendColors.destructive,
    ),
    scaffoldBackgroundColor: ZendColors.bgPrimary,
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    dividerTheme: const DividerThemeData(
      color: ZendColors.border,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ZendColors.bgSecondary,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      // Fully rounded — matches PrimaryButton/OutlineActionButton's pill
      // shape, so every text box in the app reads as the same rounded
      // language as its buttons.
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.pill),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.pill),
        borderSide: BorderSide.none,
      ),
      // No focus highlight — clean, no border on focus
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.pill),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

ThemeData buildZendDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);

  const darkTextPrimary = Color(0xFFF0F0F0);
  const darkTextSecondary = Color(0xFF8A8A8A);

  final textTheme = base.textTheme
      .apply(
        fontFamily: 'Geist',
        bodyColor: darkTextPrimary,
        displayColor: darkTextPrimary,
      )
      .copyWith(
        displayLarge: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 56,
          height: 1.04,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: darkTextPrimary,
        ),
        displayMedium: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 32,
          height: 1.08,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: darkTextPrimary,
        ),
        headlineMedium: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 28,
          height: 1.08,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: darkTextPrimary,
        ),
        headlineSmall: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 24,
          height: 1.1,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: darkTextPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: darkTextPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: darkTextPrimary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 15,
          height: 1.35,
          letterSpacing: 0,
          color: darkTextPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13,
          height: 1.35,
          letterSpacing: 0,
          color: darkTextSecondary,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: darkTextPrimary,
        ),
      );

  return ThemeData(
    // Desktop/web hover: the defaults were a near-white tooltip box popping
    // over the hovered control (covering it) and a strong hover wash. Small,
    // dark, offset tooltips and faint overlays keep buttons clickable.
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      preferBelow: false,
      verticalOffset: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 12,
        color: Colors.white,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2C30),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    hoverColor: const Color(0x0FFFFFFF),
    highlightColor: Colors.transparent,
    splashColor: const Color(0x1AFFFFFF),
    focusColor: const Color(0x0FFFFFFF),
    useMaterial3: true,
    fontFamily: 'Geist',
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF52B788),
      secondary: Color(0xFF95D5B2),
      surface: Color(0xFF0D0D0D),
      onPrimary: Color(0xFF0D0D0D),
      onSurface: darkTextPrimary,
      error: Color(0xFFE05C3A),
    ),
    scaffoldBackgroundColor: const Color(0xFF0D0D0D),
    textTheme: textTheme,
    splashFactory: NoSplash.splashFactory,
    dividerTheme: const DividerThemeData(
      color: Color(0xFF2A2A2A),
      thickness: 1,
    ),
    cardColor: const Color(0xFF1E1E1E),
    // Subtle dark scrim behind sheets/dialogs — helps distinguish sheet from background
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF0D0D0D),
      modalBackgroundColor: Color(0xFF0D0D0D),
      modalBarrierColor: Color(0x80000000),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF161616),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.pill),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.pill),
        borderSide: BorderSide.none,
      ),
      // No focus highlight — clean, no border on focus
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.pill),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
