import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';

class StatusPill extends StatelessWidget {
  final String estado;
  final int? diasRestantes;

  const StatusPill({
    super.key,
    required this.estado,
    this.diasRestantes,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color color;
    String text;

    switch (estado) {
      case 'activo_free':
        color = AppColors.neutral;
        text = 'Activo (Free)';
        break;
      case 'trial_pro':
        color = AppColors.info;
        text = diasRestantes != null ? 'Trial ($diasRestantes d)' : 'Trial PRO';
        break;
      case 'activo_pro':
        color = AppColors.success;
        text = 'Activo (PRO)';
        break;
      case 'por_vencer':
        color = AppColors.warning;
        text = diasRestantes != null ? 'Por vencer ($diasRestantes d)' : 'Por Vencer';
        break;
      case 'gracia':
        color = const Color(0xFFF97316);
        text = 'En Gracia';
        break;
      case 'suspendido':
        color = AppColors.danger;
        text = 'Suspendido';
        break;
      case 'eliminado':
        color = Colors.black45;
        text = 'Eliminado';
        break;
      default:
        color = AppColors.neutral;
        text = estado.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? color : color.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }
}
