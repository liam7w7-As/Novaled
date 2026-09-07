import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models/articulo.dart';
import '../models/tienda.dart';
import '../services/sync_service.dart';
import 'tiendas_screen.dart';
import 'almacenamiento_configuracion_screen.dart';
import '../../drive_service.dart';

class AlmacenamientoScreen extends StatefulWidget {
  final Articulo? initialArt;
  final bool hideAppBar;
  const AlmacenamientoScreen({super.key, this.initialArt, this.hideAppBar = false});

  @override
  State<AlmacenamientoScreen> createState() => _AlmacenamientoScreenState();
}

class _AlmacenamientoScreenState extends State<AlmacenamientoScreen> {
  List<Articulo> _articulos = [];
  List<Tienda> _tiendas = [];
  bool _isLoading = true;
  final DriveService _drive = DriveService();

  bool _isSyncing = false;

  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _loadData().then((_) {
      if (widget.initialArt != null) {
        final art = _articulos.firstWhere(
          (a) => a.id == widget.initialArt!.id,
          orElse: () => widget.initialArt!,
        );
        _editarStock(art);
      }
      _syncEverything(silent: true);
    });
    // Sincronización automática periódica en tiempo real (cada 10 segundos)
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

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    final artData = await DatabaseHelper.instance.queryAllArticulos();
    final tiendaData = await DatabaseHelper.instance.queryAllTiendas();
    
