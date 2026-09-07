import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';

class PlanBadge extends StatelessWidget {
  final String planId;
  final bool isLarge;

  const PlanBadge({
    super.key,
    required this.planId,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color border;
    Color textColor;
    String label;
    IconData icon;

    final pid = planId.toLowerCase();

    if (pid == 'free' || pid == 'gratis') {
      bg = isDark ? Colors.white10 : const Color(0xFFE2E8F0);
      border = isDark ? Colors.white24 : const Color(0xFFCBD5E1);
      textColor = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
      label = 'GRATIS (Bs. 0)';
      icon = Icons.star_border_rounded;
    } else if (pid == 'plus' || pid == 'pro_anual') {
      bg = AppColors.primaryGold.withOpacity(0.15);
      border = AppColors.primaryGold.withOpacity(0.4);
      textColor = isDark ? AppColors.primaryGold : const Color(0xFFB45309);
      label = 'PLAN PLUS 👑';
      icon = Icons.verified_rounded;
    } else {
      bg = AppColors.primaryPurple.withOpacity(0.15);
      border = AppColors.primaryPurple.withOpacity(0.4);
      textColor = isDark ? const Color(0xFFA5B4FC) : AppColors.primaryPurple;
      label = 'PLAN PRO ⚡';
      icon = Icons.bolt_rounded;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLarge ? 12 : 8,
        vertical: isLarge ? 6 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isLarge ? 16 : 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: isLarge ? 13 : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
