import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

enum DocumentStatus {
  pendiente,
  aprobada,
  facturada,
  entregada,
  anulada,
  pagado,
  porCobrar,
  enRevision,
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final DocumentStatus? status;
  final IconData? icon;
  final bool outlined;
  final double fontSize;

  const StatusBadge({
    super.key,
    required this.label,
    this.color,
    this.status,
    this.icon,
    this.outlined = false,
    this.fontSize = 11,
  });

  factory StatusBadge.fromStatus(DocumentStatus status, {bool outlined = false, double fontSize = 11}) {
    switch (status) {
      case DocumentStatus.pagado:
        return StatusBadge(
          label: "Pagado",
          color: AppColors.stateGreenSuccess,
          icon: Icons.check_circle_outline_rounded,
          outlined: outlined,
          fontSize: fontSize,
        );
      case DocumentStatus.porCobrar:
        return StatusBadge(
          label: "Por cobrar",
          color: AppColors.stateBlueCobrar,
          icon: Icons.access_time_rounded,
          outlined: outlined,
          fontSize: fontSize,
        );
      case DocumentStatus.pendiente:
        return StatusBadge(
          label: "Pendiente",
          color: AppColors.stateOrangeWarning,
          icon: Icons.hourglass_empty_rounded,
          outlined: outlined,
          fontSize: fontSize,
        );
      case DocumentStatus.aprobada:
      case DocumentStatus.entregada:
        return StatusBadge(
          label: status == DocumentStatus.aprobada ? "Aprobada" : "Entregada",
          color: AppColors.stateGreenSuccess,
          icon: Icons.task_alt_rounded,
          outlined: outlined,
          fontSize: fontSize,
        );
      case DocumentStatus.facturada:
        return StatusBadge(
          label: "Facturada",
          color: AppColors.primaryPurple,
          icon: Icons.receipt_long_rounded,
          outlined: outlined,
          fontSize: fontSize,
        );
      case DocumentStatus.anulada:
        return StatusBadge(
          label: "Anulada",
          color: AppColors.stateRedError,
          icon: Icons.cancel_outlined,
          outlined: outlined,
          fontSize: fontSize,
        );
      case DocumentStatus.enRevision:
        return StatusBadge(
          label: "En revisión",
          color: AppColors.stateOrangeWarning,
          icon: Icons.rate_review_outlined,
          outlined: outlined,
          fontSize: fontSize,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.primaryPurple;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : effectiveColor.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: effectiveColor.withValues(alpha: outlined ? 1.0 : (isDark ? 0.4 : 0.25)),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: effectiveColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: effectiveColor,
            ),
          ),
        ],
      ),
    );
  }
}
