import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/empresa_model.dart';
import '../../services/empresa_service.dart';
import '../../widgets/plan_badge.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/progress_quota_bar.dart';
import '../../widgets/confirmation_dialog.dart';
import 'crear_empresa_modal.dart';
import 'editar_empresa_modal.dart';
import 'detalle_empresa_screen.dart';

class ListaEmpresasScreen extends StatelessWidget {
  const ListaEmpresasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<EmpresaService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    final empresas = service.empresasFiltradas;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header y Botón Crear
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Directorio de Empresas",
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  Text(
                    "${service.empresas.length} empresas registradas en total (${service.totalEmpresasActivas} activas)",
                    style: GoogleFonts.poppins(fontSize: 13, color: textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const CrearEmpresaModal(),
                  );
                },
                icon: const Icon(Icons.add_business_rounded, size: 18, color: Colors.black87),
                label: Text(
                  "Nueva Empresa",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.black87),
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
          const SizedBox(height: 20),

          // Barra de Búsqueda y Filtros de Estado
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: Column(
              children: [
                // Buscador
                TextField(
                  onChanged: (v) => service.setFiltroTexto(v),
                  style: GoogleFonts.poppins(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: "Buscar por nombre, código, email, NIT o ciudad...",
                    hintStyle: GoogleFonts.poppins(fontSize: 13, color: textSecondary),
                    prefixIcon: Icon(Icons.search_rounded, color: textSecondary, size: 20),
                    filled: true,
                    fillColor: isDark ? AppColors.cardDark : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGold)),
                  ),
                ),
                const SizedBox(height: 14),

