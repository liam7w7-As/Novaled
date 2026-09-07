import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../database_helper.dart';
import '../models/tienda.dart';
import '../services/sync_service.dart';
import '../../drive_service.dart';

class SubUbicacion {
  final int? id;
  final String nombre;
  final String tiendaNombre;
  final String? folderId;
  final String? imagen;

  SubUbicacion({
    this.id,
    required this.nombre,
    required this.tiendaNombre,
    this.folderId,
    this.imagen,
  });

  factory SubUbicacion.fromMap(Map<String, dynamic> map) {
    return SubUbicacion(
      id: map['id'] as int?,
      nombre: map['nombre']?.toString() ?? '',
      tiendaNombre: map['tienda_nombre']?.toString() ?? '',
      folderId: map['folderId']?.toString(),
      imagen: map['imagen']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
      'tienda_nombre': tiendaNombre,
      if (folderId != null) 'folderId': folderId,
      if (imagen != null) 'imagen': imagen,
    };
  }
}

class AlmacenamientoConfiguracionScreen extends StatefulWidget {
  final bool hideAppBar;
  const AlmacenamientoConfiguracionScreen({super.key, this.hideAppBar = false});

  @override
  State<AlmacenamientoConfiguracionScreen> createState() => _AlmacenamientoConfiguracionScreenState();
}

