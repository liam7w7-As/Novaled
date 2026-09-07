import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';

class ProgressQuotaBar extends StatelessWidget {
  final int actual;
  final int limite; // -1 para ilimitado
  final String label;

  const ProgressQuotaBar({
    super.key,
    required this.actual,
    required this.limite,
    this.label = 'Docs/mes',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (limite == -1) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.all_inclusive_rounded, size: 16, color: AppColors.success),
          const SizedBox(width: 4),
          Text(
            '$actual emitidos',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary,
            ),
          ),
        ],
      );
    }

    final double porcentaje = (actual / limite).clamp(0.0, 1.0);
    Color barColor;
    if (porcentaje >= 0.9) {
      barColor = AppColors.danger;
    } else if (porcentaje >= 0.7) {
      barColor = AppColors.warning;
    } else {
      barColor = AppColors.primaryPurple;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$actual / $limite $label',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary,
              ),
            ),
            Text(
              '${(porcentaje * 100).toInt()}%',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 6,
            width: 140,
            color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: porcentaje,
              child: Container(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
