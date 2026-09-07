import 'dart:async';
import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models/tienda.dart';
import '../../drive_service.dart';

class TiendasScreen extends StatefulWidget {
  const TiendasScreen({super.key});

  @override
  State<TiendasScreen> createState() => _TiendasScreenState();
}

class _TiendasScreenState extends State<TiendasScreen> {
  List<Tienda> _tiendas = [];
  bool _isLoading = true;
  final DriveService _drive = DriveService();
  bool _isSyncing = false;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _refreshTiendas().then((_) => _syncEverything(silent: true));
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_isSyncing) {
        _syncEverything(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshTiendas({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.queryAllTiendas();
    if (mounted) {
      setState(() {
        _tiendas = data.map((e) => Tienda.fromMap(e)).toList();
        if (!silent) _isLoading = false;
      });
    }
  }

  void _showTiendaDialog({Tienda? tienda}) {
    final nombreController = TextEditingController(text: tienda?.nombre ?? '');
    final ubicacionController = TextEditingController(text: tienda?.ubicacion ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        title: Text(
          tienda == null ? "NUEVA TIENDA/DEPÓSITO" : "EDITAR TIENDA",
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: const InputDecoration(
                labelText: "Nombre",
                labelStyle: TextStyle(color: Color(0xFF00ADEF)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ubicacionController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: const InputDecoration(
                labelText: "Ubicación (opcional)",
                labelStyle: TextStyle(color: Color(0xFF00ADEF)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00ADEF)),
            onPressed: () async {
              if (nombreController.text.trim().isEmpty) return;

              final newTienda = Tienda(
                id: tienda?.id,
                nombre: nombreController.text.trim(),
                ubicacion: ubicacionController.text.trim(),
              );

              if (tienda == null) {
                await DatabaseHelper.instance.insertTienda(newTienda.toMap());
              } else {
                await DatabaseHelper.instance.updateTienda(newTienda.toMap());
              }

              if (mounted) {
                Navigator.pop(context);
                _refreshTiendas();
                _syncEverything(silent: true);
              }
            },
            child: Text(
              tienda == null ? "CREAR" : "GUARDAR",
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text("GESTIÓN DE TIENDAS", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: const [],
      ),
      body: RefreshIndicator(
        onRefresh: () => _syncEverything(),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00ADEF)))
            : _tiendas.isEmpty
                ? const Center(child: Text("No hay tiendas registradas", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _tiendas.length,
                    itemBuilder: (context, index) {
                      final t = _tiendas[index];
                      return Card(
                        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                        child: ListTile(
                          title: Text(t.nombre, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                          subtitle: Text(t.ubicacion.isEmpty ? "Sin ubicación" : t.ubicacion, style: const TextStyle(color: Colors.grey)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Color(0xFF00ADEF)),
                                onPressed: () => _showTiendaDialog(tienda: t),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                                      title: Text("¿Eliminar tienda?", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                                      content: Text("Esto no borrará el stock, pero la tienda ya no aparecerá en la lista.", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("CANCELAR")),
                                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("ELIMINAR", style: TextStyle(color: Colors.red))),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await DatabaseHelper.instance.deleteTienda(t.id!);
                                    _refreshTiendas();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00ADEF),
        onPressed: () => _showTiendaDialog(),
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  Future<void> _syncEverything({bool silent = false}) async {
    if (!mounted) return;
    setState(() => _isSyncing = true);
    try {
      // 1. Sincronizar locales a la nube
      final localData = await DatabaseHelper.instance.queryAllTiendas();
      for (var item in localData) {
        final newFolderId = await _drive.syncItemToDrive('tiendas', Map<String, dynamic>.from(item));
        if (newFolderId != null && newFolderId != item['folderId']) {
          final updatedMap = Map<String, dynamic>.from(item);
          updatedMap['folderId'] = newFolderId;
          await DatabaseHelper.instance.updateTienda(updatedMap);
        }
      }

      // 2. Descargar de la nube
      final cloudData = await _drive.downloadAllFromTable('tiendas');
      for (var item in cloudData) {
        final folderId = item['folderId'];
        if (folderId != null) {
          final map = Map<String, dynamic>.from(item);
          final localId = await DatabaseHelper.instance.findMatchingLocalId('tiendas', map);
          if (localId != null) {
            map['id'] = localId;
            await DatabaseHelper.instance.updateTienda(map);
          } else {
            map.remove('id');
            await DatabaseHelper.instance.insertTienda(map);
          }
        }
      }

      await _refreshTiendas(silent: silent);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Tiendas sincronizadas"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Error sync tiendas: $e");
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error de sincronización: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }
}
