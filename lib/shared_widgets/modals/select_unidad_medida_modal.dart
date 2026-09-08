import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../local_module/database_helper.dart';
import '../../local_module/services/sync_service.dart';

class SelectUnidadMedidaModal extends StatefulWidget {
  final String seleccionInicial;

  const SelectUnidadMedidaModal({
    super.key,
    required this.seleccionInicial,
  });

  static Future<String?> show(BuildContext context, {String seleccionInicial = "Unidad"}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SelectUnidadMedidaModal(seleccionInicial: seleccionInicial),
    );
  }

  @override
  State<SelectUnidadMedidaModal> createState() => _SelectUnidadMedidaModalState();
}

class _SelectUnidadMedidaModalState extends State<SelectUnidadMedidaModal> {
  List<String> _lista = [];
  late String _seleccionada;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _seleccionada = widget.seleccionInicial;
    _recargarLista();
    _liveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _recargarLista();
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _recargarLista() async {
    try {
      try {
        await SyncService.instance.syncTable('unidades_medida');
      } catch (_) {}
      final raw = await DatabaseHelper.instance.queryAllUnidadesMedida();
      final names = raw.map((u) => u['nombre']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
      if (names.isNotEmpty && mounted) {
        setState(() {
          _lista = names;
        });
      }
    } catch (_) {}
  }

  void _dialogAgregar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.card(isDark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Nueva Unidad de Medida",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(isDark),
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.poppins(fontSize: 15, color: AppColors.textPrimary(isDark)),
            decoration: InputDecoration(
              hintText: "Ej: Rollo, Kg, Docena...",
              hintStyle: GoogleFonts.poppins(color: AppColors.textSecondary(isDark)),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primaryPurple, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text("CANCELAR", style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isNotEmpty) {
                  Navigator.pop(dialogCtx);
                  if (!_lista.any((u) => u.toLowerCase() == nombre.toLowerCase())) {
                    setState(() {
                      _lista.add(nombre);
                      _seleccionada = nombre;
                    });
                  }
                  final uuid = "UM_${DateTime.now().millisecondsSinceEpoch}";
                  try {
                    await DatabaseHelper.instance.insertUnidadMedida({
                      'nombre': nombre,
                      'folderId': uuid,
                    });
                    await DatabaseHelper.instance.setTableDirty('unidades_medida');
                    await SyncService.instance.syncTable('unidades_medida');
                  } catch (_) {}
                  _recargarLista();
                }
              },
              child: Text("GUARDAR", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  void _dialogEditar(int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prev = _lista[index];
    final ctrl = TextEditingController(text: prev);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.card(isDark),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Editar Unidad de Medida",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(isDark),
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.poppins(fontSize: 15, color: AppColors.textPrimary(isDark)),
            decoration: const InputDecoration(
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primaryPurple, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text("CANCELAR", style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isNotEmpty && nombre.toLowerCase() != prev.toLowerCase()) {
                  Navigator.pop(dialogCtx);
                  setState(() {
                    _lista[index] = nombre;
                    if (_seleccionada.toLowerCase() == prev.toLowerCase()) {
                      _seleccionada = nombre;
                    }
                  });
                  try {
                    final db = await DatabaseHelper.instance.database;
                    final raw = await db.query('unidades_medida', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [prev.toLowerCase()], limit: 1);
                    if (raw.isNotEmpty) {
                      final id = raw.first['id'] as int;
                      final oldFolderId = raw.first['folderId']?.toString();
                      await DatabaseHelper.instance.recordDeletion('unidades_medida', oldFolderId ?? "OLD_${DateTime.now().millisecondsSinceEpoch}", nombre: prev);
                      final newUuid = "UM_${DateTime.now().millisecondsSinceEpoch}";
                      await DatabaseHelper.instance.updateUnidadMedida({
                        'id': id,
                        'nombre': nombre,
                        'folderId': newUuid,
                      });
                    }
                    await DatabaseHelper.instance.setTableDirty('unidades_medida');
                    await SyncService.instance.syncTable('unidades_medida');
                  } catch (_) {}
                  _recargarLista();
                } else {
                  Navigator.pop(dialogCtx);
                }
              },
              child: Text("ACTUALIZAR", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  void _eliminar(int index) async {
    if (_lista.length <= 1) return;
    final item = _lista[index];
    setState(() {
      _lista.removeAt(index);
      if (_seleccionada.toLowerCase() == item.toLowerCase()) {
        _seleccionada = _lista.first;
      }
    });
    try {
      final db = await DatabaseHelper.instance.database;
      final raw = await db.query('unidades_medida', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [item.toLowerCase()], limit: 1);
      if (raw.isNotEmpty) {
        final id = raw.first['id'] as int;
        final folderId = raw.first['folderId']?.toString();
        await DatabaseHelper.instance.recordDeletion('unidades_medida', folderId ?? "OLD_${DateTime.now().millisecondsSinceEpoch}", nombre: item);
        await DatabaseHelper.instance.deleteUnidadMedida(id);
      } else {
        await DatabaseHelper.instance.recordDeletion('unidades_medida', "OLD_${DateTime.now().millisecondsSinceEpoch}", nombre: item);
      }
      await DatabaseHelper.instance.setTableDirty('unidades_medida');
      await SyncService.instance.syncTable('unidades_medida');
    } catch (_) {}
    _recargarLista();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
        maxWidth: 520,
      ),
      margin: MediaQuery.of(context).size.width >= 960 ? const EdgeInsets.symmetric(vertical: 40) : EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Unidad de Medida",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(isDark),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryPurple,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(
                  "Agregar",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                onPressed: _dialogAgregar,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _lista.length,
              separatorBuilder: (context, index) => Divider(
                color: AppColors.border(isDark),
                height: 1,
              ),
              itemBuilder: (context, idx) {
                final u = _lista[idx];
                final isSelected = _seleccionada.toLowerCase() == u.toLowerCase();

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  title: Text(
                    u,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.primaryPurple : AppColors.textPrimary(isDark),
                    ),
                  ),
                  leading: Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: isSelected ? AppColors.primaryPurple : AppColors.textSecondary(isDark),
                    size: 22,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary(isDark)),
                        onPressed: () => _dialogEditar(idx),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.stateRedError),
                        onPressed: () => _eliminar(idx),
                      ),
                    ],
                  ),
                  onTap: () {
                    setState(() {
                      _seleccionada = u;
                    });
                    Navigator.pop(context, u);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
