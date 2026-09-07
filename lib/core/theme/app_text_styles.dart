import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  // Encabezados y Títulos
  static TextStyle h1(bool isDark) => GoogleFonts.poppins(
    fontSize: 26,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary(isDark),
  );

  static TextStyle h2(bool isDark) => GoogleFonts.poppins(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary(isDark),
  );

  static TextStyle h3(bool isDark) => GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary(isDark),
  );

  // Cuerpo de Texto
  static TextStyle body(bool isDark) => GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary(isDark),
  );

  static TextStyle bodyMedium(bool isDark) => GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary(isDark),
  );

  static TextStyle bodySecondary(bool isDark) => GoogleFonts.poppins(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary(isDark),
  );

  static TextStyle caption(bool isDark) => GoogleFonts.poppins(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary(isDark),
  );

  // Botones y Badges
  static TextStyle button = GoogleFonts.poppins(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static TextStyle badge(Color color) => GoogleFonts.poppins(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    color: color,
  );

  // Valores de Métricas
  static TextStyle metricValue(bool isDark) => GoogleFonts.poppins(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary(isDark),
  );
}
