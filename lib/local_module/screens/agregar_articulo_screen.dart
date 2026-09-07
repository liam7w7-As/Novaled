import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../database_helper.dart';
import '../models/articulo.dart';
import '../models/item_cotizacion.dart';
import '../../drive_service.dart';
import '../services/sync_service.dart';

class AgregarArticuloScreen extends StatefulWidget {
  final ItemCotizacion? itemAEditar;
  const AgregarArticuloScreen({super.key, this.itemAEditar});

  @override
  State<AgregarArticuloScreen> createState() => _AgregarArticuloScreenState();
}

class _AgregarArticuloScreenState extends State<AgregarArticuloScreen> {
  List<Articulo> _articulos = [];
  bool _isLoading = true;
  String _filtro = "";

  // Form controllers
  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _cantCtrl = TextEditingController(text: "1");
  final _descCtrl = TextEditingController();
  final _unidadDetalleCtrl = TextEditingController();

  List<String> _unidades = [];
  String _seleccionUnidad = "Unidad";
  final DriveService _drive = DriveService();

  bool _showSuggestions = false;
  Articulo? _selectedArticulo;

  final _nombreFocusNode = FocusNode();
  List<Articulo> _topArticulos = [];

  XFile? _pickedImage;
  String? _imagenFilename;
  final ImagePicker _picker = ImagePicker();
  bool _guardarEnInventario = true;

  @override
  void initState() {
    super.initState();
    _loadArticulos();
    _loadUnidades();
    _nombreFocusNode.addListener(_onNombreFocusChange);

    if (widget.itemAEditar != null) {
      final item = widget.itemAEditar!;
      if (item.articulo.id != null) {
        _selectedArticulo = item.articulo;
      }
      _nombreCtrl.text = item.articulo.nombre;
      _precioCtrl.text = item.articulo.precio.toString();
      _cantCtrl.text = item.cantidad.toString();
      _descCtrl.text = item.articulo.descripcion;
      _unidadDetalleCtrl.text = item.articulo.unidadDetalle;
      _imagenFilename = item.articulo.imagen;

      String matchedUnit = item.articulo.unidad.isNotEmpty ? item.articulo.unidad : "Unidad";
      _seleccionUnidad = matchedUnit;

      if (item.articulo.stockJson != null && item.articulo.stockJson!.isNotEmpty) {
        try {
          final Map<String, dynamic> extra = jsonDecode(item.articulo.stockJson!);
          _guardarEnInventario = extra['isCatalog'] == true;
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _nombreFocusNode.removeListener(_onNombreFocusChange);
    _nombreFocusNode.dispose();
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    _cantCtrl.dispose();
    _descCtrl.dispose();
    _unidadDetalleCtrl.dispose();
    super.dispose();
  }

  void _onNombreFocusChange() {
    if (!_nombreFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) {
          setState(() {
            _showSuggestions = _nombreFocusNode.hasFocus;
          });
        }
      });
    } else {
      setState(() {
        _showSuggestions = true;
      });
    }
  }

