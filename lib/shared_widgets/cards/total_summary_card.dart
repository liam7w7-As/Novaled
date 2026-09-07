import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';

class TotalSummaryCard extends StatelessWidget {
  final double subtotal;
  final double descuento;
  final double impuesto;
  final double total;
  final double? saldoCancelado;
  final String moneda;
  final bool showCancelado;

  const TotalSummaryCard({
    super.key,
    required this.subtotal,
    this.descuento = 0.0,
    this.impuesto = 0.0,
    required this.total,
    this.saldoCancelado,
    this.moneda = 'Bs',
    this.showCancelado = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double saldoPendiente = total - (saldoCancelado ?? 0.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Resumen de Totales",
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 14),
          _buildRow("Subtotal", "${subtotal.toStringAsFixed(2)} $moneda", isDark),
          if (descuento > 0) ...[
            const SizedBox(height: 8),
            _buildRow(
              "Descuento",
              "- ${descuento.toStringAsFixed(2)} $moneda",
              isDark,
              valueColor: AppColors.stateOrangeWarning,
            ),
          ],
          if (impuesto > 0) ...[
            const SizedBox(height: 8),
            _buildRow("Impuestos / IVA", "+ ${impuesto.toStringAsFixed(2)} $moneda", isDark),
          ],
          const Divider(height: 24, thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "TOTAL NETO",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryPurple,
                ),
              ),
              Text(
                "${total.toStringAsFixed(2)} $moneda",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryPurple,
                ),
              ),
            ],
          ),
          if (showCancelado && saldoCancelado != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161913) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildRow(
                    "Cancelado / Pagado",
                    "${saldoCancelado!.toStringAsFixed(2)} $moneda",
                    isDark,
                    valueColor: AppColors.stateGreenSuccess,
                    isBold: true,
                  ),
                  const SizedBox(height: 6),
                  _buildRow(
                    "Saldo Pendiente",
                    "${(saldoPendiente > 0 ? saldoPendiente : 0.0).toStringAsFixed(2)} $moneda",
                    isDark,
                    valueColor: saldoPendiente > 0 ? AppColors.stateBlueCobrar : AppColors.stateGreenSuccess,
                    isBold: true,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(
    String label,
    String value,
    bool isDark, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textSecondary(isDark),
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary(isDark),
          ),
        ),
      ],
    );
  }
}
