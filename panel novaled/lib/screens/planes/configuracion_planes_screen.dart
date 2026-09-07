import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/plan_model.dart';
import '../../services/empresa_service.dart';

class ConfiguracionPlanesScreen extends StatefulWidget {
  const ConfiguracionPlanesScreen({super.key});

  @override
  State<ConfiguracionPlanesScreen> createState() => _ConfiguracionPlanesScreenState();
}

class _ConfiguracionPlanesScreenState extends State<ConfiguracionPlanesScreen> {
  @override
  Widget build(BuildContext context) {
    final service = context.watch<EmpresaService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    final planes = service.planes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            "Configuración de Planes y Tarifas",
            style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary),
          ),
          Text(
            "Control de límites por categoría (Cotizaciones, Notas de venta, Notas de entrega, Escaneos mágicos y Usuarios)",
            style: GoogleFonts.poppins(fontSize: 13, color: textSecondary),
          ),
          const SizedBox(height: 24),

          // Tarjetas de Planes
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 950;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: planes.map((p) {
                  final isPopular = p.id == 'pro';
                  return Expanded(
                    flex: isWide ? 1 : 0,
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: isWide && p != planes.last ? 16.0 : 0.0,
                        bottom: !isWide ? 16.0 : 0.0,
                      ),
                      child: _buildPlanConfigCard(p, service, isDark, textPrimary, textSecondary, cardBg, border, isPopular),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlanConfigCard(
    PlanModel p,
    EmpresaService service,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color cardBg,
    Color border,
    bool isPopular,
  ) {
    final isProOrPlus = p.esPro || p.esPlus;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPopular ? AppColors.primaryPurple : (p.esPlus ? AppColors.primaryGold.withOpacity(0.5) : border),
          width: isPopular || p.esPlus ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPopular)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(
                color: AppColors.primaryPurple,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Center(
                child: Text(
                  "Más popular",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      p.nombre,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isPopular ? AppColors.primaryPurple : (p.esPlus ? AppColors.primaryGold : textPrimary),
                      ),
                    ),
                    if (p.esPlus)
                      const Icon(Icons.verified_rounded, color: AppColors.primaryGold, size: 22)
                    else if (isPopular)
                      const Icon(Icons.bolt_rounded, color: AppColors.primaryPurple, size: 22),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      "${p.moneda} ${p.precio.toStringAsFixed(0)}",
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      p.precio == 0 ? "" : "/ mes",
                      style: GoogleFonts.poppins(fontSize: 13, color: textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  p.descripcion,
                  style: GoogleFonts.poppins(fontSize: 12, color: textSecondary),
                ),
                const SizedBox(height: 16),
                Divider(color: border),
                const SizedBox(height: 12),

                // Lista de Características Oficiales
                _buildFeatureRow(
                  Icons.description_outlined,
                  p.esIlimitadoCotizaciones ? "Cotizaciones ilimitadas" : "${p.limiteCotizaciones} cotizaciones",
                  true,
                  textPrimary,
                ),
                _buildFeatureRow(
                  Icons.point_of_sale_rounded,
                  p.esIlimitadoNotasVenta ? "Notas de venta ilimitadas" : "${p.limiteNotasVenta} notas de venta",
                  true,
                  textPrimary,
                ),
                _buildFeatureRow(
                  Icons.local_shipping_outlined,
                  p.esIlimitadoNotasEntrega ? "Notas de entrega ilimitadas" : "${p.limiteNotasEntrega} notas de entrega",
                  true,
                  textPrimary,
                ),
                _buildFeatureRow(
                  Icons.auto_awesome_rounded,
                  p.esIlimitadoEscaneos
                      ? "Escaneos mágicos ilimitados"
                      : "${p.limiteEscaneosMagicos} escaneos mágicos al mes",
                  true,
                  textPrimary,
                ),
                _buildFeatureRow(
                  Icons.apartment_rounded,
                  "Información de empresa y logo",
                  p.permiteInfoLogo,
                  textPrimary,
                ),
                _buildFeatureRow(
                  Icons.edit_note_rounded,
                  "Modo edición desbloqueado",
                  p.permiteModoEdicion,
                  textPrimary,
                ),
                _buildFeatureRow(
                  Icons.palette_outlined,
                  "Paleta de colores",
                  p.permitePaletaColores,
                  textPrimary,
                ),
                _buildFeatureRow(
                  Icons.people_outline_rounded,
                  p.esIlimitadoUsuarios ? "Usuarios ilimitados" : "Hasta ${p.limiteUsuarios} usuarios",
                  true,
                  textPrimary,
                ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _mostrarEditarPlanModal(p, service),
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text("Modificar Límites & Precio"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text, bool enabled, Color textPrimary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_rounded : Icons.close_rounded,
            size: 18,
            color: enabled ? AppColors.primaryPurple : AppColors.neutral.withOpacity(0.4),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: enabled ? textPrimary : AppColors.textDarkMuted,
                decoration: enabled ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarEditarPlanModal(PlanModel p, EmpresaService service) {
    final precioCtrl = TextEditingController(text: p.precio.toStringAsFixed(0));
    final cotCtrl = TextEditingController(text: p.limiteCotizaciones.toString());
    final nvCtrl = TextEditingController(text: p.limiteNotasVenta.toString());
    final neCtrl = TextEditingController(text: p.limiteNotasEntrega.toString());
    final escCtrl = TextEditingController(text: p.limiteEscaneosMagicos.toString());
    final usersCtrl = TextEditingController(text: p.limiteUsuarios.toString());

    bool edicion = p.permiteModoEdicion;
    bool paleta = p.permitePaletaColores;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text("Editar ${p.nombre}"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: precioCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Precio (Bs.)"),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cotCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Límite Cotizaciones (-1 = ilimitado)"),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nvCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Límite Notas de Venta (-1 = ilimitado)"),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: neCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Límite Notas de Entrega (-1 = ilimitado)"),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: escCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Escaneos Mágicos (-1 = ilimitado)"),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: usersCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Límite Usuarios (-1 = ilimitado)"),
                  ),
                  const SizedBox(height: 14),
                  CheckboxListTile(
                    title: const Text("Modo edición desbloqueado"),
                    value: edicion,
                    onChanged: (v) => setModalState(() => edicion = v ?? false),
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text("Paleta de colores"),
                    value: paleta,
                    onChanged: (v) => setModalState(() => paleta = v ?? false),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: () {
                  final planesList = List<PlanModel>.from(service.planes);
                  final idx = planesList.indexWhere((item) => item.id == p.id);
                  if (idx != -1) {
                    planesList[idx] = PlanModel(
                      id: p.id,
                      nombre: p.nombre,
                      precio: double.tryParse(precioCtrl.text.trim()) ?? p.precio,
                      moneda: p.moneda,
                      descripcion: p.descripcion,
                      limiteCotizaciones: int.tryParse(cotCtrl.text.trim()) ?? p.limiteCotizaciones,
                      limiteNotasVenta: int.tryParse(nvCtrl.text.trim()) ?? p.limiteNotasVenta,
                      limiteNotasEntrega: int.tryParse(neCtrl.text.trim()) ?? p.limiteNotasEntrega,
                      limiteEscaneosMagicos: int.tryParse(escCtrl.text.trim()) ?? p.limiteEscaneosMagicos,
                      limiteUsuarios: int.tryParse(usersCtrl.text.trim()) ?? p.limiteUsuarios,
                      permiteInfoLogo: true,
                      permiteModoEdicion: edicion,
                      permitePaletaColores: paleta,
                    );
                    service.guardarPlanesActualizados(planesList);
                  }
                  Navigator.pop(ctx);
                },
                child: const Text("Guardar Cambios"),
              ),
            ],
          );
        },
      ),
    );
  }
}
