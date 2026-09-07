import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_colors.dart';
import '../../services/empresa_service.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/plan_badge.dart';
import '../empresas/crear_empresa_modal.dart';
import '../empresas/detalle_empresa_screen.dart';

class DashboardScreen extends StatelessWidget {
  final Function(int) onNavigateTab;

  const DashboardScreen({
    super.key,
    required this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context) {
    final service = context.watch<EmpresaService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    final empresasPorVencer = service.empresas.where((e) => !e.estaEliminado && e.estaPorVencer).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "SuperAdmin Novaled",
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      "Panel de control centralizado para gestión de inquilinos y planes",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const CrearEmpresaModal(),
                  );
                },
                icon: const Icon(Icons.add_rounded, size: 20, color: Colors.black87),
                label: Text(
                  "Nueva Empresa",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGold,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Alerta si hay empresas por vencer
          if (empresasPorVencer.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.alarm_on_rounded, color: AppColors.warning, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Atención: ${empresasPorVencer.length} empresa(s) con suscripción por vencer",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isDark ? Colors.white : const Color(0xFF92400E),
                          ),
                        ),
                        Text(
                          empresasPorVencer.map((e) => "${e.nombreComercial} (${e.diasRestantes}d)").join(', '),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : const Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      service.setFiltroEstado('por_vencer');
                      onNavigateTab(1); // Ir a empresas
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.warning),
                    label: Text(
                      "Revisar",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Tarjetas de Métricas (KPIs)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1050;
              return GridView.count(
                crossAxisCount: isWide ? 3 : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: isWide ? 1.6 : 1.35,
                children: [
                  MetricCard(
                    title: "Total Empresas Activas",
                    value: service.totalEmpresasActivas.toString(),
                    subtitle: "${service.empresas.length} registradas en total",
                    icon: Icons.business_rounded,
                    accentColor: AppColors.primaryGold,
                    changePercentage: "+12%",
                    isPositive: true,
                  ),
                  MetricCard(
                    title: "Total Cotizaciones (En Vivo)",
                    value: service.totalCotizacionesGlobal.toString(),
                    subtitle: "Emitidas por todas las empresas",
                    icon: Icons.description_outlined,
                    accentColor: AppColors.primaryPurple,
                    changePercentage: "Live MySQL",
                    isPositive: true,
                  ),
                  MetricCard(
                    title: "Total Punto de Venta (En Vivo)",
                    value: service.totalPuntoVentaGlobal.toString(),
                    subtitle: "Ventas y notas de entrega",
                    icon: Icons.point_of_sale_rounded,
                    accentColor: AppColors.success,
                    changePercentage: "Live MySQL",
                    isPositive: true,
                  ),
                  MetricCard(
                    title: "Ingresos Recurrentes (MRR)",
                    value: "Bs. ${service.ingresosRecurrentesMRR.toStringAsFixed(0)}",
                    subtitle: "Cobros recurrentes mensuales",
                    icon: Icons.monetization_on_rounded,
                    accentColor: AppColors.success,
                    changePercentage: "+8.5%",
                    isPositive: true,
                  ),
                  MetricCard(
                    title: "Empresas en Plan PRO",
                    value: service.totalPro.toString(),
                    subtitle: "${service.totalTrials} en periodo de prueba",
                    icon: Icons.bolt_rounded,
                    accentColor: AppColors.primaryPurple,
                    changePercentage: "+2 nuevas",
                    isPositive: true,
                  ),
                  MetricCard(
                    title: "Empresas Plan Free",
                    value: service.totalFree.toString(),
                    subtitle: "Límite 30 docs / mes",
                    icon: Icons.star_border_rounded,
                    accentColor: AppColors.neutral,
                    changePercentage: "Free Tier",
                    isPositive: true,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Fila de Gráficas y Actividad Reciente
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 950;

              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gráfico de Distribución de Planes
                  Expanded(
                    flex: isWide ? 5 : 0,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Distribución de Planes",
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                              Icon(Icons.pie_chart_outline_rounded, color: textSecondary, size: 20),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 180,
                            child: Row(
                              children: [
                                Expanded(
                                  child: PieChart(
                                    PieChartData(
                                      sectionsSpace: 3,
                                      centerSpaceRadius: 40,
                                      sections: [
                                        PieChartSectionData(
                                          color: AppColors.primaryGold,
                                          value: service.totalPro.toDouble() > 0 ? service.totalPro.toDouble() : 1,
                                          title: '${service.totalPro}',
                                          radius: 35,
                                          titleStyle: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        PieChartSectionData(
                                          color: AppColors.neutral,
                                          value: service.totalFree.toDouble() > 0 ? service.totalFree.toDouble() : 1,
                                          title: '${service.totalFree}',
                                          radius: 35,
                                          titleStyle: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (service.totalTrials > 0)
                                          PieChartSectionData(
                                            color: AppColors.info,
                                            value: service.totalTrials.toDouble(),
                                            title: '${service.totalTrials}',
                                            radius: 35,
                                            titleStyle: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLegendItem(AppColors.primaryGold, "Plan PRO (${service.totalPro})", textPrimary),
                                    const SizedBox(height: 8),
                                    _buildLegendItem(AppColors.neutral, "Plan Free (${service.totalFree})", textPrimary),
                                    const SizedBox(height: 8),
                                    _buildLegendItem(AppColors.info, "Trials Activos (${service.totalTrials})", textPrimary),
                                    const SizedBox(height: 8),
                                    _buildLegendItem(AppColors.danger, "Suspendidas (${service.totalSuspendidas})", textPrimary),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isWide) const SizedBox(width: 20) else const SizedBox(height: 20),

                  // Feed de Actividad Reciente (Audit Logs)
                  Expanded(
                    flex: isWide ? 6 : 0,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  "Actividad Reciente & Auditoría",
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: () => onNavigateTab(4), // Ir a Auditoría
                                child: Text(
                                  "Ver Todo",
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryGold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (service.logs.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Text(
                                "No hay actividad registrada aún.",
                                style: GoogleFonts.poppins(fontSize: 13, color: textSecondary),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: service.logs.take(4).length,
                              separatorBuilder: (_, _) => Divider(color: border, height: 16),
                              itemBuilder: (context, i) {
                                final log = service.logs[i];
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryPurple.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.history_rounded, size: 16, color: AppColors.primaryPurple),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            log.descripcion,
                                            style: GoogleFonts.poppins(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "${log.usuarioSuperadmin} • ${log.fecha.toString().split('.')[0]}",
                                            style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              color: textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Tabla Rápida: Últimas Empresas Registradas
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "Empresas Recientes",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => onNavigateTab(1),
                      icon: const Icon(Icons.list_alt_rounded, size: 16, color: AppColors.primaryGold),
                      label: Text(
                        "Ver Directorio Completo",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryGold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: service.empresas.take(4).length,
                  separatorBuilder: (_, _) => Divider(color: border, height: 16),
                  itemBuilder: (context, i) {
                    final e = service.empresas[i];
                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetalleEmpresaScreen(empresaId: e.id),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.primaryGold.withOpacity(0.15),
                              child: Text(
                                e.nombreComercial.isNotEmpty ? e.nombreComercial[0].toUpperCase() : 'N',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryGold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.nombreComercial,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                      color: textPrimary,
                                    ),
                                  ),
                                  Text(
                                    "${e.codigoEmpresa} • ${e.emailContacto}",
                                    style: GoogleFonts.poppins(
                                      fontSize: 11.5,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PlanBadge(planId: e.planId),
                            const SizedBox(width: 12),
                            StatusPill(estado: e.estado, diasRestantes: e.diasRestantes),
                            const SizedBox(width: 8),
                            Icon(Icons.chevron_right_rounded, size: 20, color: textSecondary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: textColor),
        ),
      ],
    );
  }
}
