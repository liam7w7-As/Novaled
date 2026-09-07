import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../local_module/database_helper.dart';
import '../../local_module/models/tienda.dart';

class SelectSucursalModal extends StatefulWidget {
  final String? initialSelected;

  const SelectSucursalModal({
    super.key,
    this.initialSelected,
  });

  static Future<String?> show(BuildContext context, {String? initialSelected}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => SelectSucursalModal(initialSelected: initialSelected),
    );
  }

  @override
  State<SelectSucursalModal> createState() => _SelectSucursalModalState();
}

class _SelectSucursalModalState extends State<SelectSucursalModal> {
  List<Tienda> _tiendas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTiendas();
  }

  Future<void> _loadTiendas() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query('tiendas', orderBy: 'nombre ASC');
      _tiendas = maps.map((m) => Tienda.fromMap(m)).toList();
    } catch (e) {
      debugPrint("Error al cargar tiendas: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: AppColors.card(isDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AppColors.primaryPurple),
                  ),
                )
              else if (_tiendas.isEmpty)
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
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _tiendas.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border(isDark)),
                  itemBuilder: (context, index) {
                    final tienda = _tiendas[index];
                    final fullText = "${tienda.nombre}${tienda.ubicacion.isNotEmpty ? ' - ${tienda.ubicacion}' : ''}";
                    final isSelected = widget.initialSelected == fullText || widget.initialSelected == tienda.nombre;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      selected: isSelected,
                      selectedTileColor: AppColors.primaryPurple.withOpacity(0.12),
                      leading: Icon(
                        Icons.store_mall_directory_rounded,
                        color: isSelected ? AppColors.primaryPurple : AppColors.textSecondary(isDark),
                      ),
                      title: Text(
                        tienda.nombre,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary(isDark),
                        ),
                      ),
                      subtitle: tienda.ubicacion.isNotEmpty
                          ? Text(
                              tienda.ubicacion,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.textSecondary(isDark),
                              ),
                            )
                          : null,
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.primaryPurple)
                          : const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      onTap: () => Navigator.pop(context, fullText),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
