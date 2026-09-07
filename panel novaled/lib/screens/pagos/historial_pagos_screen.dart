import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/pago_model.dart';
import '../../services/empresa_service.dart';

class HistorialPagosScreen extends StatelessWidget {
  const HistorialPagosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<EmpresaService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    final pagos = service.pagos;
    final double totalRecaudado = pagos.fold(0.0, (sum, p) => sum + p.monto);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Facturación y Pagos de Suscripciones",
                    style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary),
                  ),
                  Text(
                    "Registro de ingresos, comprobantes y renovaciones",
                    style: GoogleFonts.poppins(fontSize: 13, color: textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _mostrarModalRegistrarPagoGlobal(context, service),
                icon: const Icon(Icons.add_card_rounded, size: 18, color: Colors.white),
                label: const Text("Registrar Pago"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Total recaudado
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.success, size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Total Histórico Recaudado", style: GoogleFonts.poppins(fontSize: 13, color: textSecondary)),
                    Text(
                      "Bs. ${totalRecaudado.toStringAsFixed(2)}",
                      style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: textPrimary),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  "${pagos.length} transacciones registradas",
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Tabla de Pagos
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
            ),
            child: pagos.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Center(
                      child: Text("No existen pagos registrados.", style: GoogleFonts.poppins(color: textSecondary)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pagos.length,
                    separatorBuilder: (_, _) => Divider(color: border, height: 1),
                    itemBuilder: (context, i) {
                      final p = pagos[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.success.withOpacity(0.12),
                              child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.empresaNombre,
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13.5, color: textPrimary),
                                  ),
                                  Text(
                                    "Ref: ${p.referenciaTransaccion} • ${p.metodoPago}",
                                    style: GoogleFonts.poppins(fontSize: 11.5, color: textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                p.planNombre,
                                style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w500, color: textPrimary),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                "Cobertura hasta: ${p.fechaCoberturaHasta.toString().split(' ')[0]}",
                                style: GoogleFonts.poppins(fontSize: 11.5, color: textSecondary),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                "${p.moneda} ${p.monto.toStringAsFixed(2)}",
                                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success),
                                textAlign: TextAlign.right,
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
    );
  }

  void _mostrarModalRegistrarPagoGlobal(BuildContext context, EmpresaService service) {
    if (service.empresas.isEmpty) return;

    String empresaSeleccionadaId = service.empresas.first.id;
    final montoCtrl = TextEditingController(text: "150");
    final refCtrl = TextEditingController();
    int meses = 1;
    String metodo = 'Transferencia Bancaria';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text("Registrar Pago de Suscripción"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: empresaSeleccionadaId,
                    decoration: const InputDecoration(labelText: "Empresa"),
                    items: service.empresas.map((e) {
                      return DropdownMenuItem(value: e.id, child: Text(e.nombreComercial));
                    }).toList(),
                    onChanged: (v) => setModalState(() => empresaSeleccionadaId = v ?? empresaSeleccionadaId),
                  ),
                  const SizedBox(height: 12),
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
                    decoration: const InputDecoration(labelText: "Referencia de Transacción"),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: () {
                  final empresa = service.getEmpresaById(empresaSeleccionadaId);
                  if (empresa != null) {
                    final monto = double.tryParse(montoCtrl.text.trim()) ?? 150.0;
                    final now = DateTime.now();
                    final nuevoPago = PagoModel(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      empresaId: empresa.id,
                      empresaNombre: empresa.nombreComercial,
                      monto: monto,
                      moneda: empresa.monedaSimbolo,
                      planId: empresa.planId,
                      planNombre: empresa.planId == 'pro_anual' ? 'Plan PRO Anual' : 'Plan PRO Mensual',
                      mesesPagados: meses,
                      metodoPago: metodo,
                      referenciaTransaccion: refCtrl.text.trim().isNotEmpty ? refCtrl.text.trim() : 'PAGO-MANUAL',
                      fechaPago: now,
                      fechaCoberturaDesde: now,
                      fechaCoberturaHasta: now.add(Duration(days: 30 * meses)),
                      registradoPor: 'SuperAdmin Novaled',
                    );
                    service.registrarPago(nuevoPago);
                  }
                  Navigator.pop(ctx);
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
