import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../services/empresa_service.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<EmpresaService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    final logs = service.logs;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Auditoría y Registro de Eventos",
            style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary),
          ),
          Text(
            "Trazabilidad completa de todas las operaciones realizadas por el SuperAdmin",
            style: GoogleFonts.poppins(fontSize: 13, color: textSecondary),
          ),
          const SizedBox(height: 20),

          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
            ),
            child: logs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Center(
                      child: Text("Sin eventos de auditoría registrados.", style: GoogleFonts.poppins(color: textSecondary)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: logs.length,
                    separatorBuilder: (_, _) => Divider(color: border, height: 1),
                    itemBuilder: (context, i) {
                      final log = logs[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryPurple.withOpacity(0.12),
                          child: const Icon(Icons.history_toggle_off_rounded, color: AppColors.primaryPurple, size: 20),
                        ),
                        title: Text(
                          log.descripcion,
                          style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w500, color: textPrimary),
                        ),
                        subtitle: Text(
                          "Acción: ${log.accion} • Usuario: ${log.usuarioSuperadmin} • ${log.fecha.toString().split('.')[0]}",
                          style: GoogleFonts.poppins(fontSize: 11.5, color: textSecondary),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            log.accion,
                            style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.bold, color: textSecondary),
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
}
