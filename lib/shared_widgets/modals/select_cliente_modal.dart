import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../local_module/database_helper.dart';
import '../../local_module/models/cliente.dart';
import '../buttons/primary_action_button.dart';

class SelectClienteModal extends StatefulWidget {
  final Cliente? initialSelected;

  const SelectClienteModal({
    super.key,
    this.initialSelected,
  });

  static Future<Cliente?> show(BuildContext context, {Cliente? initialSelected}) {
    return showDialog<Cliente>(
      context: context,
      barrierDismissible: true,
      builder: (context) => SelectClienteModal(initialSelected: initialSelected),
    );
  }

  @override
  State<SelectClienteModal> createState() => _SelectClienteModalState();
}

class _SelectClienteModalState extends State<SelectClienteModal> {
  final TextEditingController _searchController = TextEditingController();
  List<Cliente> _allClientes = [];
  List<Cliente> _filteredClientes = [];
  bool _isLoading = true;
  bool _isCreating = false;

  // Controladores para creación rápida de cliente
  final TextEditingController _newNombreController = TextEditingController();
  final TextEditingController _newTelefonoController = TextEditingController();
  final TextEditingController _newCorreoController = TextEditingController();
  final TextEditingController _newRnController = TextEditingController();
  final TextEditingController _newDireccionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadClientes();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _newNombreController.dispose();
    _newTelefonoController.dispose();
    _newCorreoController.dispose();
    _newRnController.dispose();
    _newDireccionController.dispose();
    super.dispose();
  }

  Future<void> _loadClientes() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query('clientes', orderBy: 'nombreCompania ASC');
      _allClientes = maps.map((m) => Cliente.fromMap(m)).toList();
      _filteredClientes = List.from(_allClientes);
    } catch (e) {
      debugPrint("Error al cargar clientes: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredClientes = List.from(_allClientes);
      } else {
        _filteredClientes = _allClientes.where((c) {
          final nombre = c.nombreCompania.toLowerCase();
          final tel = c.telefono.toLowerCase();
          final correo = c.correo.toLowerCase();
          final rn = c.rn.toLowerCase();
          return nombre.contains(query) || tel.contains(query) || correo.contains(query) || rn.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _saveQuickClient() async {
    final nombre = _newNombreController.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre del cliente es obligatorio.')),
      );
      return;
    }

    try {
      final db = await DatabaseHelper.instance.database;
      final newClient = Cliente(
        nombreCompania: nombre,
        telefono: _newTelefonoController.text.trim(),
        correo: _newCorreoController.text.trim(),
        rn: _newRnController.text.trim(),
        direccion1: _newDireccionController.text.trim(),
      );

      final id = await db.insert('clientes', newClient.toMap());
      final created = Cliente(
        id: id,
        nombreCompania: newClient.nombreCompania,
        telefono: newClient.telefono,
        correo: newClient.correo,
        rn: newClient.rn,
        direccion1: newClient.direccion1,
      );

      if (mounted) {
        Navigator.pop(context, created);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar cliente: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: AppColors.card(isDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con Título y Botón Cerrar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isCreating ? "Registrar Nuevo Cliente" : "Seleccionar Cliente",
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

              if (!_isCreating) ...[
                // Barra de Búsqueda y Botón "+ Nuevo"
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: AppColors.textPrimary(isDark)),
                        decoration: AppDecorations.input(
                          hintText: "Buscar por nombre, NIT, teléfono...",
                          isDark: isDark,
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.all(14),
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
                      tooltip: "Nuevo Cliente",
                      onPressed: () => setState(() => _isCreating = true),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Lista de Clientes
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple))
                      : _filteredClientes.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_search_rounded, size: 48, color: AppColors.textSecondary(isDark)),
                                  const SizedBox(height: 8),
                                  Text(
                                    "No se encontraron clientes",
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: AppColors.textSecondary(isDark),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _filteredClientes.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: AppColors.border(isDark),
                              ),
                              itemBuilder: (context, index) {
                                final cliente = _filteredClientes[index];
                                final isSelected = widget.initialSelected?.id == cliente.id;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  selected: isSelected,
                                  selectedTileColor: AppColors.primaryPurple.withOpacity(0.12),
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryPurple.withOpacity(0.15),
                                    child: Text(
                                      cliente.nombreCompania.isNotEmpty
                                          ? cliente.nombreCompania[0].toUpperCase()
                                          : 'C',
                                      style: const TextStyle(
                                        color: AppColors.primaryPurple,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    cliente.nombreCompania,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: AppColors.textPrimary(isDark),
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (cliente.rn.isNotEmpty) "NIT/CI: ${cliente.rn}",
                                      if (cliente.telefono.isNotEmpty) "Tel: ${cliente.telefono}",
                                    ].join(" • "),
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: AppColors.textSecondary(isDark),
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(Icons.check_circle_rounded, color: AppColors.primaryPurple)
                                      : const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                                  onTap: () => Navigator.pop(context, cliente),
                                );
                              },
                            ),
                ),
              ] else ...[
                // Formulario de Creación Rápida
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        TextField(
                          controller: _newNombreController,
                          style: TextStyle(color: AppColors.textPrimary(isDark)),
                          decoration: AppDecorations.input(
                            hintText: "Nombre del Cliente / Razón Social *",
                            isDark: isDark,
                            prefixIcon: const Icon(Icons.business_rounded, size: 20),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newRnController,
                          style: TextStyle(color: AppColors.textPrimary(isDark)),
                          decoration: AppDecorations.input(
                            hintText: "NIT / CI / Documento",
                            isDark: isDark,
                            prefixIcon: const Icon(Icons.badge_rounded, size: 20),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newTelefonoController,
                          style: TextStyle(color: AppColors.textPrimary(isDark)),
                          decoration: AppDecorations.input(
                            hintText: "Teléfono / WhatsApp",
                            isDark: isDark,
                            prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newCorreoController,
                          style: TextStyle(color: AppColors.textPrimary(isDark)),
                          decoration: AppDecorations.input(
                            hintText: "Correo Electrónico",
                            isDark: isDark,
                            prefixIcon: const Icon(Icons.email_rounded, size: 20),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newDireccionController,
                          style: TextStyle(color: AppColors.textPrimary(isDark)),
                          decoration: AppDecorations.input(
                            hintText: "Dirección",
                            isDark: isDark,
                            prefixIcon: const Icon(Icons.location_on_rounded, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _isCreating = false),
                      child: Text("Cancelar", style: GoogleFonts.poppins(color: AppColors.textSecondary(isDark))),
                    ),
                    const SizedBox(width: 12),
                    PrimaryActionButton(
                      label: "Guardar y Seleccionar",
                      onPressed: _saveQuickClient,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
