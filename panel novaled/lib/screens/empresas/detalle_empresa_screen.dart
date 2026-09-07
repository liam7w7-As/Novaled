import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_colors.dart';
import '../../models/empresa_model.dart';
import '../../models/pago_model.dart';
import '../../models/plan_model.dart';
import '../../services/empresa_service.dart';
import '../../widgets/plan_badge.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/progress_quota_bar.dart';
import '../../widgets/confirmation_dialog.dart';
import 'editar_empresa_modal.dart';

class DetalleEmpresaScreen extends StatefulWidget {
  final String empresaId;

  const DetalleEmpresaScreen({super.key, required this.empresaId});

  @override
  State<DetalleEmpresaScreen> createState() => _DetalleEmpresaScreenState();
}

class _DetalleEmpresaScreenState extends State<DetalleEmpresaScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<EmpresaService>();
    final empresa = service.getEmpresaById(widget.empresaId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    if (empresa == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Empresa no encontrada")),
        body: const Center(child: Text("La empresa solicitada no existe o fue eliminada.")),
      );
    }

    final plan = service.getPlanById(empresa.planId);
    final pagosEmpresa = service.pagos.where((p) => p.empresaId == empresa.id).toList();
    final logsEmpresa = service.logs.where((l) => l.empresaId == empresa.id).toList();

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryGold.withOpacity(0.2),
                    child: Text(
                      empresa.nombreComercial.isNotEmpty ? empresa.nombreComercial[0].toUpperCase() : 'N',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: AppColors.primaryGold),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              empresa.nombreComercial,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            PlanBadge(planId: empresa.planId),
                            const SizedBox(width: 8),
                            StatusPill(estado: empresa.estado, diasRestantes: empresa.diasRestantes),
                          ],
                        ),
                        Text(
                          "Código: ${empresa.codigoEmpresa} • NIT: ${empresa.nitRut.isNotEmpty ? empresa.nitRut : 'S/N'} • ${empresa.emailContacto}",
                          style: GoogleFonts.poppins(fontSize: 12, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                  // Botones de acción rápida
                  OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => EditarEmpresaModal(empresa: empresa),
                      );
                    },
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text("Editar Datos"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      side: BorderSide(color: border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (empresa.estaSuspendido)
                    ElevatedButton.icon(
                      onPressed: () => service.reactivarEmpresa(empresa.id),
                      icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
                      label: const Text("Reactivar Acceso"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => ConfirmationDialog(
                            title: "Suspender Empresa",
                            message: "¿Deseas suspender temporalmente el acceso a ${empresa.nombreComercial}? La app se bloqueará para creación de nuevos documentos.",
                            confirmText: "Suspender",
                            confirmColor: AppColors.danger,
                            onConfirm: () => service.suspenderEmpresa(empresa.id),
                          ),
                        );
                      },
                      icon: const Icon(Icons.pause_circle_outline_rounded, size: 16, color: AppColors.danger),
                      label: Text("Suspender", style: GoogleFonts.poppins(color: AppColors.danger)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        side: const BorderSide(color: AppColors.danger),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              color: cardBg,
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primaryGold,
                indicatorWeight: 3,
                labelColor: AppColors.primaryGold,
                unselectedLabelColor: textSecondary,
                labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(icon: Icon(Icons.info_outline_rounded, size: 18), text: "Información"),
                  Tab(icon: Icon(Icons.workspace_premium_rounded, size: 18), text: "Plan & Suscripción"),
                  Tab(icon: Icon(Icons.bar_chart_rounded, size: 18), text: "Métricas"),
                  Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: "Pagos"),
                  Tab(icon: Icon(Icons.history_rounded, size: 18), text: "Auditoría"),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTabInformacion(empresa, isDark, textPrimary, textSecondary, cardBg, border),
                  _buildTabPlanSuscripcion(empresa, plan, service, isDark, textPrimary, textSecondary, cardBg, border),
                  _buildTabMetricas(empresa, plan, isDark, textPrimary, textSecondary, cardBg, border),
                  _buildTabPagos(pagosEmpresa, empresa, service, isDark, textPrimary, textSecondary, cardBg, border),
                  _buildTabAuditoria(logsEmpresa, isDark, textPrimary, textSecondary, cardBg, border),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1. PESTAÑA INFORMACIÓN GENERAL
  Widget _buildTabInformacion(
    EmpresaModel e,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color cardBg,
    Color border,
  ) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Datos Corporativos", style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                    const SizedBox(height: 16),
                    _buildInfoRow("Nombre Comercial", e.nombreComercial, textPrimary, textSecondary),
                    _buildInfoRow("Razón Social", e.razonSocial.isNotEmpty ? e.razonSocial : "No especificada", textPrimary, textSecondary),
                    _buildInfoRow("NIT / CI / RUT", e.nitRut.isNotEmpty ? e.nitRut : "Sin documento fiscal", textPrimary, textSecondary),
                    _buildInfoRow("Ciudad y País", "${e.ciudad}, ${e.pais}", textPrimary, textSecondary),
                    _buildInfoRow("Dirección", e.direccionPrincipal.isNotEmpty ? e.direccionPrincipal : "Sin dirección", textPrimary, textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Contacto & Configuración", style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
                    const SizedBox(height: 16),
                    _buildInfoRow("Email Principal", e.emailContacto, textPrimary, textSecondary),
                    _buildInfoRow("Teléfono / Móvil", e.telefono.isNotEmpty ? e.telefono : "No registrado", textPrimary, textSecondary),
                    _buildInfoRow("Moneda por Defecto", e.monedaSimbolo, textPrimary, textSecondary),
                    _buildInfoRow("Fecha Registro", e.fechaRegistro.toString().split(' ')[0], textPrimary, textSecondary),
                    _buildInfoRow("Notas Admin", e.notasAdmin.isNotEmpty ? e.notasAdmin : "Sin observaciones", textPrimary, textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 2. PESTAÑA PLAN & SUSCRIPCIÓN
  Widget _buildTabPlanSuscripcion(
    EmpresaModel e,
    dynamic plan,
    EmpresaService service,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color cardBg,
    Color border,
  ) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Plan Activo y Estado de Suscripción", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
                      Text("Gestiona los límites, prórrogas y upgrades de la empresa", style: GoogleFonts.poppins(fontSize: 12, color: textSecondary)),
                    ],
                  ),
                  PlanBadge(planId: e.planId, isLarge: true),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildStatTile(
                      "Fecha Inicio Plan",
                      e.fechaInicioPlan.toString().split(' ')[0],
                      Icons.calendar_today_rounded,
                      AppColors.info,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatTile(
                      "Fecha Vencimiento",
                      e.fechaVencimiento != null ? e.fechaVencimiento.toString().split(' ')[0] : "Ilimitado / Free",
                      Icons.event_busy_rounded,
                      e.estaPorVencer ? AppColors.warning : AppColors.primaryGold,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatTile(
                      "Días Restantes",
                      e.fechaVencimiento != null ? "${e.diasRestantes} días" : "N/A",
                      Icons.timelapse_rounded,
                      e.diasRestantes < 5 ? AppColors.danger : AppColors.success,
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: border),
              const SizedBox(height: 16),

              Text("Acciones Rápidas de Suscripción", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      _mostrarModalCambioPlan(e, service);
                    },
                    icon: const Icon(Icons.upgrade_rounded, size: 18),
                    label: const Text("Cambiar / Renovar Plan"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGold,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      service.extenderProrroga(e.id, 7);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Prórroga de +7 días aplicada.")));
                    },
                    icon: const Icon(Icons.more_time_rounded, size: 18),
                    label: const Text("+7 Días Prórroga"),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      service.extenderProrroga(e.id, 15);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Prórroga de +15 días aplicada.")));
                    },
                    icon: const Icon(Icons.more_time_rounded, size: 18),
                    label: const Text("+15 Días Prórroga"),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      service.extenderProrroga(e.id, 30);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Prórroga de +30 días aplicada.")));
                    },
                    icon: const Icon(Icons.more_time_rounded, size: 18),
                    label: const Text("+30 Días Prórroga"),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 3. PESTAÑA MÉTRICAS
  Widget _buildTabMetricas(
    EmpresaModel e,
    dynamic plan,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color cardBg,
    Color border,
  ) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Cotizaciones (En Vivo)", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                    const SizedBox(height: 8),
                    Text(
                      "${e.totalCotizaciones} / ${plan?.esIlimitadoCotizaciones == true ? 'Ilimitadas' : (plan?.limiteCotizaciones ?? 5)}",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primaryPurple),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Notas de Venta (POS)", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                    const SizedBox(height: 8),
                    Text(
                      "${e.totalNotasVenta} / ${plan?.esIlimitadoNotasVenta == true ? 'Ilimitadas' : (plan?.limiteNotasVenta ?? 5)}",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.success),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Notas de Entrega", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                    const SizedBox(height: 8),
                    Text(
                      "${e.totalNotasEntrega} / ${plan?.esIlimitadoNotasEntrega == true ? 'Ilimitadas' : (plan?.limiteNotasEntrega ?? 5)}",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primaryGold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Escaneos Mágicos", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                    const SizedBox(height: 8),
                    Text(
                      "${e.totalEscaneos} / ${plan?.esIlimitadoEscaneos == true ? 'Ilimitados' : (plan?.limiteEscaneosMagicos ?? 5)}",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.indigoAccent),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Usuarios / Vendedores", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                    const SizedBox(height: 8),
                    Text(
                      "${e.usuariosActivos} / ${plan?.esIlimitadoUsuarios == true ? 'Ilimitados' : (plan?.limiteUsuarios ?? 2)}",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.blueAccent),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Artículos en Catálogo", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                    const SizedBox(height: 8),
                    Text("${e.articulosCreados} producto(s)", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 4. PESTAÑA HISTORIAL DE PAGOS
  Widget _buildTabPagos(
    List<PagoModel> pagos,
    EmpresaModel e,
    EmpresaService service,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color cardBg,
    Color border,
  ) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Historial de Pagos y Comprobantes", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
            ElevatedButton.icon(
              onPressed: () => _mostrarModalRegistrarPago(e, service),
              icon: const Icon(Icons.add_card_rounded, size: 18, color: Colors.white),
              label: const Text("Registrar Nuevo Pago"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (pagos.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
            child: Center(
              child: Text("No existen comprobantes o pagos registrados para esta empresa.", style: GoogleFonts.poppins(color: textSecondary)),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pagos.length,
              separatorBuilder: (_, _) => Divider(color: border, height: 1),
              itemBuilder: (context, i) {
                final p = pagos[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.success.withOpacity(0.15),
                    child: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success),
                  ),
                  title: Text("${p.moneda} ${p.monto.toStringAsFixed(2)} • ${p.planNombre}", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: textPrimary)),
                  subtitle: Text("Ref: ${p.referenciaTransaccion} • ${p.metodoPago} • ${p.fechaPago.toString().split(' ')[0]}", style: GoogleFonts.poppins(fontSize: 12, color: textSecondary)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.success.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                    child: Text("Pagado (${p.mesesPagados}m)", style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // 5. PESTAÑA AUDITORÍA
  Widget _buildTabAuditoria(
    List logs,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color cardBg,
    Color border,
  ) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text("Logs de Actividad de la Empresa", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border)),
          child: logs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Center(child: Text("Sin eventos de auditoría registrados.", style: GoogleFonts.poppins(color: textSecondary))),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => Divider(color: border, height: 1),
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    return ListTile(
                      leading: const Icon(Icons.history_toggle_off_rounded, color: AppColors.primaryPurple),
                      title: Text(log.descripcion, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary)),
                      subtitle: Text("${log.usuarioSuperadmin} • ${log.fecha.toString().split('.')[0]}", style: GoogleFonts.poppins(fontSize: 11.5, color: textSecondary)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, Color textPrimary, Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 13, color: textSecondary)),
          Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
        ],
      ),
    );
  }

  Widget _buildStatTile(String title, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  void _mostrarModalCambioPlan(EmpresaModel e, EmpresaService service) {
    String nuevoPlan = e.planId;
    int meses = 1;
    String metodo = 'Transferencia Bancaria';
    final refCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final planSel = service.getPlanById(nuevoPlan) ?? PlanModel.planFreeDefault;

          Widget buildCheckItem(String text, bool active) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.5),
              child: Row(
                children: [
                  Icon(
                    active ? Icons.check_rounded : Icons.close_rounded,
                    color: active ? const Color(0xFF6C5CE7) : Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: active
                            ? (isDark ? Colors.white : const Color(0xFF1E293B))
                            : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.upgrade_rounded, color: Color(0xFF6C5CE7), size: 26),
                const SizedBox(width: 8),
                Text(
                  "Cambiar / Asignar Plan",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Empresa: ${e.nombreComercial}",
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: service.planes.any((p) => p.id == nuevoPlan) ? nuevoPlan : 'free',
                      decoration: InputDecoration(
                        labelText: "Selecciona el Plan",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      ),
                      items: service.planes.map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          "${p.nombre} (${p.moneda} ${p.precio.toStringAsFixed(0)}/mes) - ${p.esIlimitadoDocs ? 'Ilimitado' : '${p.limiteCotizaciones} docs'}",
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      )).toList(),
                      onChanged: (v) => setModalState(() => nuevoPlan = v ?? nuevoPlan),
                    ),
                    const SizedBox(height: 14),

                    // Tarjeta Visual de Características del Plan Seleccionado
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F6FB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF6C5CE7).withOpacity(0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Beneficios Plan ${planSel.nombre}:",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF6C5CE7),
                                ),
                              ),
                              Text(
                                planSel.precio == 0 ? "GRATIS" : "${planSel.moneda} ${planSel.precio.toStringAsFixed(0)} / mes",
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          buildCheckItem(
                            planSel.esIlimitadoCotizaciones ? "Cotizaciones ilimitadas" : "${planSel.limiteCotizaciones} cotizaciones máx.",
                            true,
                          ),
                          buildCheckItem(
                            planSel.esIlimitadoNotasVenta ? "Notas de venta ilimitadas" : "${planSel.limiteNotasVenta} notas de venta máx.",
                            true,
                          ),
                          buildCheckItem(
                            planSel.esIlimitadoNotasEntrega ? "Notas de entrega ilimitadas" : "${planSel.limiteNotasEntrega} notas de entrega máx.",
                            true,
                          ),
                          buildCheckItem(
                            planSel.esIlimitadoEscaneos
                                ? "Escaneos mágicos ilimitados"
                                : "${planSel.limiteEscaneosMagicos} escaneos mágicos al mes",
                            true,
                          ),
                          buildCheckItem("Información de empresa y logo", planSel.permiteInfoLogo),
                          buildCheckItem("Modo edición desbloqueado", planSel.permiteModoEdicion),
                          buildCheckItem("Paleta de colores", planSel.permitePaletaColores),
                          buildCheckItem(
                            planSel.esIlimitadoUsuarios ? "Usuarios ilimitados" : "Hasta ${planSel.limiteUsuarios} usuarios",
                            true,
                          ),
                        ],
                      ),
                    ),

                    if (nuevoPlan != 'free') ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        value: meses,
                        decoration: InputDecoration(
                          labelText: "Meses a contratar",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text("1 Mes")),
                          DropdownMenuItem(value: 3, child: Text("3 Meses")),
                          DropdownMenuItem(value: 6, child: Text("6 Meses")),
                          DropdownMenuItem(value: 12, child: Text("12 Meses")),
                        ],
                        onChanged: (v) => setModalState(() => meses = v ?? 1),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: refCtrl,
                        decoration: InputDecoration(
                          labelText: "Referencia de Pago (opcional)",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  "Cancelar",
                  style: GoogleFonts.poppins(color: Colors.grey, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await service.cambiarPlan(
                    empresaId: e.id,
                    nuevoPlanId: nuevoPlan,
                    meses: meses,
                    metodoPago: metodo,
                    referenciaPago: refCtrl.text.trim(),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Plan actualizado exitosamente a ${planSel.nombre}"),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  }
                },
                child: Text(
                  "Aplicar Plan",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _mostrarModalRegistrarPago(EmpresaModel e, EmpresaService service) {
    final montoCtrl = TextEditingController(text: "150");
    final refCtrl = TextEditingController();
    int meses = 1;
    String metodo = 'Transferencia Bancaria';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text("Registrar Pago para ${e.nombreComercial}"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: montoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Monto (Bs.)"),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: meses,
                  decoration: const InputDecoration(labelText: "Meses pagados"),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text("1 Mes")),
                    DropdownMenuItem(value: 3, child: Text("3 Meses")),
                    DropdownMenuItem(value: 6, child: Text("6 Meses")),
                    DropdownMenuItem(value: 12, child: Text("12 Meses")),
                  ],
                  onChanged: (v) => setModalState(() => meses = v ?? 1),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(labelText: "Referencia de Pago"),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: () {
                  final monto = double.tryParse(montoCtrl.text.trim()) ?? 150.0;
                  final now = DateTime.now();
                  final nuevoPago = PagoModel(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    empresaId: e.id,
                    empresaNombre: e.nombreComercial,
                    monto: monto,
                    moneda: e.monedaSimbolo,
                    planId: e.planId,
                    planNombre: e.planId == 'pro_anual' ? 'Plan PRO Anual' : 'Plan PRO Mensual',
                    mesesPagados: meses,
                    metodoPago: metodo,
                    referenciaTransaccion: refCtrl.text.trim().isNotEmpty ? refCtrl.text.trim() : 'PAGO-MANUAL',
                    fechaPago: now,
                    fechaCoberturaDesde: now,
                    fechaCoberturaHasta: now.add(Duration(days: 30 * meses)),
                    registradoPor: 'SuperAdmin Novaled',
                  );
                  Navigator.pop(ctx);
                  service.registrarPago(nuevoPago);
                },
                child: const Text("Guardar Pago"),
              ),
            ],
          );
        },
      ),
    );
  }
}
