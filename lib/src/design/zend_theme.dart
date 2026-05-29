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
      // No focus highlight — clean, no border on focus
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.xl),
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
        fontFamily: 'DMSans',
        bodyColor: darkTextPrimary,
        displayColor: darkTextPrimary,
      )
      .copyWith(
        displayLarge: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 56,
          height: 1.04,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
        ),
        displayMedium: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 32,
          height: 1.08,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
        ),
        headlineMedium: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 28,
          height: 1.08,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
        ),
        headlineSmall: const TextStyle(
          fontFamily: 'InstrumentSerif',
          fontSize: 24,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 15,
          height: 1.35,
          color: darkTextPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13,
          height: 1.35,
          color: darkTextSecondary,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: darkTextPrimary,
        ),
      );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'DMSans',
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
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        borderSide: BorderSide.none,
      ),
      // No focus highlight — clean, no border on focus
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZendRadii.xl),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
