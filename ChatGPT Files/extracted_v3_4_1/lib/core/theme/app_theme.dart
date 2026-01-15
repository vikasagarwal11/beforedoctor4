import 'package:flutter/material.dart';
import '../constants/tokens.dart';

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _textTheme(Brightness.light),
      appBarTheme: const AppBarTheme(centerTitle: false),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          side: const BorderSide(color: AppColors.outline),
        ),
        labelStyle: const TextStyle(color: AppColors.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.sm),
      ),
      cardTheme: CardThemeData(
        elevation: AppTokens.e1,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          side: const BorderSide(color: AppColors.outline),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
    );
    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _textTheme(Brightness.dark),
      appBarTheme: const AppBarTheme(centerTitle: false),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          side: const BorderSide(color: AppColors.darkOutline),
        ),
        labelStyle: const TextStyle(color: AppColors.darkTextPrimary),
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.sm),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.darkSurfaceMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          side: const BorderSide(color: AppColors.darkOutline),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          borderSide: const BorderSide(color: AppColors.darkOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          borderSide: const BorderSide(color: AppColors.darkOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }

  static TextTheme _textTheme(Brightness b) {
    final primary = b == Brightness.dark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final secondary = b == Brightness.dark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return TextTheme(
      titleLarge: TextStyle(fontSize: AppTokens.title, fontWeight: FontWeight.w700, color: primary),
      titleMedium: TextStyle(fontSize: AppTokens.h2, fontWeight: FontWeight.w700, color: primary),
      bodyLarge: TextStyle(fontSize: AppTokens.body, fontWeight: FontWeight.w500, color: primary),
      bodyMedium: TextStyle(fontSize: AppTokens.body, fontWeight: FontWeight.w400, color: primary),
      bodySmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: secondary),
      labelSmall: TextStyle(fontSize: AppTokens.caption, fontWeight: FontWeight.w600, color: secondary),
    );
  }
}
