import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: AppColors.primaryGold,
      scaffoldBackgroundColor: AppColors.bgDark,
      cardColor: AppColors.cardDark,
      dividerColor: AppColors.borderDark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryGold,
        secondary: AppColors.primaryPurple,
        surface: AppColors.surfaceDark,
        error: AppColors.danger,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: AppColors.textDarkPrimary,
        displayColor: AppColors.textDarkPrimary,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderDark),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppColors.primaryGold,
      scaffoldBackgroundColor: AppColors.bgLight,
      cardColor: AppColors.cardLight,
      dividerColor: AppColors.borderLight,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryGold,
        secondary: AppColors.primaryPurple,
        surface: AppColors.surfaceLight,
        error: AppColors.danger,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme).apply(
        bodyColor: AppColors.textLightPrimary,
        displayColor: AppColors.textLightPrimary,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),
    );
  }
}
