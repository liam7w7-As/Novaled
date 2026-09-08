import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../local_module/database_helper.dart';
import '../../local_module/models/articulo.dart';

class SelectArticuloModal extends StatefulWidget {
  final Articulo? initialSelected;

  const SelectArticuloModal({
    super.key,
    this.initialSelected,
  });

  static Future<Articulo?> show(BuildContext context, {Articulo? initialSelected}) {
    return showModalBottomSheet<Articulo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SelectArticuloModal(initialSelected: initialSelected),
    );
  }

  @override
  State<SelectArticuloModal> createState() => _SelectArticuloModalState();
}

class _SelectArticuloModalState extends State<SelectArticuloModal> {
  final TextEditingController _searchController = TextEditingController();
  List<Articulo> _allArticulos = [];
  List<Articulo> _filteredArticulos = [];
  bool _isLoading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadArticulos();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadArticulos() async {
    setState(() => _isLoading = true);
    try {
      final dbHelper = DatabaseHelper.instance;
      final rawArticulos = await dbHelper.queryAllArticulos();
      final articulos = rawArticulos.map((m) => Articulo.fromMap(m)).toList();
      if (mounted) {
        setState(() {
          _allArticulos = articulos;
          _filteredArticulos = articulos.take(50).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error al cargar artículos de catálogo: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      final query = _searchController.text.toLowerCase().trim();
      if (!mounted) return;

      setState(() {
        if (query.isEmpty) {
          _filteredArticulos = _allArticulos.take(50).toList();
        } else {
          final words = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
          _filteredArticulos = _allArticulos.where((art) {
            final nombre = art.nombre.toLowerCase();
            final desc = art.descripcion.toLowerCase();
            final cod = (art.codCaja ?? '').toLowerCase();
            final fam = art.familia.toLowerCase();
            final sub = art.subcategoria.toLowerCase();

            return words.every((word) =>
                nombre.contains(word) ||
                desc.contains(word) ||
                cod.contains(word) ||
                fam.contains(word) ||
                sub.contains(word));
          }).take(60).toList();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
        maxWidth: 600,
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
          // Drag Handle
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

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Catálogo de Artículos",
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

          // Search Field
          TextField(
            controller: _searchController,
            style: GoogleFonts.poppins(color: AppColors.textPrimary(isDark), fontSize: 14),
            decoration: AppDecorations.input(
              hintText: "Buscar por nombre, código o categoría...",
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryPurple, size: 20),
              isDark: isDark,
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
            ),
          ),

          const SizedBox(height: 12),

          // List or Loading
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primaryPurple),
              ),
            )
          else if (_filteredArticulos.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.textSecondary(isDark)),
                      const SizedBox(height: 12),
                      Text(
                        "No se encontraron artículos",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _filteredArticulos.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: AppColors.border(isDark)),
                itemBuilder: (context, index) {
                  final articulo = _filteredArticulos[index];
                  final isSelected = widget.initialSelected?.id == articulo.id;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    selected: isSelected,
                    selectedTileColor: AppColors.primaryPurple.withOpacity(0.08),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.shopping_bag_outlined, color: AppColors.primaryPurple, size: 20),
                    ),
                    title: Text(
                      articulo.nombre,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary(isDark),
                      ),
                    ),
                    subtitle: Text(
                      "${articulo.unidad.isNotEmpty ? articulo.unidad : 'Unidad'} ${articulo.subcategoria.isNotEmpty ? '• ${articulo.subcategoria}' : ''}",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textSecondary(isDark),
                      ),
                    ),
                    trailing: Text(
                      "Bs. ${articulo.precio.toStringAsFixed(2)}",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.primaryPurple,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, articulo),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
