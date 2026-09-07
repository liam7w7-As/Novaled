import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import 'product_model.dart';
import 'drive_service.dart';
import 'login_screen.dart';
import 'dart:convert';
import 'dart:math';
import 'local_module/database_helper.dart';

class AddArtScreen extends StatefulWidget {
  final Product? product;
  final bool? isCatalog;
  const AddArtScreen({super.key, this.product, this.isCatalog});

  @override
  State<AddArtScreen> createState() => _AddArtScreenState();
}

class _AddArtScreenState extends State<AddArtScreen> {
  final _drive = DriveService();
  late TextEditingController _tituloController;
  late TextEditingController _precioController;
  late TextEditingController _precioCajaController;
  late TextEditingController _cantController;
  late TextEditingController _detallesController;
  late TextEditingController _tiendaController;
  late TextEditingController _cajaController;
  late TextEditingController _wattsController;
  late TextEditingController _marcaController;
  late TextEditingController _familiaController;
  late TextEditingController _subcategoriaController;
  
  final _anchoController = TextEditingController();
  final _altoController = TextEditingController();
  final _grosorController = TextEditingController();
  final _diametroController = TextEditingController();
  String _unit = 'cm';

  String? _selectedFamilia;
  String? _selectedSubcat;
  bool _isSaving = false;
  List<XFile> _images = [];
  XFile? _pendingFinalArt;
  String? _verificadoPor;
  Set<String> _camposModificados = {};

  final session = Session();

  Map<String, List<String>> _categoryMap = {
    "ILUMINACIÓN": ["FOCOS", "PANELES", "CINTAS", "REFLECTORES"],
    "HERRAMIENTAS": ["TALADROS", "MARTILLOS"],
    "CABLES": ["CABLE UTP", "CABLE ELÉCTRICO"],
  };
  List<String> _imageIds = [];
  bool _isLoadingImages = false;

  List<String> _unidades = ["Unidad"];
  String _seleccionUnidad = "Unidad";
  bool _guardarEnInventario = false;

