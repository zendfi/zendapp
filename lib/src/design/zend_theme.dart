import 'package:flutter/material.dart';
import 'zend_tokens.dart';

ThemeData buildZendTheme() {
  final base = ThemeData.light(useMaterial3: true);
  final textTheme = base.textTheme
      .apply(
        fontFamily: 'DMSans',
        bodyColor: ZendColors.textPrimary,
        displayColor: ZendColors.textPrimary,
      )
      .copyWith(
        displayLarge: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 56,
          height: 1.04,
          fontWeight: FontWeight.w700,
          color: ZendColors.textPrimary,
        ),
        displayMedium: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 32,
          height: 1.08,
          fontWeight: FontWeight.w700,
          color: ZendColors.textPrimary,
        ),
        headlineMedium: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 28,
          height: 1.08,
          fontWeight: FontWeight.w700,
          color: ZendColors.textPrimary,
        ),
        headlineSmall: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 24,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: ZendColors.textPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: ZendColors.textPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: ZendColors.textPrimary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 15,
          height: 1.35,
          color: ZendColors.textPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13,
          height: 1.35,
          color: ZendColors.textSecondary,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ZendColors.textPrimary,
        ),
      );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'DMSans',
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
    dividerTheme: const DividerThemeData(color: ZendColors.border, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ZendColors.bgSecondary,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        borderSide: const BorderSide(color: ZendColors.accent, width: 1.2),
      ),
    ),
  );
}

ThemeData buildZendDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = base.textTheme
      .apply(
        fontFamily: 'DMSans',
        bodyColor: ZendColors.textOnDeep,
        displayColor: ZendColors.textOnDeep,
      )
      .copyWith(
        displayLarge: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 56,
          height: 1.04,
          fontWeight: FontWeight.w700,
          color: ZendColors.textOnDeep,
        ),
        displayMedium: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 32,
          height: 1.08,
          fontWeight: FontWeight.w700,
          color: ZendColors.textOnDeep,
        ),
        headlineMedium: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 28,
          height: 1.08,
          fontWeight: FontWeight.w700,
          color: ZendColors.textOnDeep,
        ),
        headlineSmall: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 24,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: ZendColors.textOnDeep,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: ZendColors.textOnDeep,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: ZendColors.textOnDeep,
        ),
        bodyLarge: const TextStyle(
          fontSize: 15,
          height: 1.35,
          color: ZendColors.textOnDeep,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13,
          height: 1.35,
          color: Color(0x99E8F4EC),
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ZendColors.textOnDeep,
        ),
      );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'DMSans',
    colorScheme: const ColorScheme.dark(
      primary: ZendColors.accentBright,
      secondary: ZendColors.accentPop,
      surface: ZendColors.bgDeep,
      onPrimary: ZendColors.textPrimary,
      onSurface: ZendColors.textOnDeep,
      error: ZendColors.destructive,
    ),
    scaffoldBackgroundColor: ZendColors.bgDeep,
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    dividerTheme: const DividerThemeData(color: Color(0x26E8F4EC), thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x1AE8F4EC),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        borderSide: const BorderSide(color: ZendColors.accentBright, width: 1.2),
      ),
    ),
  );
}