  void _seleccionarImagen() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF00ADEF)),
              title: Text("Galería", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (image != null) {
                  setState(() {
                    _pickedImage = image;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF00ADEF)),
              title: Text("Cámara", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                if (image != null) {
                  setState(() {
                    _pickedImage = image;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadArticulos() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final articulosRaw = await dbHelper.queryAllArticulos();
      
      // Consultar documentos para calcular frecuencias
      final cotizaciones = await dbHelper.queryAllCotizaciones();
      final notasEntrega = await dbHelper.queryAllNotasEntrega();
      final proformas = await dbHelper.queryAllProformas();

      final Map<String, int> usageCounts = {};

      void processItemsJson(String? itemsJsonStr) {
        if (itemsJsonStr == null || itemsJsonStr.isEmpty) return;
        try {
          final List<dynamic> decoded = jsonDecode(itemsJsonStr);
          for (var itemMap in decoded) {
            final artMap = itemMap['articulo'];
            if (artMap != null) {
              final name = artMap['nombre']?.toString().toLowerCase().trim();
              if (name != null) {
                usageCounts[name] = (usageCounts[name] ?? 0) + 1;
              }
            }
          }
        } catch (e) {
          debugPrint("Error parsing itemsJson: $e");
        }
      }

      for (var doc in cotizaciones) {
        processItemsJson(doc['itemsJson'] as String?);
      }
      for (var doc in notasEntrega) {
        processItemsJson(doc['itemsJson'] as String?);
      }
      for (var doc in proformas) {
        processItemsJson(doc['itemsJson'] as String?);
      }

      final List<Articulo> allArticulos = articulosRaw.map((a) => Articulo.fromMap(a)).toList();

      // Clonar y ordenar por el número de usos descendente
      final sortedArticulos = List<Articulo>.from(allArticulos);
      sortedArticulos.sort((a, b) {
        final countA = usageCounts[a.nombre.toLowerCase().trim()] ?? 0;
        final countB = usageCounts[b.nombre.toLowerCase().trim()] ?? 0;
        return countB.compareTo(countA);
      });

      setState(() {
        _articulos = allArticulos;
        _topArticulos = sortedArticulos.take(7).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading articulos and usage stats: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUnidades() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final rawUnits = await dbHelper.queryAllUnidadesMedida();
      final List<String> unitNames = rawUnits.map((u) => u['nombre']?.toString() ?? '').where((name) => name.isNotEmpty).toList();
      
      setState(() {
        _unidades = unitNames;
        if (widget.itemAEditar != null) {
          final matchedUnit = widget.itemAEditar!.articulo.unidad.isNotEmpty ? widget.itemAEditar!.articulo.unidad : "Unidad";
          if (!_unidades.contains(matchedUnit)) {
            _unidades.add(matchedUnit);
          }
          _seleccionUnidad = matchedUnit;
        } else if (_unidades.isNotEmpty && !_unidades.contains(_seleccionUnidad)) {
          _seleccionUnidad = _unidades.first;
        }
      });
      
      // Sincronizar en segundo plano
      _syncUnidades(silent: true);
    } catch (e) {
      debugPrint("Error cargando unidades de medida: $e");
    }
  }

  Future<void> _syncUnidades({bool silent = false}) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      await dbHelper.syncUnidadesMedida(_drive);

      // Recargar la lista local
      final updatedLocalRaw = await dbHelper.queryAllUnidadesMedida();
      final List<String> updatedNames = updatedLocalRaw.map((u) => u['nombre']?.toString() ?? '').where((name) => name.isNotEmpty).toList();
      
      if (mounted) {
        setState(() {
          _unidades = updatedNames;
          if (!_unidades.contains(_seleccionUnidad)) {
            if (_unidades.isNotEmpty) {
              _seleccionUnidad = _unidades.first;
            } else {
              _seleccionUnidad = "Unidad";
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Error al sincronizar unidades de medida: $e");
    }
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
                            await _syncUnidades(silent: true);
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 18),
                                onPressed: () async {
                                  final nuevoNombre = await _mostrarDialogoEditarUnidad(u);
                                  if (nuevoNombre != null && nuevoNombre.isNotEmpty) {
                                    final dbHelper = DatabaseHelper.instance;
                                    final rawUnits = await dbHelper.queryAllUnidadesMedida();
                                    final item = rawUnits.firstWhere((element) => element['nombre'] == u, orElse: () => <String, dynamic>{});
                                    if (item.isNotEmpty) {
                                      final updated = Map<String, dynamic>.from(item);
                                      updated['nombre'] = nuevoNombre;
                                      await dbHelper.updateUnidadMedida(updated);
                                      if (updated['folderId'] != null) {
                                        await _drive.syncItemToDrive('unidades_medida', updated);
                                      }
                                      await _syncUnidades(silent: true);
                                      setModalState(() {});
                                    }
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                                      title: Text("¿Eliminar unidad?", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                                      content: Text("¿Estás seguro de que deseas eliminar la unidad '$u'?", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("CANCELAR")),
                                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("ELIMINAR", style: TextStyle(color: Colors.red))),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    final dbHelper = DatabaseHelper.instance;
                                    final rawUnits = await dbHelper.queryAllUnidadesMedida();
                                    final item = rawUnits.firstWhere((element) => element['nombre'] == u, orElse: () => <String, dynamic>{});
                                    if (item.isNotEmpty) {
                                      await dbHelper.deleteUnidadMedida(item['id']);
                                      if (item['folderId'] != null && item['folderId'].toString().isNotEmpty) {
                                        try {
                                          await _drive.deleteFile(item['folderId'].toString());
                                        } catch (e) {
                                          debugPrint("Error borrando unidad en Drive: $e");
                                        }
                                      }
                                      await _syncUnidades(silent: true);
                                      setModalState(() {});
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
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

  Future<String?> _mostrarDialogoEditarUnidad(String nombreActual) async {
    final ctrl = TextEditingController(text: nombreActual);
    return showDialog<String>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
          title: Text("Editar Unidad de Medida", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: "Nombre de Unidad",
              labelStyle: const TextStyle(color: Color(0xFF00ADEF)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
            TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text("GUARDAR", style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompactEditField(TextEditingController ctrl, String label, {bool isNumber = false, String? hintText, void Function(String)? onChanged}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      onChanged: onChanged,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: const Color(0xFF00ADEF), fontSize: isDark ? 11 : 12),
        hintText: hintText,
        hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 13),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12), borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00ADEF)), borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: isDark ? Colors.black38 : Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      ),
    );
  }

  Widget _buildTopSuggestions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          "Productos frecuentes:",
          style: TextStyle(
            color: Color(0xFF00ADEF),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _topArticulos.map((a) {
            return InkWell(
              onTap: () {
                final cantidad = int.tryParse(_cantCtrl.text.trim()) ?? 1;
                final item = ItemCotizacion(
                  articulo: a,
                  precioOriginal: a.precio,
                  cantidad: cantidad <= 0 ? 1 : cantidad,
                );
                Navigator.pop(context, [item]);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E222B) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.trending_up,
                      size: 14,
                      color: Color(0xFF00ADEF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      a.nombre,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "${a.precio.toStringAsFixed(0)} Bs",
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _guardarArticulo() async {
    if (_nombreCtrl.text.trim().isEmpty) return;
    double precioEditado = double.tryParse(_precioCtrl.text) ?? 0.0;
    int cantidad = int.tryParse(_cantCtrl.text) ?? 1;

    setState(() => _isLoading = true);

    try {
      String? uploadFilename = _imagenFilename;
      if (_pickedImage != null) {
        final bytes = await _pickedImage!.readAsBytes();
        final uploaded = await SyncService.instance.uploadImageToHostinger(bytes, _pickedImage!.name);
        if (uploaded != null) {
          uploadFilename = uploaded;
        }
      }

      // Construir stockJson Map
      Map<String, dynamic> stockJsonMap = {};
      if (_selectedArticulo?.stockJson != null && _selectedArticulo!.stockJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(_selectedArticulo!.stockJson!);
          if (decoded is Map) {
            stockJsonMap = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }

      stockJsonMap['isCatalog'] = _guardarEnInventario;
      stockJsonMap['general'] = cantidad;

      final newArt = Articulo(
        id: _selectedArticulo?.id ?? widget.itemAEditar?.articulo.id,
        nombre: _nombreCtrl.text.trim(),
        precio: precioEditado,
        descripcion: _descCtrl.text.trim(),
        unidad: _seleccionUnidad,
        unidadDetalle: _unidadDetalleCtrl.text.trim(),
        imagen: uploadFilename,
        stockJson: jsonEncode(stockJsonMap),
        folderId: _selectedArticulo?.folderId ?? widget.itemAEditar?.articulo.folderId,
        finalArtId: _selectedArticulo?.finalArtId ?? widget.itemAEditar?.articulo.finalArtId,
        proveedor: _selectedArticulo?.proveedor ?? widget.itemAEditar?.articulo.proveedor ?? 'Novaled',
        familia: _selectedArticulo?.familia ?? widget.itemAEditar?.articulo.familia ?? '',
        subcategoria: _selectedArticulo?.subcategoria ?? widget.itemAEditar?.articulo.subcategoria ?? '',
        fecha: _selectedArticulo?.fecha != null && _selectedArticulo!.fecha.isNotEmpty
            ? _selectedArticulo!.fecha
            : (widget.itemAEditar?.articulo.fecha != null && widget.itemAEditar!.articulo.fecha.isNotEmpty
                ? widget.itemAEditar!.articulo.fecha
                : DateTime.now().toIso8601String().substring(0, 10)),
      );

      // Guardar localmente
      int savedId;
      if (newArt.id == null) {
        savedId = await DatabaseHelper.instance.insertArticulo(newArt.toMap());
      } else {
        savedId = newArt.id!;
        await DatabaseHelper.instance.updateArticulo(newArt.toMap());
      }

      final savedArt = newArt.copyWith(id: savedId);

      // Limpiar memoria RAM para que el nuevo producto aparezca al instante en el buscador e inventario
      DriveService().clearMemoryCache();

      // Sincronizar en segundo plano
      SyncService.instance.syncTable('articulos');

      final item = ItemCotizacion(
        articulo: savedArt,
        precioOriginal: widget.itemAEditar != null
            ? (_selectedArticulo != null && _selectedArticulo!.id != widget.itemAEditar!.articulo.id
                ? _selectedArticulo!.precio
                : widget.itemAEditar!.precioOriginal)
            : (_selectedArticulo?.precio ?? precioEditado),
        cantidad: cantidad,
      );

      if (mounted) {
        Navigator.pop(context, [item]);
      }
    } catch (e) {
      debugPrint("Error al guardar articulo: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0B0C10) : Colors.grey[50]!;
    final textColor = isDark ? Colors.white : Colors.black87;

    final filtrados = _filtro.trim().isEmpty
        ? <Articulo>[]
        : _articulos.where((a) => a.nombre.toLowerCase().contains(_filtro.toLowerCase())).toList();

    double precioEditado = double.tryParse(_precioCtrl.text) ?? 0.0;
    int cantidad = int.tryParse(_cantCtrl.text) ?? 1;
    double subtotalItem = precioEditado * cantidad;

    final size = MediaQuery.of(context).size;
    final bool isWide = size.width > 700;

    // Componentes del formulario
    Widget nombreSection() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nombreCtrl,
          focusNode: _nombreFocusNode,
          style: TextStyle(color: textColor, fontSize: 13),
          decoration: InputDecoration(
            labelText: "Nombre del Producto",
            labelStyle: TextStyle(color: const Color(0xFF00ADEF), fontSize: isDark ? 11 : 12),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF00ADEF), size: 20),
            suffixIcon: _nombreCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                    onPressed: () {
                      setState(() {
                        _nombreCtrl.clear();
                        _filtro = "";
                        _showSuggestions = false;
                        _selectedArticulo = null;
                      });
                    },
                  )
                : null,
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12), borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00ADEF)), borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: isDark ? Colors.black38 : Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          ),
          onChanged: (val) {
            setState(() {
              _filtro = val;
              _showSuggestions = true;
              if (_selectedArticulo != null && val != _selectedArticulo!.nombre) {
                _selectedArticulo = null;
              }
            });
          },
        ),
        // Sugerencias de búsqueda o Frecuentes
        if (_showSuggestions) ...[
          if (_nombreCtrl.text.trim().isEmpty && _topArticulos.isNotEmpty)
            _buildTopSuggestions()
          else if (_nombreCtrl.text.trim().isNotEmpty && filtrados.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E222B) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: filtrados.length,
                separatorBuilder: (context, i) => Divider(color: isDark ? Colors.white10 : Colors.grey[100]),
                itemBuilder: (context, i) {
                  final a = filtrados[i];
                  return ListTile(
                    dense: true,
                    title: Text(a.nombre, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(
                      "${a.precio.toStringAsFixed(2)} Bs | ${a.unidad.isNotEmpty ? a.unidad : 'Unidad'}",
                      style: const TextStyle(color: Color(0xFF00ADEF), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      final cantidad = int.tryParse(_cantCtrl.text.trim()) ?? 1;
                      final item = ItemCotizacion(
                        articulo: a,
                        precioOriginal: a.precio,
                        cantidad: cantidad <= 0 ? 1 : cantidad,
                      );
                      Navigator.pop(context, [item]);
                    },
                  );
                },
              ),
            ),
          ] else if (_nombreCtrl.text.trim().isNotEmpty && filtrados.isEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E222B) : Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
              ),
              child: Text(
                "No se encontraron productos en el inventario.",
                style: TextStyle(color: isDark ? Colors.white30 : Colors.black45, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ],
    );

    Widget switchSection() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131A26) : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Row(
        children: [
          Switch(
            value: _guardarEnInventario,
            activeColor: const Color(0xFF00ADEF),
            onChanged: (val) {
              setState(() {
                _guardarEnInventario = val;
              });
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "¿Guardar cambios en Inventario?",
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _guardarEnInventario
                      ? "Activado. Se guardará en Inventario (Catálogo)."
                      : "Desactivado por defecto. Se guardará en Pre-inventario.",
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF161A22) : Colors.white,
        elevation: 2,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.itemAEditar != null ? "Editar Artículo" : "Añadir Artículo",
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded, color: Color(0xFF00ADEF), size: 28),
            onPressed: _nombreCtrl.text.trim().isEmpty ? null : _guardarArticulo,
            tooltip: "Guardar Artículo",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00ADEF))))
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _nombreFocusNode.unfocus();
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.add_shopping_cart, color: Color(0xFF00ADEF), size: 24),
                        const SizedBox(width: 10),
                        Text(
                          "Detalles del Artículo",
                          style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Divider(height: 30, color: isDark ? Colors.white10 : Colors.black12),
                    
                    // 1. Selector de Imagen al inicio (de paso)
                    Center(
                      child: GestureDetector(
                        onTap: _seleccionarImagen,
                        child: Stack(
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1F1F1F) : Colors.grey[200],
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: const Color(0xFF00ADEF), width: 1.5),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _pickedImage != null
                                  ? (kIsWeb
                                      ? Image.network(_pickedImage!.path, fit: BoxFit.cover)
                                      : Image.file(File(_pickedImage!.path), fit: BoxFit.cover))
                                  : (_imagenFilename != null && _imagenFilename!.isNotEmpty)
                                      ? Image.network(
                                          'https://novaledbolivia.com/sistema/api/uploads/$_imagenFilename',
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                                        )
                                      : const Icon(Icons.add_a_photo_rounded, color: Color(0xFF00ADEF), size: 40),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00ADEF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.edit, color: Colors.black, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Formulario adaptativo de dos columnas
                    if (isWide) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                nombreSection(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCompactEditField(
                                  _precioCtrl,
                                  "Precio Unitario (Bs)",
                                  isNumber: true,
                                  hintText: "0.0",
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),
                                _buildCompactEditField(
                                  _cantCtrl,
                                  "Cantidad",
                                  isNumber: true,
                                  hintText: "1",
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Unidad de Medida",
                                      style: TextStyle(color: const Color(0xFF00ADEF), fontSize: 12),
                                    ),
                                    const SizedBox(height: 4),
                                    GestureDetector(
                                      onTap: _mostrarSelectorUnidades,
                                      child: Container(
                                        height: 48,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.black38 : Colors.grey[100],
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _seleccionUnidad,
                                              style: TextStyle(color: textColor, fontSize: 13),
                                            ),
                                            const Icon(
                                              Icons.arrow_drop_down,
                                              color: Color(0xFF00ADEF),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      nombreSection(),
                      const SizedBox(height: 16),
                      _buildCompactEditField(
                        _precioCtrl,
                        "Precio Unitario (Bs)",
                        isNumber: true,
                        hintText: "0.0",
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      _buildCompactEditField(
                        _cantCtrl,
                        "Cantidad",
                        isNumber: true,
                        hintText: "1",
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Unidad de Medida",
                            style: TextStyle(color: const Color(0xFF00ADEF), fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: _mostrarSelectorUnidades,
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black38 : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _seleccionUnidad,
                                    style: TextStyle(color: textColor, fontSize: 13),
                                  ),
                                  const Icon(
                                    Icons.arrow_drop_down,
                                    color: Color(0xFF00ADEF),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 32),

                    // Subtotal Informativo Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00ADEF).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF00ADEF).withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Subtotal Item:",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            "${subtotalItem.toStringAsFixed(2)} Bs",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF00ADEF)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}