class _AlmacenamientoConfiguracionScreenState extends State<AlmacenamientoConfiguracionScreen> {
  List<Tienda> _tiendas = [];
  List<SubUbicacion> _subUbicaciones = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  final DriveService _drive = DriveService();
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _loadData().then((_) => _syncEverything(silent: true));
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
    final tiendasRaw = await DatabaseHelper.instance.queryAllTiendas();
    final subRaw = await DatabaseHelper.instance.queryAllSubUbicaciones();
    if (mounted) {
      setState(() {
        _tiendas = tiendasRaw.map((e) => Tienda.fromMap(e)).toList();
        _subUbicaciones = subRaw.map((e) => SubUbicacion.fromMap(e)).toList();
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
          // Sincronizar tiendas locales a Drive
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
          
          // Descargar tiendas de Drive
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

          // Sincronizar sub-ubicaciones locales a Drive
          final localSubs = await DatabaseHelper.instance.queryAllSubUbicaciones();
          for (var item in localSubs) {
            final folderId = await _drive.syncItemToDrive('sub_ubicaciones', Map<String, dynamic>.from(item));
            if (folderId == "DELETED_ON_DRIVE") {
              await DatabaseHelper.instance.deleteSubUbicacion(item['id']);
              continue;
            }
            if (folderId != null && folderId != item['folderId']) {
              final updated = Map<String, dynamic>.from(item)..['folderId'] = folderId;
              await DatabaseHelper.instance.updateSubUbicacion(updated);
            }
          }

          // Descargar sub-ubicaciones de Drive
          final cloudSubs = await _drive.downloadAllFromTable('sub_ubicaciones');
          for (var item in cloudSubs) {
            final folderId = item['folderId'];
            if (folderId != null) {
              final map = Map<String, dynamic>.from(item);
              final localId = await DatabaseHelper.instance.findMatchingLocalId('sub_ubicaciones', map);
              if (localId != null) {
                map['id'] = localId;
                await DatabaseHelper.instance.updateSubUbicacion(map);
              } else {
                map.remove('id');
                await DatabaseHelper.instance.insertSubUbicacion(map);
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Advertencia: Falló la sincronización con Google Drive: $e");
      }
    }

    // --- 2. Sincronización con MySQL Hostinger (Siempre se ejecuta, en Android y Web) ---
    try {
      await SyncService.instance.syncTable('tiendas');
      await SyncService.instance.syncTable('sub_ubicaciones');
      
      await _loadData(silent: silent);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Datos sincronizados con éxito"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Error al sincronizar con MySQL Hostinger: $e");
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error de sincronización con la nube: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showTiendaDialog({Tienda? tienda}) {
    final nombreController = TextEditingController(text: tienda?.nombre ?? '');
    final ubicacionController = TextEditingController(text: tienda?.ubicacion ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          tienda == null ? "AUMENTAR TIENDA" : "EDITAR TIENDA",
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: const InputDecoration(
                labelText: "Nombre de Tienda",
                labelStyle: TextStyle(color: Color(0xFF00ADEF)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ADEF))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ubicacionController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: const InputDecoration(
                labelText: "Depósito / Ubicación (opcional)",
                labelStyle: TextStyle(color: Color(0xFF00ADEF)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ADEF))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00ADEF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final nombre = nombreController.text.trim();
              if (nombre.isEmpty) return;

              final map = {
                if (tienda?.id != null) 'id': tienda!.id,
                'nombre': nombre,
                'ubicacion': ubicacionController.text.trim(),
                if (tienda?.folderId != null) 'folderId': tienda!.folderId,
              };

              if (tienda == null) {
                await DatabaseHelper.instance.insertTienda(map);
              } else {
                await DatabaseHelper.instance.updateTienda(map);
              }

              if (mounted) {
                Navigator.pop(context);
                _loadData();
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

  void _showSubUbicacionDialog({SubUbicacion? sub}) {
    final nombreController = TextEditingController(text: sub?.nombre ?? '');
    String? selectedTienda = sub?.tiendaNombre;
    XFile? pickedImage;
    String? currentImageName = sub?.imagen;
    bool isUploading = false;
    
    // Si la tienda guardada ya no existe en la lista de tiendas activas, resetear
    if (selectedTienda != null && !_tiendas.any((t) => t.nombre == selectedTienda)) {
      selectedTienda = null;
    }
    
    // Si no hay seleccionada pero hay tiendas, seleccionar la primera por defecto
    if (selectedTienda == null && _tiendas.isNotEmpty) {
      selectedTienda = _tiendas.first.nombre;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_tiendas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Debe registrar al menos una tienda primero."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(
            sub == null ? "AUMENTAR LUGAR" : "EDITAR LUGAR EXACTO",
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: isUploading 
            ? const SizedBox(
                height: 150,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF00ADEF)),
                      SizedBox(height: 16),
                      Text("Subiendo foto del lugar...", style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              )
            : SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nombreController,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: const InputDecoration(
                          labelText: "Nombre del Lugar (ej: Pasillo A - Estante 3)",
                          labelStyle: TextStyle(color: Color(0xFF00ADEF)),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ADEF))),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Tienda / Depósito Asociado",
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedTienda,
                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[600]!)),
                          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ADEF))),
                        ),
                        items: _tiendas.map((t) {
                          return DropdownMenuItem<String>(
                            value: t.nombre,
                            child: Text(t.nombre),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedTienda = val;
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Foto del Lugar",
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: GestureDetector(
                          onTap: () async {
                            await showModalBottomSheet(
                              context: context,
                              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
                              builder: (bottomCtx) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.photo_library, color: Color(0xFF00ADEF)),
                                      title: Text("Galería", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                                      onTap: () async {
                                        Navigator.pop(bottomCtx);
                                        final ImagePicker picker = ImagePicker();
                                        final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                                        if (image != null) {
                                          setDialogState(() {
                                            pickedImage = image;
                                          });
                                        }
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.camera_alt, color: Color(0xFF00ADEF)),
                                      title: Text("Cámara", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                                      onTap: () async {
                                        Navigator.pop(bottomCtx);
                                        final ImagePicker picker = ImagePicker();
                                        final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
                                        if (image != null) {
                                          setDialogState(() {
                                            pickedImage = image;
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : Colors.grey[200],
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: const Color(0xFF00ADEF), width: 1),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: pickedImage != null
                                ? (kIsWeb
                                    ? Image.network(pickedImage!.path, fit: BoxFit.cover)
                                    : Image.file(File(pickedImage!.path), fit: BoxFit.cover))
                                : (currentImageName != null && currentImageName!.isNotEmpty
                                    ? Image.network(
                                        'https://novaledbolivia.com/sistema/api/uploads/$currentImageName',
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => const Icon(
                                          Icons.broken_image,
                                          color: Colors.redAccent,
                                          size: 40,
                                        ),
                                      )
                                    : const Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_a_photo, color: Color(0xFF00ADEF), size: 36),
                                          SizedBox(height: 8),
                                          Text(
                                            "Subir Foto",
                                            style: TextStyle(color: Color(0xFF00ADEF), fontSize: 11, fontWeight: FontWeight.bold),
                                          )
                                        ],
                                      )),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          actions: isUploading 
            ? [] 
            : [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00ADEF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final nombre = nombreController.text.trim();
                    if (nombre.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Debe poner un nombre de la ubicación exacta"),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }

                    if (selectedTienda == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Debe seleccionar una tienda o depósito asociado"),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }

                    setDialogState(() {
                      isUploading = true;
                    });

                    String? uploadedImageName = currentImageName;
                    if (pickedImage != null) {
                      try {
                        final bytes = await pickedImage!.readAsBytes();
                        final result = await SyncService.instance.uploadImageToHostinger(bytes, pickedImage!.name);
                        if (result != null) {
                          uploadedImageName = result;
                        }
                      } catch (e) {
                        debugPrint("Error subiendo foto de sub-ubicación: $e");
                      }
                    }

                    final newSub = SubUbicacion(
                      id: sub?.id,
                      nombre: nombre,
                      tiendaNombre: selectedTienda!,
                      folderId: sub?.folderId,
                      imagen: uploadedImageName,
                    );

                    if (sub == null) {
                      await DatabaseHelper.instance.insertSubUbicacion(newSub.toMap());
                    } else {
                      await DatabaseHelper.instance.updateSubUbicacion(newSub.toMap());
                    }

                    if (mounted) {
                      Navigator.pop(context);
                      _loadData();
                      _syncEverything(silent: true);
                    }
                  },
                  child: Text(
                    sub == null ? "CREAR" : "GUARDAR",
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final bool isWide = size.width >= 950;

    Widget bodyWidget = _isLoading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00ADEF)))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.hideAppBar) ...[
                  Text(
                    "Configuración de Almacenamiento",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildTiendasCard(isDark)),
                      const SizedBox(width: 24),
                      Expanded(child: _buildLugaresCard(isDark)),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildTiendasCard(isDark),
                      const SizedBox(height: 24),
                      _buildLugaresCard(isDark),
                    ],
                  ),
              ],
            ),
          );

    if (widget.hideAppBar) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: bodyWidget,
      );
    } else {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.grey[50],
        appBar: AppBar(
          title: const Text("CONFIGURACIÓN DE ALMACENAMIENTO", style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          actions: const [],
        ),
        body: bodyWidget,
      );
    }
  }

  Widget _buildTiendasCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131A26) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Tiendas y Depósitos",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 14, color: Colors.black),
                label: const Text(
                  "Aumentar Tienda",
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00ADEF),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showTiendaDialog(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _tiendas.isEmpty
              ? Container(
                  height: 100,
                  alignment: Alignment.center,
                  child: const Text("No hay tiendas registradas", style: TextStyle(color: Colors.grey, fontSize: 13)),
                )
              : Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(3),
                    2: FixedColumnWidth(90),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                      ),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(bottom: 10.0),
                          child: Text("Tienda", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                        ),
                        Padding(
                          padding: EdgeInsets.only(bottom: 10.0),
                          child: Text("Depósito", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                        ),
                        Padding(
                          padding: EdgeInsets.only(bottom: 10.0),
                          child: Text("Acciones", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                    for (var t in _tiendas)
                      TableRow(
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                            child: Text(
                              t.nombre,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                            child: Text(
                              t.ubicacion.isEmpty ? "-" : t.ubicacion,
                              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Color(0xFF00ADEF), size: 18),
                                  onPressed: () => _showTiendaDialog(tienda: t),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                        title: const Text("¿Eliminar Tienda?"),
                                        content: const Text("Esto eliminará la tienda y sus asociaciones."),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("CANCELAR")),
                                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("ELIMINAR", style: TextStyle(color: Colors.red))),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await DatabaseHelper.instance.deleteTienda(t.id!);
                                      _loadData();
                                      _syncEverything(silent: true);
                                    }
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildLugaresCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131A26) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Lugares Exactos / Sub-ubicaciones",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 14, color: Colors.black),
                label: const Text(
                  "Aumentar Lugar",
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00ADEF),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showSubUbicacionDialog(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _subUbicaciones.isEmpty
              ? Container(
                  height: 100,
                  alignment: Alignment.center,
                  child: const Text("No hay lugares exactos registrados", style: TextStyle(color: Colors.grey, fontSize: 13)),
                )
              : Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3.5),
                    1: FlexColumnWidth(2.5),
                    2: FixedColumnWidth(90),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                      ),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(bottom: 10.0),
                          child: Text("Lugar", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                        ),
                        Padding(
                          padding: EdgeInsets.only(bottom: 10.0),
                          child: Text("Tienda", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                        ),
                        Padding(
                          padding: EdgeInsets.only(bottom: 10.0),
                          child: Text("Acciones", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                    for (var sub in _subUbicaciones)
                      TableRow(
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white10 : Colors.black12,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: sub.imagen != null && sub.imagen!.isNotEmpty
                                      ? Image.network(
                                          'https://novaledbolivia.com/sistema/api/uploads/${sub.imagen}',
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, size: 16, color: Colors.grey),
                                        )
                                      : const Icon(Icons.image, size: 16, color: Colors.grey),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    sub.nombre,
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: Text(
                              sub.tiendaNombre,
                              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Color(0xFF00ADEF), size: 18),
                                  onPressed: () => _showSubUbicacionDialog(sub: sub),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                        title: const Text("¿Eliminar Lugar Exacto?"),
                                        content: Text("¿Está seguro de eliminar '${sub.nombre}'?"),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("CANCELAR")),
                                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("ELIMINAR", style: TextStyle(color: Colors.red))),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await DatabaseHelper.instance.deleteSubUbicacion(sub.id!);
                                      _loadData();
                                      _syncEverything(silent: true);
                                    }
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ],
      ),
    );
  }
}
