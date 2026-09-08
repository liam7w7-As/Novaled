import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../local_module/database_helper.dart';
import '../../local_module/models/tienda.dart';
import '../../local_module/tenant_helper.dart';

class SelectSucursalModal extends StatefulWidget {
  final String? initialSelected;

  const SelectSucursalModal({
    super.key,
    this.initialSelected,
  });

  static Future<String?> show(BuildContext context, {String? initialSelected}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SelectSucursalModal(initialSelected: initialSelected),
    );
  }

  @override
  State<SelectSucursalModal> createState() => _SelectSucursalModalState();
}

class _SelectSucursalModalState extends State<SelectSucursalModal> {
  List<String> _sucursales = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSucursales();
  }

  Future<void> _loadSucursales() async {
    setState(() => _isLoading = true);
    try {
      final Set<String> items = {};
      final tenantSucursales = await TenantHelper.getSucursales();
      items.addAll(tenantSucursales);

      final db = await DatabaseHelper.instance.database;
      final maps = await db.query('tiendas', orderBy: 'nombre ASC');
      final tiendas = maps.map((m) => Tienda.fromMap(m)).toList();
      for (final t in tiendas) {
        final text = t.ubicacion.isNotEmpty ? "${t.nombre} - ${t.ubicacion}" : t.nombre;
        items.add(text);
      }

      _sucursales = items.where((s) => s.trim().isNotEmpty).toList();
    } catch (e) {
      debugPrint("Error al cargar sucursales: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.70,
        maxWidth: 520,
      ),
      margin: MediaQuery.of(context).size.width >= 960 ? const EdgeInsets.symmetric(vertical: 40) : EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Seleccionar Sucursal",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(isDark),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.primaryPurple),
              ),
            )
          else if (_sucursales.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "No hay sucursales registradas",
                  style: GoogleFonts.poppins(color: AppColors.textSecondary(isDark)),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: _sucursales.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: AppColors.border(isDark)),
                itemBuilder: (context, index) {
                  final sucursal = _sucursales[index];
                  final isSelected = widget.initialSelected == sucursal;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    selected: isSelected,
                    selectedTileColor: AppColors.primaryPurple.withOpacity(0.08),
                    leading: Icon(
                      Icons.storefront_outlined,
                      color: isSelected ? AppColors.primaryPurple : AppColors.textSecondary(isDark),
                    ),
                    title: Text(
                      sucursal,
                      style: GoogleFonts.poppins(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 14,
                        color: isSelected ? AppColors.primaryPurple : AppColors.textPrimary(isDark),
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.primaryPurple)
                        : const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
                    onTap: () => Navigator.pop(context, sucursal),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
