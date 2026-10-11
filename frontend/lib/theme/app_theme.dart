import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds the Material 3 light/dark themes for BenildeSafe.
///
/// Extracted from `main.dart` without changing a single color, radius,
/// or padding value — every screen continues to render identically.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.forestGreen,
          brightness: brightness,
          surface: isDark ? AppColors.darkSurface : Colors.white,
        ).copyWith(
          primary: isDark ? const Color(0xFF8AC99B) : AppColors.forestGreen,
          onPrimary: isDark ? const Color(0xFF063819) : Colors.white,
          primaryContainer: isDark
              ? const Color(0xFF23452C)
              : AppColors.paleGreen,
          onPrimaryContainer: isDark
              ? const Color(0xFFD1EBD6)
              : const Color(0xFF153B21),
          secondary: isDark ? const Color(0xFFE6C64A) : AppColors.warmGold,
          onSecondary: isDark
              ? const Color(0xFF3B3000)
              : const Color(0xFF28220C),
          secondaryContainer: isDark
              ? const Color(0xFF4A401A)
              : const Color(0xFFFFF4CC),
          onSecondaryContainer: isDark
              ? const Color(0xFFF4E8B0)
              : const Color(0xFF493A00),
          surface: isDark ? AppColors.darkSurface : Colors.white,
          onSurface: isDark
              ? const Color(0xFFE4EAE4)
              : const Color(0xFF1F2D23),
          surfaceContainerHighest: isDark
              ? const Color(0xFF303832)
              : const Color(0xFFF1F5F0),
          outline: isDark ? AppColors.darkOutline : AppColors.borderLight,
        );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark
          ? AppColors.darkScaffold
          : AppColors.scaffoldLight,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.scaffoldLight,
        foregroundColor: isDark
            ? colorScheme.onSurface
            : AppColors.darkTextOnLight,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: colorScheme.primary),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.darkCard : Colors.white,
        elevation: isDark ? 0 : 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.borderLight,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkCard : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 50),
          elevation: 0,
          backgroundColor: isDark
              ? colorScheme.primary
              : AppColors.deepForest,
          foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
          disabledBackgroundColor: isDark
              ? const Color(0xFF303832)
              : const Color(0xFFE6E9E3),
          disabledForegroundColor: isDark
              ? const Color(0xFF89958B)
              : const Color(0xFF898F88),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkBorder : AppColors.borderLight,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        indicatorColor: isDark
            ? const Color(0xFF2D5136)
            : AppColors.paleGreen,
        elevation: 8,
      ),
    );
  }
}