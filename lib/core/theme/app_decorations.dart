import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppDecorations {
  // Decoración de Tarjeta Estándar
  static BoxDecoration card({
    required bool isDark,
    double borderRadius = 16,
    Color? customColor,
    Border? customBorder,
  }) {
    return BoxDecoration(
      color: customColor ?? AppColors.card(isDark),
      borderRadius: BorderRadius.circular(borderRadius),
      border: customBorder ?? Border.all(color: AppColors.border(isDark), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.25 : 0.03),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  // Decoración de Contenedor de Entrada / Inputs
  static InputDecoration input({
    required String hintText,
    required bool isDark,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
        fontSize: 13,
      ),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? const Color(0xFF161913) : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border(isDark), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryPurple, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.stateRedError, width: 1),
      ),
    );
  }

  // Decoración de Píldoras / Badges
  static BoxDecoration pill({
    required Color color,
    double opacity = 0.12,
    double borderRadius = 20,
  }) {
    return BoxDecoration(
      color: color.withOpacity(opacity),
      borderRadius: BorderRadius.circular(borderRadius),
    );
  }
}