  void _onReorderDriveImages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final String item = _imageIds.removeAt(oldIndex);
      _imageIds.insert(newIndex, item);
    });
  }

  void _onReorderLocalImages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final XFile item = _images.removeAt(oldIndex);
      _images.insert(newIndex, item);
    });
  }

  @override
  void initState() {
    super.initState();
    _normalizeLocalMap();
    _loadConfig();
    _loadUnidades();
    _tituloController = TextEditingController(text: widget.product?.titulo ?? '');
    _precioController = TextEditingController(text: widget.product?.precio ?? '');
    _precioCajaController = TextEditingController(
      text: widget.product != null && widget.product!.precioCaja > 0 
          ? widget.product!.precioCaja.toString() 
          : ''
    );
    _cantController = TextEditingController(
      text: widget.product != null 
          ? widget.product!.cantidad.toString() 
          : '1'
    );
    _detallesController = TextEditingController(text: widget.product?.detalles ?? '');
    _tiendaController = TextEditingController(text: widget.product?.codTienda ?? '');
    final String initialCaja = (widget.product?.codCaja != null && widget.product!.codCaja.trim().isNotEmpty)
        ? widget.product!.codCaja
        : "BOX-${Random().nextInt(900000) + 100000}";
    _cajaController = TextEditingController(text: initialCaja);
    _wattsController = TextEditingController(text: widget.product?.watts ?? '');
    _marcaController = TextEditingController(text: widget.product?.marca ?? '');
    _familiaController = TextEditingController(text: widget.product?.familia ?? '');
    _subcategoriaController = TextEditingController(text: widget.product?.subcategoria ?? '');
    
    _seleccionUnidad = widget.product != null && widget.product!.unidad.isNotEmpty 
        ? widget.product!.unidad 
        : 'Unidad';
        
    _guardarEnInventario = true;

    if (widget.product != null) {
      _anchoController.text = widget.product!.medidas['Ancho']?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '';
      _altoController.text = widget.product!.medidas['Alto']?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '';
      _grosorController.text = widget.product!.medidas['Grosor']?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '';
      _diametroController.text = widget.product!.medidas['Diametro']?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '';
      _selectedFamilia = widget.product!.familia.toUpperCase();
      _selectedSubcat = widget.product!.subcategoria.toUpperCase();
      _camposModificados = Set<String>.from(widget.product!.camposModificados);
      _verificadoPor = widget.product!.verificadoPor;
      if (widget.product!.medidas.values.any((v) => v.contains(' m'))) _unit = 'm';
      _loadProductImages();
    }

    _tituloController.addListener(_detectarCambios);
    _precioController.addListener(_detectarCambios);
    _precioCajaController.addListener(_detectarCambios);
    _cantController.addListener(_detectarCambios);
    _detallesController.addListener(_detectarCambios);
    _tiendaController.addListener(_detectarCambios);
    _cajaController.addListener(_detectarCambios);
    _wattsController.addListener(_detectarCambios);
    _marcaController.addListener(_detectarCambios);
    _familiaController.addListener(_detectarCambios);
    _subcategoriaController.addListener(_detectarCambios);
    _anchoController.addListener(_detectarCambios);
    _altoController.addListener(_detectarCambios);
    _grosorController.addListener(_detectarCambios);
    _diametroController.addListener(_detectarCambios);
  }

  Future<void> _loadUnidades() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final rawUnits = await dbHelper.queryAllUnidadesMedida();
      final List<String> unitNames = rawUnits.map((u) => u['nombre']?.toString() ?? '').where((name) => name.isNotEmpty).toList();
      
      setState(() {
        _unidades = unitNames;
        if (widget.product != null && widget.product!.unidad.isNotEmpty) {
          if (!_unidades.contains(widget.product!.unidad)) {
            _unidades.add(widget.product!.unidad);
          }
          _seleccionUnidad = widget.product!.unidad;
        } else if (_unidades.isNotEmpty && !_unidades.contains(_seleccionUnidad)) {
          _seleccionUnidad = _unidades.first;
        }
      });
    } catch (e) {
      debugPrint("Error loading units: $e");
    }
  }

  void _detectarCambios() {
    if (widget.product == null) return;
    final p = widget.product!;
    final nuevosCampos = <String>{};

    if (_tituloController.text.trim() != p.titulo.trim()) nuevosCampos.add("Título");
    if (_precioController.text.trim() != p.precio.trim()) nuevosCampos.add("Precio");
    if (_precioCajaController.text.trim() != p.precioCaja.toString()) nuevosCampos.add("Precio Caja");
    if (_cantController.text.trim() != p.cantidad.toString()) nuevosCampos.add("Cantidad");
    if (_detallesController.text.trim() != p.detalles.trim()) nuevosCampos.add("Descripción");
    if (_tiendaController.text.trim() != p.codTienda.trim()) nuevosCampos.add("Cód. Tienda");
    if (_cajaController.text.trim() != p.codCaja.trim()) nuevosCampos.add("Cód. Caja");
    if (_wattsController.text.trim() != p.watts.trim()) nuevosCampos.add("Watts");
    if (_marcaController.text.trim() != p.marca.trim()) nuevosCampos.add("Marca");

    if ('${_anchoController.text} $_unit'.trim() != (p.medidas['Ancho'] ?? '').trim()) nuevosCampos.add("Ancho");
    if ('${_altoController.text} $_unit'.trim() != (p.medidas['Alto'] ?? '').trim()) nuevosCampos.add("Alto");
    if ('${_grosorController.text} $_unit'.trim() != (p.medidas['Grosor'] ?? '').trim()) nuevosCampos.add("Grosor");
    if ('${_diametroController.text} $_unit'.trim() != (p.medidas['Diametro'] ?? '').trim()) nuevosCampos.add("Diámetro");

    if (_selectedFamilia != p.familia.toUpperCase()) nuevosCampos.add("Familia");
    if (_selectedSubcat != p.subcategoria.toUpperCase()) nuevosCampos.add("Subcategoría");

    if (nuevosCampos.toString() != _camposModificados.toString()) {
      setState(() {
        _camposModificados = nuevosCampos;
        // Si hay cambios técnicos y el usuario es vendedor, anulamos la verificación previa
        if (nuevosCampos.isNotEmpty) {
           _verificadoPor = null;
        }
      });
    }
  }

  void _normalizeLocalMap() {
    final Map<String, List<String>> normalized = {};
    _categoryMap.forEach((k, v) {
      String key = k.trim().toUpperCase();
      List<String> values = v.map((e) => e.trim().toUpperCase()).toSet().toList();
      normalized[key] = values;
    });
    setState(() => _categoryMap = normalized);
  }

  Future<void> _loadConfig() async {
    try {
      await _drive.authenticate();
      final config = await _drive.getConfig();
      if (config.isNotEmpty) {
        _categoryMap = config;
        _normalizeLocalMap();
      }
    } catch (e) { debugPrint("Error config: $e"); }
  }

  Future<void> _loadProductImages() async {
    if (widget.product?.folderId == null) return;
    setState(() => _isLoadingImages = true);
    
    // Si el producto ya tiene imageIds guardados en su data.json, los usamos primero
    if (widget.product!.imageIds.isNotEmpty) {
      _imageIds = List.from(widget.product!.imageIds);
      setState(() => _isLoadingImages = false);
      // Opcionalmente podemos verificar si siguen existiendo o si hay nuevas en segundo plano
    } else {
      final ids = await _drive.getProductImages(widget.product!.folderId!);
      setState(() { _imageIds = ids; _isLoadingImages = false; });
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Cámara'), onTap: () => Navigator.pop(context, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galería'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ],
        ),
      ),
    );
    
    if (source != null) {
      if (source == ImageSource.gallery) {
        final picked = await picker.pickMultiImage();
        if (picked.isNotEmpty) setState(() => _images.addAll(picked));
      } else {
        final picked = await picker.pickImage(source: ImageSource.camera);
        if (picked != null) setState(() => _images.add(picked));
      }
    }
  }

  Future<void> _pickFinalArt() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _pendingFinalArt = picked);
  }

  Future<void> _save() async {
    if (_tituloController.text.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final p = _getProductFromFields();
      p.imageIds = _imageIds; // Guardar el orden actual de Drive

      // 1. Guardar localmente en SQLite
      final dbHelper = DatabaseHelper.instance;
      final row = {
        'nombre': p.titulo,
        'precio': double.tryParse(p.precio) ?? 0.0,
        'precioCaja': p.precioCaja,
        'descripcion': p.detalles,
        'folderId': p.folderId ?? '',
        'finalArtId': p.finalArtId ?? '',
        'proveedor': p.marca,
        'codCaja': p.codCaja,
        'familia': p.familia,
        'subcategoria': p.subcategoria,
        'unidad': p.unidad,
        'unidadDetalle': p.unidadDetalle,
        'stockJson': jsonEncode({
          'isCatalog': _guardarEnInventario,
          'medidas': p.medidas,
          'imageIds': p.imageIds,
          'camposModificados': p.camposModificados,
          'general': p.cantidad,
        }),
      };

      if (widget.product == null) {
        if (p.folderId == null || p.folderId!.isEmpty) {
          final rand = Random().nextInt(1000000);
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          p.folderId = 'ARTICULOS_${timestamp}_$rand';
          row['folderId'] = p.folderId!;
        }
        await dbHelper.insertRecord('articulos', row);
      } else {
        final localId = await dbHelper.findMatchingLocalId('articulos', {'folderId': p.folderId});
        if (localId != null) {
          row['id'] = localId;
          await dbHelper.updateRecord('articulos', row);
        } else {
          await dbHelper.insertRecord('articulos', row);
        }
      }

      // 2. Intentar guardar en Drive asíncronamente como respaldo si está conectado
      try {
        final connected = await _drive.authenticate(forceSignIn: false);
        if (connected && _drive.driveApi != null) {
          if (widget.product == null) {
            await _drive.createProduct(p, _images);
          } else {
            if (_pendingFinalArt != null) {
              await _drive.uploadFinalArt(_pendingFinalArt!, p);
              if (_images.isNotEmpty) await _drive.updateProduct(p, _images);
            } else {
              await _drive.updateProduct(p, _images);
            }
          }
        }
      } catch (driveErr) {
        debugPrint("Aviso: Falló el respaldo a Google Drive: $driveErr");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Datos actualizados con éxito"), backgroundColor: Color(0xFF00ADEF))
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Product _getProductFromFields() {
    String nuevoEstado = widget.product?.estado ?? 'pendiente';
    List<String> campos = _camposModificados.toList();

    if (_pendingFinalArt != null || _verificadoPor != null) {
      nuevoEstado = 'listo';
      campos = [];
    } else if (_camposModificados.isNotEmpty || (widget.product != null && widget.product!.estado.trim().toLowerCase() == 'pendiente')) {
      // Si hay cambios o ya estaba pendiente, se mantiene/pasa a pendiente
      nuevoEstado = 'pendiente';
    }

    return Product(
      folderId: widget.product?.folderId,
      dataFileId: widget.product?.dataFileId,
      titulo: _tituloController.text,
      precio: _precioController.text,
      detalles: _detallesController.text,
      estado: nuevoEstado,
      familia: _familiaController.text,
      subcategoria: _subcategoriaController.text,
      codTienda: _tiendaController.text,
      codCaja: _cajaController.text,
      watts: _wattsController.text,
      marca: _marcaController.text,
      medidas: {
        'Ancho': '${_anchoController.text} $_unit',
        'Alto': '${_altoController.text} $_unit',
        'Grosor': '${_grosorController.text} $_unit',
        'Diametro': '${_diametroController.text} $_unit',
      },
      finalArtId: widget.product?.finalArtId,
      infoDocId: widget.product?.infoDocId,
      verificadoPor: _verificadoPor,
      camposModificados: campos,
      fecha: (widget.product?.fecha != null && widget.product!.fecha.isNotEmpty) 
          ? widget.product!.fecha 
          : DateTime.now().toIso8601String(),
      precioCaja: double.tryParse(_precioCajaController.text) ?? 0.0,
      cantidad: int.tryParse(_cantController.text) ?? 0,
      unidad: _seleccionUnidad,
      unidadDetalle: widget.product?.unidadDetalle ?? "",
    );
  }

  // --- GESTIÓN DE CATEGORÍAS ---

  void _showCategoryDialog({required bool isFamilia, String? oldName}) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(oldName == null ? "Añadir ${isFamilia ? 'Familia' : 'Subcategoría'}" : "Editar"),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: "Nombre")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () {
              String name = controller.text.trim().toUpperCase();
              if (name.isEmpty) return;
              
              setState(() {
                if (isFamilia) {
                  if (oldName == null) {
                    _categoryMap[name] = [];
                    _selectedFamilia = name; // Selección automática del nuevo
                    _selectedSubcat = null;  // Reset subcat al cambiar familia
                  } else {
                    final sub = _categoryMap.remove(oldName);
                    _categoryMap[name] = sub ?? [];
                    if (_selectedFamilia == oldName) _selectedFamilia = name;
                  }
                } else {
                  if (_selectedFamilia != null) {
                    if (oldName == null) {
                      _categoryMap[_selectedFamilia]!.add(name);
                      _selectedSubcat = name; // Selección automática del nuevo
                    } else {
                      int idx = _categoryMap[_selectedFamilia]!.indexOf(oldName);
                      if (idx != -1) _categoryMap[_selectedFamilia]![idx] = name;
                      if (_selectedSubcat == oldName) _selectedSubcat = name;
                    }
                  }
                }
              });

              // 1. Cerramos el diálogo inmediatamente para que no haya lag
              Navigator.pop(c);

              // 2. Guardamos en Drive en segundo plano
              _drive.saveConfig(_categoryMap).catchError((e) => debugPrint("Error config: $e"));
              
              // 3. Notificar cambios al modelo
              _detectarCambios();
            },
            child: const Text("GUARDAR"),
          ),
        ],
      ),
    );
  }

  void _deleteCategory(bool isFamilia) {
    if (isFamilia && _selectedFamilia == null) return;
    if (!isFamilia && _selectedSubcat == null) return;

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("¿Eliminar?"),
        content: Text("Se borrará la ${isFamilia ? 'Familia y todas sus subcategorías' : 'Subcategoría'}: ${isFamilia ? _selectedFamilia : _selectedSubcat}"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("CANCELAR")),
          TextButton(
            onPressed: () async {
              setState(() {
                if (isFamilia) {
                  _categoryMap.remove(_selectedFamilia);
                  _selectedFamilia = null;
                  _selectedSubcat = null;
                } else {
                  _categoryMap[_selectedFamilia]!.remove(_selectedSubcat);
                  _selectedSubcat = null;
                }
              });
              await _drive.saveConfig(_categoryMap);
              if (mounted) Navigator.pop(c);
            },
            child: const Text("ELIMINAR", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isEdit = widget.product != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF0B0C10) : Colors.grey[50]!;



    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF161A22) : Colors.white,
        elevation: 2,
        title: Text(isEdit ? "Editar Artículo" : "Añadir Artículo", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          if (isEdit && (session.isAdmin || session.isDesigner))
            _buildDriveActionButton(),
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text("⚠️ ¿ELIMINAR ESTE PRODUCTO?"),
                    content: const Text("Esta acción borrará permanentemente el producto y todos sus archivos de Google Drive."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("CANCELAR")),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true), 
                        child: const Text("SÍ, BORRAR", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  setState(() => _isSaving = true);
                  try {
                    await _drive.deleteFile(widget.product!.folderId!);
                    if (mounted) Navigator.pop(context, true);
                  } catch (e) {
                    setState(() => _isSaving = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al borrar: $e")));
                  }
                }
              },
            ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00ADEF))),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check_rounded, color: Color(0xFF00ADEF), size: 28),
              onPressed: _save,
              tooltip: "Guardar Artículo",
            ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_camposModificados.isNotEmpty && widget.product?.estado.trim().toLowerCase() == 'listo')
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Cambios detectados en: ${_camposModificados.join(', ')}. El estado pasará a PENDIENTE hasta subir un nuevo arte.",
                          style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  const Icon(Icons.inventory_2, color: Color(0xFF00ADEF), size: 24),
                  const SizedBox(width: 10),
                  Text(
                    "Detalles del Producto",
                    style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Divider(height: 30, color: isDark ? Colors.white10 : Colors.black12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _pickImages,
                    child: Stack(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1F1F1F) : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF00ADEF), width: 1.5),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _images.isNotEmpty
                              ? FutureBuilder<Uint8List>(
                                  future: _images.first.readAsBytes(),
                                  builder: (context, snapshot) => snapshot.hasData
                                      ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                                      : const Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
                                )
                              : (_imageIds.isNotEmpty)
                                  ? FutureBuilder<Uint8List?>(
                                      future: _drive.getFileThumbnail(_imageIds.first),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState == ConnectionState.waiting) {
                                          return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
                                        }
                                        final thumb = snapshot.data;
                                        return thumb != null
                                            ? Image.memory(thumb, fit: BoxFit.cover)
                                            : const Icon(Icons.broken_image, color: Colors.grey, size: 20);
                                      },
                                    )
                                  : const Icon(Icons.add_a_photo_rounded, color: Color(0xFF00ADEF), size: 20),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xFF00ADEF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, color: Colors.black, size: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField("Nombre del Producto", _tituloController, TextInputType.text),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildField("Precio (Bs)", _precioController, TextInputType.number)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildField("Precio Caja (Bs)", _precioCajaController, TextInputType.number)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildField("Cantidad", _cantController, TextInputType.number)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: _mostrarSelectorUnidades,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: "Unidad de Medida",
                          labelStyle: const TextStyle(color: Color(0xFF00ADEF), fontSize: 12),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.grey : Colors.grey[400]!)),
                          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ADEF))),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _seleccionUnidad,
                                style: TextStyle(color: textColor, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: Color(0xFF00ADEF),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildField("Categoría/Familia", _familiaController, TextInputType.text)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildField("Subcategoría", _subcategoriaController, TextInputType.text)),
                ],
              ),
              const SizedBox(height: 16),
              _buildField("Descripción", _detallesController, TextInputType.multiline, maxLines: 4),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildField("Watts", _wattsController, TextInputType.text)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildField("Marca/Proveedor", _marcaController, TextInputType.text)),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("MEDIDAS (cm/m)", style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildMeasureField(_anchoController, "Ancho")),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMeasureField(_altoController, "Alto")),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMeasureField(_grosorController, "Grosor")),
                        const SizedBox(width: 8),
                        Expanded(child: _buildMeasureField(_diametroController, "Diámetro")),
                      ],
                    ),
                  ],
                ),
              ),

              _buildImagePickerSection(),
              if (isEdit) ...[
                const SizedBox(height: 20),
                _buildDriveGallery(),
                const SizedBox(height: 20),
                if (session.isAdmin || session.isDesigner) _buildFinalArtSection(),
                if (session.isAdmin || session.isSeller) ...[
                  const SizedBox(height: 20),
                  _buildSellerVerificationSection(),
                ],
              ],
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00ADEF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isSaving ? null : _save,
                  child: Text(
                    isEdit ? "GUARDAR CAMBIOS" : "AGREGAR ARTÍCULO",
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, TextInputType type, {int maxLines = 1}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      keyboardType: type,
      maxLines: maxLines,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF00ADEF), fontSize: 12),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.grey : Colors.grey[400]!)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ADEF))),
        isDense: true,
      ),
    );
  }

  Widget _buildMeasureField(TextEditingController c, String l) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: l,
        labelStyle: const TextStyle(fontSize: 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 5),
        border: const UnderlineInputBorder(),
      ),
    );
  }

  void _mostrarSelectorUnidades() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E222B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final textColor = isDark ? Colors.white : Colors.black87;
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "UNIDADES DE MEDIDA",
                        style: TextStyle(
                          color: Color(0xFF00ADEF),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, color: Color(0xFF00ADEF)),
                        onPressed: () async {
                          final nuevo = await _mostrarDialogoNuevaUnidad();
                          if (nuevo != null && nuevo.isNotEmpty) {
                            final dbHelper = DatabaseHelper.instance;
                            await dbHelper.insertUnidadMedida({'nombre': nuevo});
                            await _loadUnidades();
                            setModalState(() {});
                          }
                        },
                        tooltip: "Agregar Unidad",
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _unidades.length,
                      itemBuilder: (context, index) {
                        final u = _unidades[index];
                        return ListTile(
                          dense: true,
                          title: Text(u, style: TextStyle(color: textColor, fontSize: 14)),
                          onTap: () {
                            setState(() {
                              _seleccionUnidad = u;
                            });
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _mostrarDialogoNuevaUnidad() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
          title: Text("Nueva Unidad de Medida", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: "Ej: Litros, Paquete...",
              hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
            TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text("CREAR", style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTicketMedidas() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        const Text("MEDIDAS", style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold, fontSize: 12)),
        Row(children: [
          Expanded(child: TextField(controller: _anchoController, style: TextStyle(color: isDark ? Colors.white : Colors.black87), decoration: const InputDecoration(labelText: "Ancho"))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _altoController, style: TextStyle(color: isDark ? Colors.white : Colors.black87), decoration: const InputDecoration(labelText: "Alto"))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _grosorController, style: TextStyle(color: isDark ? Colors.white : Colors.black87), decoration: const InputDecoration(labelText: "Grosor"))),
        ]),
      ]),
    );
  }

  Widget _buildImagePickerSection() {
    return Column(children: [
      OutlinedButton.icon(onPressed: _pickImages, icon: const Icon(Icons.add_a_photo), label: const Text("AÑADIR FOTOS PRODUCTO")),
      const SizedBox(height: 10),
      if (_images.isNotEmpty)
        SizedBox(
          height: 120,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length,
            onReorder: _onReorderLocalImages,
            itemBuilder: (context, i) => Stack(
              key: ValueKey(_images[i].path),
              children: [
                FutureBuilder<Uint8List>(
                  future: _images[i].readAsBytes(),
                  builder: (context, snapshot) => snapshot.hasData 
                    ? Padding(padding: const EdgeInsets.only(right: 8), child: Image.memory(snapshot.data!, width: 100, height: 100, fit: BoxFit.cover))
                    : Container(width: 100, color: Colors.white10),
                ),
                Positioned(
                  right: 12, top: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _images.removeAt(i)),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
    ]);
  }

  Widget _buildDriveGallery() {
    if (_isLoadingImages) return const LinearProgressIndicator();
    if (_imageIds.isEmpty) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("FOTOS EN DRIVE (Arrastra para reordenar)", style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 10),
      SizedBox(
        height: 100,
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _imageIds.length,
          onReorder: _onReorderDriveImages,
          itemBuilder: (context, i) => Stack(
            key: ValueKey(_imageIds[i]),
            children: [
              FutureBuilder<Uint8List?>(
                future: _drive.getFileThumbnail(_imageIds[i]),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      width: 80, height: 80, margin: const EdgeInsets.only(right: 8),
                      color: Colors.white10,
                      child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                    );
                  }
                  final thumb = snapshot.data;
                  return GestureDetector(
                    onTap: () => _showImagePreview(_imageIds[i], thumb),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: thumb != null 
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: (_imageIds[i] == widget.product?.finalArtId)
                              ? Transform.scale(
                                  scale: 2.3,
                                  alignment: const Alignment(-0.15, -0.42),
                                  child: Image.memory(thumb, width: 80, height: 80, fit: BoxFit.cover),
                                )
                              : Image.memory(thumb, width: 80, height: 80, fit: BoxFit.cover),
                          )
                        : Container(width: 80, height: 80, color: Colors.white10, child: const Icon(Icons.image, color: Colors.white24)),
                    ),
                  );
                },
              ),
              Positioned(
                right: 10, top: 2,
                child: GestureDetector(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text("⚠️ ¿ELIMINAR FOTO?"),
                        content: const Text("Se borrará permanentemente de Google Drive."),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("CANCELAR")),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true), 
                            child: const Text("ELIMINAR", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _drive.deleteImageFromProduct(_imageIds[i], widget.product!.folderId!);
                      setState(() => _imageIds.removeAt(i));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.delete, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      )
    ]);
  }


  void _showImagePreview(String fileId, Uint8List? thumb) {
    Uint8List? displayBytes = thumb;
    bool isHighResLoading = true;
    bool hasStartedLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!hasStartedLoading) {
              hasStartedLoading = true;
              _drive.getFileBytes(fileId).then((bytes) {
                if (bytes.isNotEmpty && mounted) {
                  setDialogState(() {
                    displayBytes = Uint8List.fromList(bytes);
                    isHighResLoading = false;
                  });
                }
              });
            }

            return Dialog.fullscreen(
              backgroundColor: Colors.black,
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      child: displayBytes != null 
                        ? Image.memory(displayBytes!, fit: BoxFit.contain)
                        : const CircularProgressIndicator(),
                    ),
                  ),
                  if (isHighResLoading)
                    Positioned(
                      top: 100, left: 0, right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF00ADEF), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00ADEF))),
                              SizedBox(width: 10),
                              Text("Cargando alta resolución...", style: TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Positioned(top: 40, left: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context))),
                  Positioned(
                    bottom: 40, left: 0, right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _previewActionButton(Icons.download, "Guardar", () async {
                          Directory? directory;
                          if (Platform.isAndroid) {
                            directory = Directory('/storage/emulated/0/Download');
                            if (!await directory.exists()) directory = await getExternalStorageDirectory();
                          } else {
                            directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
                          }
                          
                          if (displayBytes != null && directory != null) {
                            final file = File('${directory.path}/IMG_${DateTime.now().millisecondsSinceEpoch}.jpg');
                            await file.writeAsBytes(displayBytes!);
                            if(mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text("✅ Imagen guardada en ${directory.path.split('/').last}"),
                                backgroundColor: const Color(0xFF00ADEF),
                              ));
                            }
                          }
                        }),
                        _previewActionButton(Icons.share, "Enviar", () async {
                          final tempDir = await getTemporaryDirectory();
                          if (displayBytes != null) {
                            final file = File('${tempDir.path}/share_temp.jpg');
                            await file.writeAsBytes(displayBytes!);
                            await Share.shareXFiles([XFile(file.path)]);
                          }
                        }),
                      ],
                    ),
                  )
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _previewActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      FloatingActionButton(heroTag: label, backgroundColor: const Color(0xFF00ADEF), onPressed: onTap, child: Icon(icon, color: Colors.white)),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildFinalArtSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFF00ADEF).withOpacity(0.3)), borderRadius: BorderRadius.circular(15)),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("ARTE FINAL", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00ADEF))),
            _buildDriveShortcut(),
          ],
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(onPressed: _pickFinalArt, icon: const Icon(Icons.cloud_upload), label: const Text("CARGAR ARTE")),
        if (_pendingFinalArt != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text("Pendiente: ${_pendingFinalArt!.name}", style: const TextStyle(color: Colors.orange, fontSize: 11))),
      ]),
    );
  }

  Widget _buildDriveActionButton() {
    return Container(
      margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: InkWell(
        onTap: () async {
          if (widget.product?.folderId == null) return;
          final url = Uri.parse("https://drive.google.com/drive/folders/${widget.product!.folderId}");
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF00ADEF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_outlined, color: Colors.white, size: 20),
              Text("DRIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriveShortcut() {
    return InkWell(
      onTap: () async {
        if (widget.product?.folderId == null) return;
        final url = Uri.parse("https://drive.google.com/drive/folders/${widget.product!.folderId}");
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF00ADEF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_outlined, color: Colors.white, size: 28),
            Text("DRIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerVerificationSection() {
    bool isVerificado = _verificadoPor != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final phosphorGreen = isDark ? const Color(0xFFCCFF00) : const Color(0xFF2E7D32);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isVerificado ? phosphorGreen.withOpacity(0.1) : Colors.transparent,
        border: Border.all(color: isVerificado ? phosphorGreen : Colors.orange.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(15)
      ),
      child: Column(children: [
        Text(isVerificado ? "PRODUCTO VERIFICADO" : "VERIFICACIÓN DE DATOS", 
          style: TextStyle(fontWeight: FontWeight.bold, color: isVerificado ? phosphorGreen : Colors.orange)),
        const SizedBox(height: 10),
        if (isVerificado)
          InkWell(
            onTap: () {
               setState(() => _verificadoPor = null);
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text("Verificación anulada. El producto volverá a su estado inicial."))
               );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: phosphorGreen),
                const SizedBox(width: 8),
                Text("POR: $_verificadoPor", style: TextStyle(fontWeight: FontWeight.w900, color: phosphorGreen)),
                const SizedBox(width: 10),
                const Icon(Icons.close, size: 14, color: Colors.redAccent),
              ],
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: () {
              setState(() => _verificadoPor = session.userName);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Marcado como verificado por ${session.userName}. Guarde para confirmar."))
              );
            }, 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            icon: const Icon(Icons.fact_check), 
            label: const Text("MARCAR COMO LISTO (TICKET)")
          ),
      ]),
    );
  }
}