    if (mounted) {
      setState(() {
        _articulos = artData.map((e) => Articulo.fromMap(e)).toList();
        _tiendas = tiendaData.map((e) => Tienda.fromMap(e)).toList();
        if (!silent) _isLoading = false;
      });
    }
  }

  Future<void> _syncEverything({bool silent = false}) async {
    if (!mounted) return;
    setState(() => _isSyncing = true);
    
    // --- 1. Sincronización con Google Drive (Solo si no es Web y está autenticado) ---
    if (!kIsWeb) {
      try {
        final hasDriveAuth = await _drive.authenticate();
        if (hasDriveAuth && _drive.driveApi != null) {
          // Tiendas (Almacenamiento)
          final localTiendas = await DatabaseHelper.instance.queryAllTiendas();
          for (var item in localTiendas) {
            final folderId = await _drive.syncItemToDrive('tiendas', Map<String, dynamic>.from(item));
            if (folderId == "DELETED_ON_DRIVE") {
              await DatabaseHelper.instance.deleteTienda(item['id']);
              continue;
            }
            if (folderId != null && folderId != item['folderId']) {
              final updated = Map<String, dynamic>.from(item)..['folderId'] = folderId;
              await DatabaseHelper.instance.updateTienda(updated);
            }
          }
          final cloudTiendas = await _drive.downloadAllFromTable('tiendas');
          for (var item in cloudTiendas) {
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

          // Artículos (para stock)
          final localArticulos = await DatabaseHelper.instance.queryAllArticulos();
          for (var item in localArticulos) {
            final folderId = await _drive.syncItemToDrive('articulos', Map<String, dynamic>.from(item));
            if (folderId == "DELETED_ON_DRIVE") {
              await DatabaseHelper.instance.deleteArticulo(item['id']);
              continue;
            }
            if (folderId != null && folderId != item['folderId']) {
              final updated = Map<String, dynamic>.from(item)..['folderId'] = folderId;
              await DatabaseHelper.instance.updateArticulo(updated);
            }
          }
          final cloudArticulos = await _drive.downloadAllFromTable('articulos');
          for (var item in cloudArticulos) {
            final folderId = item['folderId'];
            if (folderId != null) {
              final map = Map<String, dynamic>.from(item);
              final localId = await DatabaseHelper.instance.findMatchingLocalId('articulos', map);
              if (localId != null) {
                map['id'] = localId;
                await DatabaseHelper.instance.updateArticulo(map);
              } else {
                map.remove('id');
                await DatabaseHelper.instance.insertArticulo(map);
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Advertencia Google Drive sync en Almacenamiento: $e");
      }
    }

    // --- 2. Sincronización con MySQL Hostinger (Siempre en Android y Web) ---
    try {
      await SyncService.instance.syncTable('tiendas');
      await SyncService.instance.syncTable('sub_ubicaciones');
      await SyncService.instance.syncTable('articulos');

      await _loadData(silent: silent);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sincronización de almacenamiento completa"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Error de sincronización con la nube en Almacenamiento: $e");
      if (!silent && mounted) {
        final cleanMsg = e.toString().replaceFirst('Exception: ', '');
        final isOffline = cleanMsg.contains("Modo Offline");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOffline ? cleanMsg : "Error de sincronización con la nube: $cleanMsg"),
            backgroundColor: isOffline ? Colors.orange[800] : Colors.red,
            duration: Duration(seconds: isOffline ? 3 : 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _editarStock(Articulo art) {
    if (_tiendas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Primero debe crear al menos una tienda o depósito")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarStockScreen(articulo: art),
      ),
    ).then((result) {
      if (result == true) {
        _loadData();
      }
    });
  }

  Widget _buildInfoRow(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          Text(value, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  int _getTotalStock(String? stockJson) {
    if (stockJson == null || stockJson.isEmpty) return 0;
    try {
      final decoded = jsonDecode(stockJson);
      if (decoded is Map) {
        int total = 0;
        decoded.values.forEach((v) {
          if (v is Map) {
            v.values.forEach((subV) => total += (int.tryParse(subV.toString()) ?? 0));
          } else {
            total += (int.tryParse(v.toString()) ?? 0);
          }
        });
        return total;
      }
    } catch (_) {}
    return 0;
  }

  void _confirmDelete(Articulo art) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        title: Text("¿Eliminar?", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
        content: Text("Se borrará permanentemente '${art.nombre}'", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text("NO")),
          TextButton(
            onPressed: () async {
              Navigator.pop(confirmCtx);
              
              // Mostrar diálogo de "Procesando solicitud..."
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext progressContext) {
                  return PopScope(
                    canPop: false,
                    child: AlertDialog(
                      backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                      content: Row(
                        children: [
                          const CircularProgressIndicator(color: Color(0xFF00ADEF)),
                          const SizedBox(width: 20),
                          Text(
                            "Procesando solicitud...",
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );

              try {
                // 1. Borrar de la nube primero si tiene folderId
                if (art.folderId != null && art.folderId!.isNotEmpty) {
                  try {
                    await _drive.deleteFile(art.folderId!);
                  } catch (e) {
                    debugPrint("Error al borrar de Drive: $e");
                  }
                }
                
                // 2. Borrar de la base de datos local
                if (art.id != null) {
                  await DatabaseHelper.instance.deleteArticulo(art.id!);
                }
                await _loadData();
                
                // 3. Sincronización silenciosa para refrescar
                await _syncEverything(silent: true);
              } finally {
                // Cerrar diálogo de procesamiento
                if (mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text("SÍ", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: widget.hideAppBar ? null : AppBar(
        title: const Text("GESTIÓN DE ALMACENAMIENTO", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            color: isDark ? const Color(0xFF00ADEF) : Colors.white,
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AlmacenamientoConfiguracionScreen()),
              );
              _loadData();
            },
            tooltip: "Configuración de Almacenamiento",
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_articulos.isEmpty) {
            await _syncEverything();
          } else {
            await _loadData();
          }
        },
        color: const Color(0xFF00ADEF),
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.grey[200],
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00ADEF)))
            : _articulos.isEmpty
                ? Stack(
                    children: [
                      ListView(),
                      const Center(child: Text("Cargue artículos en el inventario primero. Desliza para sincronizar.", style: TextStyle(color: Colors.grey))),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _articulos.length,
                    itemBuilder: (context, index) {
                      final art = _articulos[index];
                      final total = _getTotalStock(art.stockJson);
                      
                      return Card(
                        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                        child: ListTile(
                          onTap: () => _editarStock(art),
                          title: Text(art.nombre, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                          subtitle: Text("Total en Stock: $total unidades", style: const TextStyle(color: Color(0xFF00ADEF))),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () => _confirmDelete(art),
                                tooltip: "Eliminar Artículo",
                              ),
                              const Icon(Icons.edit_location_alt, color: Color(0xFF00ADEF)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _UbicacionRow {
  final TextEditingController nombreController;
  final TextEditingController stockController;
  _UbicacionRow({String nombre = "General", int stock = 0})
      : nombreController = TextEditingController(text: nombre),
        stockController = TextEditingController(text: stock.toString());
}

class EditarStockScreen extends StatefulWidget {
  final Articulo articulo;
  const EditarStockScreen({super.key, required this.articulo});

  @override
  State<EditarStockScreen> createState() => _EditarStockScreenState();
}

class _ProductLocationEntry {
  String tiendaNombre;
  String subUbicacionNombre;
  _ProductLocationEntry({required this.tiendaNombre, required this.subUbicacionNombre});
}

class _EditarStockScreenState extends State<EditarStockScreen> {
  List<Tienda> _tiendas = [];
  List<SubUbicacion> _subUbicaciones = [];
  List<_ProductLocationEntry> _locationEntries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final tiendasRaw = await DatabaseHelper.instance.queryAllTiendas();
      final subRaw = await DatabaseHelper.instance.queryAllSubUbicaciones();
      
      if (mounted) {
        setState(() {
          _tiendas = tiendasRaw.map((e) => Tienda.fromMap(e)).toList();
          _subUbicaciones = subRaw.map((e) => SubUbicacion.fromMap(e)).toList();
          _initLocationEntries();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading data in EditarStockScreen: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initLocationEntries() {
    _locationEntries.clear();
    final art = widget.articulo;
    if (art.stockJson != null && art.stockJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(art.stockJson!);
        if (decoded is Map) {
          decoded.forEach((storeName, content) {
            if (content is Map) {
              content.keys.forEach((locName) {
                _locationEntries.add(_ProductLocationEntry(
                  tiendaNombre: storeName.toString(),
                  subUbicacionNombre: locName.toString(),
                ));
              });
            } else {
              _locationEntries.add(_ProductLocationEntry(
                tiendaNombre: storeName.toString(),
                subUbicacionNombre: "General",
              ));
            }
          });
        }
      } catch (e) {
        debugPrint("Error decoding stockJson: $e");
      }
    }

    // Ensure we have at least one entry if none exists and we have stores
    if (_locationEntries.isEmpty && _tiendas.isNotEmpty) {
      final defaultStore = _tiendas.first.nombre;
      final defaultSub = _getSubLocationsForStore(defaultStore).first;
      _locationEntries.add(_ProductLocationEntry(
        tiendaNombre: defaultStore,
        subUbicacionNombre: defaultSub,
      ));
    }
  }

  List<String> _getSubLocationsForStore(String storeName) {
    final list = _subUbicaciones
        .where((sub) => sub.tiendaNombre.toLowerCase() == storeName.toLowerCase())
        .map((sub) => sub.nombre)
        .toList();
    if (!list.contains("General")) {
      list.insert(0, "General");
    }
    return list;
  }

  Future<void> _onSave() async {
    Map<String, Map<String, int>> newStock = {};
    for (var entry in _locationEntries) {
      if (entry.tiendaNombre.trim().isEmpty) continue;
      String subLoc = entry.subUbicacionNombre.trim();
      if (subLoc.isEmpty) subLoc = "General";
      
      final storeMap = newStock.putIfAbsent(entry.tiendaNombre, () => {});
      storeMap[subLoc] = 0; // Quantities set to 0 as they are not used
    }

    final updatedArt = widget.articulo.copyWith(
      stockJson: jsonEncode(newStock),
    );

    await DatabaseHelper.instance.updateArticulo(updatedArt.toMap());
    
    final drive = DriveService();
    drive.syncItemToDrive('articulos', updatedArt.toMap()).then((newFolderId) async {
      if (newFolderId != null && newFolderId != updatedArt.folderId) {
        final map = updatedArt.toMap();
        map['folderId'] = newFolderId;
        await DatabaseHelper.instance.updateArticulo(map);
      }
    });

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Widget _buildLocationRow(_ProductLocationEntry entry, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subLocations = _getSubLocationsForStore(entry.tiendaNombre);
    
    if (!subLocations.contains(entry.subUbicacionNombre)) {
      entry.subUbicacionNombre = subLocations.first;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Card(
        color: isDark ? const Color(0xFF1C2431) : const Color(0xFFF9F9F9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Ubicación #${index + 1}",
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_locationEntries.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      onPressed: () {
                        setState(() {
                          _locationEntries.removeAt(index);
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              
              const Text("TIENDA", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                  color: isDark ? const Color(0xFF131A26) : Colors.white,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _tiendas.any((t) => t.nombre == entry.tiendaNombre) ? entry.tiendaNombre : (_tiendas.isNotEmpty ? _tiendas.first.nombre : null),
                    isExpanded: true,
                    dropdownColor: isDark ? const Color(0xFF131A26) : Colors.white,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.bold),
                    items: _tiendas.map((t) {
                      return DropdownMenuItem<String>(
                        value: t.nombre,
                        child: Text(t.nombre),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          entry.tiendaNombre = val;
                          final newSubs = _getSubLocationsForStore(val);
                          entry.subUbicacionNombre = newSubs.first;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              const Text("UBICACIÓN (sub ubicación)", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                  color: isDark ? const Color(0xFF131A26) : Colors.white,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: entry.subUbicacionNombre,
                    isExpanded: true,
                    dropdownColor: isDark ? const Color(0xFF131A26) : Colors.white,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                    items: subLocations.map((sub) {
                      return DropdownMenuItem<String>(
                        value: sub,
                        child: Text(sub),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          entry.subUbicacionNombre = val;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.articulo.nombre,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Prov: ${widget.articulo.proveedor ?? 'N/A'} | Caja: ${widget.articulo.codCaja ?? 'S/C'}",
              style: const TextStyle(color: Color(0xFF00ADEF), fontSize: 11),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: const Color(0xFF00ADEF),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.build_rounded),
            color: const Color(0xFF00ADEF),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AlmacenamientoConfiguracionScreen(),
                ),
              ).then((_) {
                _loadData();
              });
            },
            tooltip: "Configuración Almacén",
          ),
        ],
        backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Divider(
            color: isDark ? Colors.white10 : Colors.black12,
            height: 1.0,
            thickness: 1.0,
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_tiendas.isEmpty) ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40.0),
                          child: Column(
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orangeAccent),
                              const SizedBox(height: 12),
                              const Text(
                                "No hay tiendas configuradas",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Use el botón de configuración superior para añadir una.",
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    ] else ...[
                      ..._locationEntries.asMap().entries.map((item) {
                        return _buildLocationRow(item.value, item.key);
                      }),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              final defaultStore = _tiendas.first.nombre;
                              final defaultSub = _getSubLocationsForStore(defaultStore).first;
                              _locationEntries.add(_ProductLocationEntry(
                                tiendaNombre: defaultStore,
                                subUbicacionNombre: defaultSub,
                              ));
                            });
                          },
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00ADEF)),
                          label: const Text(
                            "AÑADIR UBICACIÓN",
                            style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: _isLoading || _tiendas.isEmpty
          ? null
          : Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131A26) : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white10 : Colors.black12,
                    width: 1.0,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    offset: const Offset(0, -3),
                    blurRadius: 10,
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom > 0
                    ? MediaQuery.of(context).padding.bottom + 8
                    : 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "CANCELAR",
                      style: TextStyle(
                        color: Color(0xFF00ADEF),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00ADEF),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    ),
                    onPressed: _onSave,
                    child: const Text("GUARDAR", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
    );
  }
}
