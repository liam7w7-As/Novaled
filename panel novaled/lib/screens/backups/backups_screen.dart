import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../core/theme/app_colors.dart';
import '../../models/backup_model.dart';
import '../../services/backup_service.dart';

class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filtroTipo = 'Todos';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final tableHeaderBg = isDark ? const Color(0xFF1E222B) : const Color(0xFFF8FAFC);

    final service = context.watch<BackupService>();

    final backupsFiltrados = service.backups.where((b) {
      final query = _searchCtrl.text.toLowerCase().trim();
      final matchQuery = query.isEmpty ||
          b.nombreArchivo.toLowerCase().contains(query) ||
          b.id.toLowerCase().contains(query) ||
          b.tipo.toLowerCase().contains(query);

      if (!matchQuery) return false;

      if (_filtroTipo == 'Todos') return true;
      if (_filtroTipo == 'SQLite' && b.nombreArchivo.endsWith('.db')) return true;
      if (_filtroTipo == 'JSON' && b.nombreArchivo.endsWith('.json')) return true;
      if (_filtroTipo == 'CSV' && b.nombreArchivo.endsWith('.csv')) return true;
      if (_filtroTipo == 'SQL' && b.nombreArchivo.endsWith('.sql')) return true;
      return true;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la Sección
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Copias de Seguridad & Backups",
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Respaldos históricos de bases de datos, catálogos e historiales con programación automática",
                    style: GoogleFonts.poppins(fontSize: 13, color: textSecondary),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                children: [
                  // Botón Abrir Carpeta
                  OutlinedButton.icon(
                    onPressed: () => service.abrirCarpetaBackups(),
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: Text("Abrir Carpeta", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      side: BorderSide(color: border),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  // Botón Exportar a Excel
                  OutlinedButton.icon(
                    onPressed: () async {
                      final path = await service.exportarTablaAExcel();
                      if (mounted && path.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("✅ Tabla de backups exportada a Excel (reporte_historial_backups.csv)"),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.table_chart_rounded, size: 18, color: AppColors.success),
                    label: Text("Exportar a Excel", style: GoogleFonts.poppins(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: BorderSide(color: AppColors.success.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  // Botón Programar Horario
                  OutlinedButton.icon(
                    onPressed: () => _mostrarDialogoProgramacion(context, service),
                    icon: const Icon(Icons.alarm_rounded, size: 18, color: AppColors.primaryPurple),
                    label: Text("Horario Automático", style: GoogleFonts.poppins(color: AppColors.primaryPurple, fontWeight: FontWeight.w600, fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryPurple,
                      side: BorderSide(color: AppColors.primaryPurple.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  // Botón Hacer Backup Ahora
                  ElevatedButton.icon(
                    onPressed: service.isCreatingBackup
                        ? null
                        : () async {
                            final bkp = await service.crearBackupManual();
                            if (mounted && bkp != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("✅ Backup generado con éxito: ${bkp.nombreArchivo} (${bkp.tamanoFormateado})"),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                    icon: service.isCreatingBackup
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                          )
                        : const Icon(Icons.flash_on_rounded, size: 18, color: Colors.black87),
                    label: Text(
                      service.isCreatingBackup ? "Extrayendo en caliente..." : "Hacer Backup Ahora",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGold,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Tarjetas de Métricas Rápidas (4 KPIs)
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: "Total Copias Guardadas",
                  value: "${service.backups.length} Archivos",
                  icon: Icons.inventory_2_outlined,
                  color: AppColors.primaryPurple,
                  cardBg: cardBg,
                  border: border,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  title: "Espacio en Disco",
                  value: service.totalTamanoFormateado,
                  icon: Icons.storage_rounded,
                  color: AppColors.primaryGold,
                  cardBg: cardBg,
                  border: border,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  title: "Hora Backup Automático",
                  value: service.autoBackupActivo
                      ? "${service.horaProgramada.hour.toString().padLeft(2, '0')}:${service.horaProgramada.minute.toString().padLeft(2, '0')} (${service.frecuencia.split(' ')[0]})"
                      : "Desactivado",
                  icon: Icons.schedule_rounded,
                  color: service.autoBackupActivo ? AppColors.success : AppColors.danger,
                  cardBg: cardBg,
                  border: border,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  title: "Último Respaldo",
                  value: service.backups.isNotEmpty ? service.backups.first.fechaFormateada.split(' ')[0] : "Sin registros",
                  icon: Icons.verified_user_outlined,
                  color: AppColors.info,
                  cardBg: cardBg,
                  border: border,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Buscador y Filtros
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.poppins(fontSize: 13, color: textPrimary),
                    decoration: InputDecoration(
                      hintText: "Buscar por nombre de archivo, ID o tipo...",
                      hintStyle: GoogleFonts.poppins(fontSize: 13, color: textSecondary.withOpacity(0.6)),
                      prefixIcon: Icon(Icons.search_rounded, color: textSecondary, size: 20),
                      filled: true,
                      fillColor: isDark ? AppColors.cardDark : const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                _buildFilterTab("Todos", cardBg, border, textPrimary, textSecondary),
                const SizedBox(width: 8),
                _buildFilterTab("SQLite", cardBg, border, textPrimary, textSecondary),
                const SizedBox(width: 8),
                _buildFilterTab("JSON", cardBg, border, textPrimary, textSecondary),
                const SizedBox(width: 8),
                _buildFilterTab("CSV", cardBg, border, textPrimary, textSecondary),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tabla tipo Excel
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    // Header de la Tabla
                    Container(
                      color: tableHeaderBg,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          _buildHeaderCell("ID CÓDIGO", flex: 2, textSecondary: textSecondary),
                          _buildHeaderCell("NOMBRE DEL ARCHIVO", flex: 4, textSecondary: textSecondary),
                          _buildHeaderCell("TIPO", flex: 3, textSecondary: textSecondary),
                          _buildHeaderCell("PESO / TAMAÑO", flex: 2, textSecondary: textSecondary),
                          _buildHeaderCell("FECHA Y HORA", flex: 3, textSecondary: textSecondary),
                          _buildHeaderCell("ESTADO", flex: 2, textSecondary: textSecondary),
                          _buildHeaderCell("ACCIONES", flex: 3, alignment: Alignment.centerRight, textSecondary: textSecondary),
                        ],
                      ),
                    ),
                    Divider(color: border, height: 1),

                    // Filas de la Tabla
                    Expanded(
                      child: backupsFiltrados.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.folder_off_outlined, size: 48, color: textSecondary.withOpacity(0.5)),
                                  const SizedBox(height: 12),
                                  Text(
                                    "No se encontraron copias de seguridad",
                                    style: GoogleFonts.poppins(fontSize: 14, color: textSecondary),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: backupsFiltrados.length,
                              separatorBuilder: (_, __) => Divider(color: border.withOpacity(0.6), height: 1),
                              itemBuilder: (context, index) {
                                final b = backupsFiltrados[index];
                                final isDb = b.nombreArchivo.endsWith('.db');

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                                  color: index % 2 == 0 ? Colors.transparent : (isDark ? Colors.white.withOpacity(0.015) : const Color(0xFFFBFBFD)),
                                  child: Row(
                                    children: [
                                      // ID
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          b.id,
                                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryGold),
                                        ),
                                      ),

                                      // Nombre Archivo con icono
                                      Expanded(
                                        flex: 4,
                                        child: Row(
                                          children: [
                                            Icon(_getFileIcon(b.nombreArchivo), size: 18, color: _getFileColor(b.nombreArchivo)),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                b.nombreArchivo,
                                                style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w500, color: textPrimary),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Tipo
                                      Expanded(
                                        flex: 3,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _getFileColor(b.nombreArchivo).withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            b.tipo,
                                            style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: _getFileColor(b.nombreArchivo)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                      // Tamaño
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          b.tamanoFormateado,
                                          style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: textPrimary),
                                        ),
                                      ),

                                      // Fecha y Hora
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          b.fechaFormateada,
                                          style: GoogleFonts.poppins(fontSize: 12, color: textSecondary),
                                        ),
                                      ),

                                      // Estado
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: const BoxDecoration(
                                                color: AppColors.success,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              b.estado,
                                              style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.success),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Acciones
                                      Expanded(
                                        flex: 3,
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Botón Restablecer (Solo para .db)
                                              if (isDb)
                                                ElevatedButton.icon(
                                                  onPressed: () => _mostrarDialogoConfirmarRestablecer(context, b, service),
                                                  icon: const Icon(Icons.restore_rounded, size: 14, color: Colors.white),
                                                  label: Text(
                                                    "Restablecer",
                                                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: AppColors.danger,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    minimumSize: Size.zero,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    elevation: 0,
                                                  ),
                                                ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                icon: const Icon(Icons.folder_open_outlined, size: 18),
                                                tooltip: "Abrir carpeta en Explorador",
                                                onPressed: () => service.abrirCarpetaBackups(),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.copy_rounded, size: 18),
                                                tooltip: "Copiar ruta",
                                                onPressed: () {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text("Ruta copiada: ${b.rutaCompleta}")),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String title, {required int flex, Alignment alignment = Alignment.centerLeft, required Color textSecondary}) {
    return Expanded(
      flex: flex,
      child: Align(
        alignment: alignment,
        child: Text(
          title,
          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: textSecondary),
        ),
      ),
    );
  }

  Widget _buildFilterTab(String label, Color cardBg, Color border, Color textPrimary, Color textSecondary) {
    final isSelected = _filtroTipo == label;
    return InkWell(
      onTap: () => setState(() => _filtroTipo = label),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGold : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? AppColors.primaryGold : border),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.black87 : textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color cardBg,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.poppins(fontSize: 11.5, color: textSecondary)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String filename) {
    if (filename.endsWith('.db')) return Icons.storage_rounded;
    if (filename.endsWith('.json')) return Icons.data_object_rounded;
    if (filename.endsWith('.csv')) return Icons.table_chart_rounded;
    if (filename.endsWith('.sql')) return Icons.code_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor(String filename) {
    if (filename.endsWith('.db')) return AppColors.primaryPurple;
    if (filename.endsWith('.json')) return AppColors.primaryGold;
    if (filename.endsWith('.csv')) return AppColors.success;
    if (filename.endsWith('.sql')) return AppColors.info;
    return Colors.blueGrey;
  }

  void _mostrarDialogoConfirmarRestablecer(BuildContext context, BackupModel b, BackupService service) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? AppColors.surfaceDark : Colors.white;
        final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
        final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
        final border = isDark ? AppColors.borderDark : AppColors.borderLight;

        return AlertDialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppColors.danger, width: 1.5)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "ACCION DE ÚLTIMO RECURSO",
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.danger, letterSpacing: 0.8),
                    ),
                    Text(
                      "Restablecer Sistema a Punto de Respaldo",
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                  ),
                  child: Text(
                    "⚠️ ATENCIÓN: Esta acción reemplazará la base de datos local y sincronizará la copia con la Nube y el dispositivo móvil. Utilícese únicamente en caso de emergencia si ocurrió una falla en el sistema.",
                    style: GoogleFonts.poppins(fontSize: 12.5, height: 1.4, color: isDark ? Colors.red[200] : Colors.red[900]),
                  ),
                ),
                const SizedBox(height: 16),
                Text("Detalles de la Copia Seleccionada:", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.cardDark : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Archivo:", style: GoogleFonts.poppins(fontSize: 12, color: textSecondary)),
                          Text(b.nombreArchivo, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Fecha de Captura:", style: GoogleFonts.poppins(fontSize: 12, color: textSecondary)),
                          Text(b.fechaFormateada, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Tamaño en Disco:", style: GoogleFonts.poppins(fontSize: 12, color: textSecondary)),
                          Text(b.tamanoFormateado, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryGold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancelar", style: GoogleFonts.poppins(color: textSecondary, fontWeight: FontWeight.w500)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _ejecutarRestauracionConProgreso(context, b, service);
              },
              icon: const Icon(Icons.restore_rounded, color: Colors.white, size: 18),
              label: Text("Sí, Restablecer Sistema Ahora", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _ejecutarRestauracionConProgreso(BuildContext context, BackupModel b, BackupService service) {
    double progreso = 0.1;
    String status = "Iniciando validación del archivo de respaldo...";
    Map<String, dynamic>? resultadoFinal;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setProgressState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final bg = isDark ? AppColors.surfaceDark : Colors.white;
          final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
          final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
          final border = isDark ? AppColors.borderDark : AppColors.borderLight;

          return AlertDialog(
            backgroundColor: bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cloud_sync_rounded, color: AppColors.primaryPurple, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  "Restableciendo Sistema...",
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                ),
              ],
            ),
            content: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progreso,
                      minHeight: 10,
                      backgroundColor: isDark ? AppColors.cardDark : const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryGold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "${(progreso * 100).toInt()}%",
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryGold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.cardDark : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Column(
                      children: [
                        _buildStepCheck("1. Verificación de integridad SQLite", progreso >= 0.35, textPrimary, textSecondary),
                        const SizedBox(height: 6),
                        _buildStepCheck("2. Extracción de cotizaciones e inventario", progreso >= 0.70, textPrimary, textSecondary),
                        const SizedBox(height: 6),
                        _buildStepCheck("3. Sincronización con Nube y Celular", progreso >= 1.0, textPrimary, textSecondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (progreso >= 1.0)
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text("Entendido / Cerrar", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
            ],
          );
        },
      ),
    );

    // Ejecutar en segundo plano con callbacks
    Future.microtask(() async {
      final res = await service.restablecerBackup(
        b.nombreArchivo,
        onProgress: (newStatus, newProgress) {
          // El diálogo State se actualiza con el provider
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🎉 Sistema restablecido exitosamente al punto: ${b.nombreArchivo}"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

  Widget _buildStepCheck(String label, bool completed, Color textPrimary, Color textSecondary) {
    return Row(
      children: [
        Icon(
          completed ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 16,
          color: completed ? AppColors.success : textSecondary.withOpacity(0.5),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: completed ? FontWeight.w600 : FontWeight.w400,
              color: completed ? textPrimary : textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  void _mostrarDialogoProgramacion(BuildContext context, BackupService service) {
    TimeOfDay selectedTime = service.horaProgramada;
    String selectedFreq = service.frecuencia;
    bool activo = service.autoBackupActivo;

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
                  child: const Icon(Icons.schedule_rounded, color: AppColors.primaryPurple, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  "Programar Backup Automático",
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("Backup Automático Activado", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                  subtitle: Text("Genera copias periódicas de seguridad en segundo plano", style: GoogleFonts.poppins(fontSize: 11.5, color: textSecondary)),
                  value: activo,
                  activeColor: AppColors.primaryGold,
                  onChanged: (val) => setDlgState(() => activo = val),
                ),
                const SizedBox(height: 16),
                Text("Hora del Backup:", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: selectedTime,
                    );
                    if (picked != null) {
                      setDlgState(() => selectedTime = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.cardDark : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}",
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                        ),
                        const Icon(Icons.access_time_rounded, color: AppColors.primaryPurple, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text("Frecuencia de Respaldo:", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.cardDark : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedFreq,
                      dropdownColor: bg,
                      items: const [
                        DropdownMenuItem(value: 'Diaria (Cada 24h)', child: Text("Diaria (Cada 24h)")),
                        DropdownMenuItem(value: 'Cada 12 Horas', child: Text("Cada 12 Horas")),
                        DropdownMenuItem(value: 'Semanal (Cada Domingo)', child: Text("Semanal (Cada Domingo)")),
                      ],
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedFreq = val);
                      },
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
                  Navigator.pop(ctx);
                  await service.guardarProgramacion(
                    activo: activo,
                    hora: selectedTime,
                    frecuencia: selectedFreq,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("✅ Configuración de backup automático guardada"),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text("Guardar Horario", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }
}