                // Pestañas de Filtro Rápido
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip("Todos (${service.empresas.where((e) => !e.estaEliminado).length})", 'todos', service, isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip("Plan PRO (${service.totalPro})", 'pro', service, isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip("Plan Free (${service.totalFree})", 'free', service, isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip("Trials Activos (${service.totalTrials})", 'trial', service, isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip("Por Vencer (${service.totalPorVencer})", 'por_vencer', service, isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip("Suspendidas (${service.totalSuspendidas})", 'suspendido', service, isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip("🗑️ Papelera 30d (${service.totalEliminadas})", 'eliminado', service, isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Tabla de Empresas
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
            ),
            child: empresas.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(48.0),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: textSecondary.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text(
                            "No se encontraron empresas con los filtros aplicados",
                            style: GoogleFonts.poppins(fontSize: 14, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: empresas.length,
                    separatorBuilder: (_, _) => Divider(color: border, height: 1),
                    itemBuilder: (context, i) {
                      final e = empresas[i];
                      final plan = service.getPlanById(e.planId);

                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DetalleEmpresaScreen(empresaId: e.id),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              // Avatar & Nombre
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.primaryGold.withOpacity(0.15),
                                child: Text(
                                  e.nombreComercial.isNotEmpty ? e.nombreComercial[0].toUpperCase() : 'N',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: AppColors.primaryGold),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.nombreComercial,
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13.5, color: textPrimary),
                                    ),
                                    Text(
                                      "${e.codigoEmpresa} • ${e.emailContacto} • ${e.ciudad}",
                                      style: GoogleFonts.poppins(fontSize: 11.5, color: textSecondary),
                                    ),
                                    if (e.estaEliminado)
                                      Container(
                                        margin: const EdgeInsets.only(top: 5),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.timer_outlined, color: Colors.redAccent, size: 13),
                                            const SizedBox(width: 4),
                                            Text(
                                              "⏳ Papelera: se borra definitivamente en ${e.diasRestantesPapelera} días • ACCESO BLOQUEADO",
                                              style: GoogleFonts.poppins(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Plan
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: PlanBadge(planId: e.planId),
                                ),
                              ),

                              // Estado
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: StatusPill(estado: e.estado, diasRestantes: e.diasRestantes),
                                ),
                              ),

                              // Consumo Docs Mes
                              Expanded(
                                flex: 3,
                                child: ProgressQuotaBar(
                                  actual: e.documentosMesActual,
                                  limite: plan?.limiteDocumentosMes ?? 30,
                                ),
                              ),

                              // Fechas
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      e.fechaVencimiento != null ? "Vence: ${e.fechaVencimiento.toString().split(' ')[0]}" : "Sin vencimiento",
                                      style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w500, color: textPrimary),
                                    ),
                                    Text(
                                      "Reg: ${e.fechaRegistro.toString().split(' ')[0]}",
                                      style: GoogleFonts.poppins(fontSize: 11, color: textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Menú de Acciones (3 puntos)
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert_rounded, color: textSecondary, size: 20),
                                color: cardBg,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border)),
                                onSelected: (val) => _handleAction(val, e, service, context),
                                itemBuilder: (ctx) => e.estaEliminado
                                    ? [
                                        const PopupMenuItem(
                                          value: 'restaurar',
                                          child: Row(children: [Icon(Icons.restore_from_trash_rounded, size: 18, color: AppColors.success), SizedBox(width: 8), Text("Restaurar Acceso", style: TextStyle(color: AppColors.success))]),
                                        ),
                                        const PopupMenuItem(
                                          value: 'purga_definitiva',
                                          child: Row(children: [Icon(Icons.delete_forever_rounded, size: 18, color: AppColors.danger), SizedBox(width: 8), Text("Eliminar Definitivamente", style: TextStyle(color: AppColors.danger))]),
                                        ),
                                      ]
                                    : [
                                        const PopupMenuItem(
                                          value: 'ver_perfil',
                                          child: Row(children: [Icon(Icons.remove_red_eye_outlined, size: 18), SizedBox(width: 8), Text("Ver Perfil 360°")]),
                                        ),
                                        const PopupMenuItem(
                                          value: 'editar',
                                          child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text("Editar Datos")]),
                                        ),
                                        const PopupMenuItem(
                                          value: 'cambiar_password',
                                          child: Row(children: [Icon(Icons.key_rounded, size: 18, color: AppColors.primaryPurple), SizedBox(width: 8), Text("Cambiar Contraseña")]),
                                        ),
                                        const PopupMenuItem(
                                          value: 'extender_7',
                                          child: Row(children: [Icon(Icons.more_time_rounded, size: 18, color: AppColors.primaryGold), SizedBox(width: 8), Text("+7 Días Prórroga")]),
                                        ),
                                        const PopupMenuItem(
                                          value: 'extender_30',
                                          child: Row(children: [Icon(Icons.add_circle_outline_rounded, size: 18, color: AppColors.success), SizedBox(width: 8), Text("+30 Días Prórroga")]),
                                        ),
                                        if (e.estaSuspendido)
                                          const PopupMenuItem(
                                            value: 'reactivar',
                                            child: Row(children: [Icon(Icons.play_arrow_outlined, size: 18, color: AppColors.success), SizedBox(width: 8), Text("Reactivar Empresa")]),
                                          )
                                        else
                                          const PopupMenuItem(
                                            value: 'suspender',
                                            child: Row(children: [Icon(Icons.pause_circle_outline_rounded, size: 18, color: AppColors.warning), SizedBox(width: 8), Text("Suspender")]),
                                          ),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                          value: 'eliminar',
                                          child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger), SizedBox(width: 8), Text("Enviar a Papelera (30d)", style: TextStyle(color: AppColors.danger))]),
                                        ),
                                      ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, EmpresaService service, bool isDark) {
    final isSelected = service.filtroEstado == value;
    return InkWell(
      onTap: () => service.setFiltroEstado(value),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryGold
              : (isDark ? AppColors.cardDark : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.black87 : (isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary),
          ),
        ),
      ),
    );
  }

  void _handleAction(String action, EmpresaModel e, EmpresaService service, BuildContext context) {
    switch (action) {
      case 'ver_perfil':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetalleEmpresaScreen(empresaId: e.id),
          ),
        );
        break;
      case 'editar':
        showDialog(
          context: context,
          builder: (_) => EditarEmpresaModal(empresa: e),
        );
        break;
      case 'cambiar_password':
        _mostrarDialogoCambiarPassword(context, e, service);
        break;
      case 'extender_7':
        service.extenderProrroga(e.id, 7);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Prórroga de +7 días aplicada.")));
        break;
      case 'extender_30':
        service.extenderProrroga(e.id, 30);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Prórroga de +30 días aplicada.")));
        break;
      case 'suspender':
        service.suspenderEmpresa(e.id, motivo: "Suspensión administrativa");
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Empresa suspendida.")));
        break;
      case 'reactivar':
        service.reactivarEmpresa(e.id);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Empresa reactivada.")));
        break;
      case 'restaurar':
        service.restaurarEmpresa(e.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ \"${e.nombreComercial}\" restaurada y acceso reactivado en MySQL."),
            backgroundColor: Colors.green,
          ),
        );
        break;
      case 'eliminar':
        showDialog(
          context: context,
          builder: (_) => ConfirmationDialog(
            title: "Enviar a Papelera (30 días)",
            message: "¿Deseas enviar \"${e.nombreComercial}\" a la papelera?\n\n• Se bloqueará inmediatamente el acceso al sistema a todos sus usuarios.\n• Permanecerá en la papelera durante 30 días para su eliminación definitiva.",
            confirmText: "Enviar a Papelera (Bloquear)",
            confirmColor: AppColors.danger,
            onConfirm: () => service.eliminarEmpresa(e.id, softDelete: true),
          ),
        );
        break;
      case 'purga_definitiva':
        showDialog(
          context: context,
          builder: (_) => ConfirmationDialog(
            title: "⚠️ ¿Eliminar Definitivamente?",
            message: "Esta acción NO se puede deshacer.\n\nSe borrarán de forma irreversible todas las cotizaciones, ventas, notas de entrega, artículos y usuarios de \"${e.nombreComercial}\" del servidor MySQL.",
            confirmText: "Purgar Definitivamente",
            confirmColor: AppColors.danger,
            onConfirm: () => service.eliminarEmpresa(e.id, softDelete: false),
          ),
        );
        break;
    }
  }

  void _mostrarDialogoCambiarPassword(BuildContext context, EmpresaModel e, EmpresaService service) {
    final passCtrl = TextEditingController();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final bg = isDark ? AppColors.surfaceDark : Colors.white;
          final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
          final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
          final border = isDark ? AppColors.borderDark : AppColors.borderLight;

          return AlertDialog(
            backgroundColor: bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.key_rounded, color: AppColors.primaryPurple, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Cambiar Contraseña",
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                      ),
                      Text(
                        e.nombreComercial,
                        style: GoogleFonts.poppins(fontSize: 12, color: textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Correo / Usuario de Acceso: ${e.emailContacto}",
                  style: GoogleFonts.poppins(fontSize: 12, color: textSecondary),
                ),
                const SizedBox(height: 14),
                Text(
                  "Nueva Contraseña",
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  style: GoogleFonts.poppins(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: "Escribe la nueva contraseña",
                    hintStyle: GoogleFonts.poppins(fontSize: 12, color: textSecondary.withOpacity(0.6)),
                    filled: true,
                    fillColor: isDark ? AppColors.cardDark : const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryPurple)),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18, color: textSecondary),
                          onPressed: () => setDlgState(() => obscure = !obscure),
                        ),
                        IconButton(
                          icon: const Icon(Icons.auto_awesome, size: 18, color: AppColors.primaryGold),
                          tooltip: "Generar clave",
                          onPressed: () {
                            final chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
                            final rand = List.generate(8, (i) => chars[(DateTime.now().microsecondsSinceEpoch + i * 5) % chars.length]).join();
                            setDlgState(() => passCtrl.text = "Nova@$rand");
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Cancelar", style: GoogleFonts.poppins(color: textSecondary)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newPass = passCtrl.text.trim();
                  if (newPass.length < 4) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("La contraseña debe tener al menos 4 caracteres"), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  final ok = await service.cambiarPasswordEmpresa(
                    empresaId: e.id,
                    empresaNombre: e.nombreComercial,
                    emailContacto: e.emailContacto,
                    nuevaPassword: newPass,
                  );
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("✅ Contraseña actualizada en el servidor para ${e.nombreComercial}"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("⚠️ Error actualizando contraseña en el servidor"), backgroundColor: Colors.red),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text("Guardar en Nube", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }
}
