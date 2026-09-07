import 'package:flutter/material.dart';

class AppColors {
  // Paleta Primaria Oficial
  static const Color primaryPurple = Color(0xFF5842F4);
  static const Color primaryPurpleLight = Color(0xFF7B66FF);
  static const Color primaryPurpleDark = Color(0xFF3F2BB8);
  static const Color primaryCyan = Color(0xFF00ADEF);

  // Estados Comerciales (Código de Colores Oficial)
  static const Color stateGreenSuccess = Color(0xFF10B981); // Venta pagada / Aprobada
  static const Color stateOrangeWarning = Color(0xFFF59E0B); // Venta anulada / Pendiente
  static const Color stateBlueCobrar = Color(0xFF00ADEF);    // Por cobrar
  static const Color stateRedError = Color(0xFFEF4444);      // Error / Cancelado

  // Fondos Modo Oscuro
  static const Color darkBgPrimary = Color(0xFF11130E);
  static const Color darkBgSecondary = Color(0xFF161913);
  static const Color darkCard = Color(0xFF1E211A);
  static const Color darkCardHover = Color(0xFF252A20);
  static const Color darkBorder = Color(0x1AFFFFFF); // Blanco 10%
  static const Color darkTextPrimary = Colors.white;
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  // Fondos Modo Claro
  static const Color lightBgPrimary = Color(0xFFF8FAFC);
  static const Color lightBgSecondary = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);

  // Gradientes Globales
  static const LinearGradient purpleGradient = LinearGradient(
    colors: [primaryPurple, primaryPurpleLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    colors: [Color(0xFF1E211A), Color(0xFF171A14)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Helpers de Color Adaptativos
  static Color bg(bool isDark) => isDark ? darkBgPrimary : lightBgPrimary;
  static Color card(bool isDark) => isDark ? darkCard : lightCard;
  static Color border(bool isDark) => isDark ? darkBorder : lightBorder;
  static Color textPrimary(bool isDark) => isDark ? darkTextPrimary : lightTextPrimary;
  static Color textSecondary(bool isDark) => isDark ? darkTextSecondary : lightTextSecondary;
}
