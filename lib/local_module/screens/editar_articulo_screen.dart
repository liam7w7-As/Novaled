import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../database_helper.dart';
import '../models/articulo.dart';
import '../services/sync_service.dart';
import 'almacenamiento_screen.dart';
import '../../drive_service.dart';

class EditarArticuloScreen extends StatefulWidget {
  final Articulo? articulo;
  const EditarArticuloScreen({super.key, this.articulo});

  @override
  State<EditarArticuloScreen> createState() => _EditarArticuloScreenState();
}

class _EditarArticuloScreenState extends State<EditarArticuloScreen> {
  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _precioCajaCtrl = TextEditingController();
  final _codCajaCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _familiaCtrl = TextEditingController();
  final _subcategoriaCtrl = TextEditingController();
  final _cantCtrl = TextEditingController(text: "0");

  XFile? _pickedImage;
  String? _imagenFilename;
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;
  final DriveService _drive = DriveService();

  List<String> _unidades = ["Unidad"];
  String _seleccionUnidad = "Unidad";
  bool _guardarEnInventario = true;

  @override
  void initState() {
    super.initState();
    _loadUnidades();
    
    // Configurar listeners de actualización de UI para subtotal en tiempo real
    _precioCtrl.addListener(() => setState(() {}));
    _cantCtrl.addListener(() => setState(() {}));

    if (widget.articulo != null) {
      final art = widget.articulo!;
      _nombreCtrl.text = art.nombre;
      _precioCtrl.text = art.precio > 0 ? art.precio.toString() : "";
      _precioCajaCtrl.text = art.precioCaja > 0 ? art.precioCaja.toString() : "";
      _codCajaCtrl.text = art.codCaja ?? "";
      _descCtrl.text = art.descripcion;
      _familiaCtrl.text = art.familia;
      _subcategoriaCtrl.text = art.subcategoria;
      _imagenFilename = art.imagen;
      _seleccionUnidad = art.unidad.isNotEmpty ? art.unidad : "Unidad";

      if (art.stockJson != null && art.stockJson!.isNotEmpty) {
        try {
          final Map<String, dynamic> extra = jsonDecode(art.stockJson!);
          _guardarEnInventario = extra['isCatalog'] != false; // default true
          
          if (extra.containsKey('general')) {
            _cantCtrl.text = extra['general'].toString();
          } else {
            // Sumar stocks de locales si existe
            int totalStock = 0;
            extra.values.forEach((v) {
              if (v is Map) {
                v.values.forEach((subV) => totalStock += (int.tryParse(subV.toString()) ?? 0));
              } else if (v is! bool) {
                totalStock += (int.tryParse(v.toString()) ?? 0);
              }
            });
            _cantCtrl.text = totalStock.toString();
          }
        } catch (_) {}
      }
    }
    if (_codCajaCtrl.text.trim().isEmpty) {
      _codCajaCtrl.text = "BOX-${Random().nextInt(900000) + 100000}";
    }
    _guardarEnInventario = true;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    _precioCajaCtrl.dispose();
    _codCajaCtrl.dispose();
    _descCtrl.dispose();
    _familiaCtrl.dispose();
    _subcategoriaCtrl.dispose();
    _cantCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("El nombre es obligatorio")),
      );
      return;
    }

    setState(() => _isSaving = true);

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
      if (widget.articulo?.stockJson != null && widget.articulo!.stockJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(widget.articulo!.stockJson!);
          if (decoded is Map) {
            stockJsonMap = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }

      stockJsonMap['isCatalog'] = _guardarEnInventario;
      stockJsonMap['general'] = int.tryParse(_cantCtrl.text) ?? 0;

      final a = Articulo(
        id: widget.articulo?.id,
        nombre: _nombreCtrl.text.trim(),
        precio: double.tryParse(_precioCtrl.text) ?? 0.0,
        precioCaja: double.tryParse(_precioCajaCtrl.text) ?? 0.0,
        descripcion: _descCtrl.text.trim(),
        folderId: widget.articulo?.folderId,
        finalArtId: widget.articulo?.finalArtId,
        proveedor: widget.articulo?.proveedor ?? 'Novaled',
        codCaja: _codCajaCtrl.text.trim(),
        stockJson: jsonEncode(stockJsonMap),
        familia: _familiaCtrl.text.trim(),
        subcategoria: _subcategoriaCtrl.text.trim(),
        unidad: _seleccionUnidad,
        unidadDetalle: widget.articulo?.unidadDetalle ?? "",
        imagen: uploadFilename,
        fecha: widget.articulo?.fecha != null && widget.articulo!.fecha.isNotEmpty
            ? widget.articulo!.fecha
            : DateTime.now().toIso8601String().substring(0, 10),
      );

      int id;
      Articulo savedArt;

      if (widget.articulo?.id == null) {
        id = await DatabaseHelper.instance.insertArticulo(a.toMap());
        savedArt = a.copyWithId(id);
      } else {
        id = widget.articulo!.id!;
        await DatabaseHelper.instance.updateArticulo(a.toMap());
        savedArt = a;
      }

      // Sincronizar en segundo plano inmediatamente
      SyncService.instance.syncTable('articulos');

      if (!mounted) return;

      // 1. Obtenemos el Navigator de la pantalla
      final navigator = Navigator.of(context);
      final parentContext = navigator.context;

      // 2. Regresamos a la pantalla de inventario pasando un valor indicando éxito
      navigator.pop(true);

      // 3. Preguntar por stock
      Future.delayed(Duration.zero, () async {
        if (!parentContext.mounted) return;
        final bool? goToStorage = await showDialog<bool>(
          context: parentContext,
          builder: (askCtx) {
            final isDark = Theme.of(askCtx).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
              title: Text("Producto Guardado", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
              content: Text("¿Quieres crear o actualizar un registro de almacenamiento (Stock) para este producto?", 
                                 style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(askCtx, false), child: const Text("LUEGO")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00ADEF)),
                  onPressed: () => Navigator.pop(askCtx, true), 
                  child: const Text("SÍ, IR AHORA", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
                ),
              ],
            );
          },
        );

        if (goToStorage == true && savedArt.id != null) {
          navigator.push(
            MaterialPageRoute(builder: (context) => AlmacenamientoScreen(initialArt: savedArt))
          );
        }
      });
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
              title: const Text("Error al Guardar", style: TextStyle(color: Colors.red)),
              content: Text("No se pudo guardar: $e", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ENTENDIDO"))],
            );
          }
        );
      }
    }
  }

  Future<void> _seleccionarImagen() async {
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

  Future<void> _loadUnidades() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final rawUnits = await dbHelper.queryAllUnidadesMedida();
      final List<String> unitNames = rawUnits.map((u) => u['nombre']?.toString() ?? '').where((name) => name.isNotEmpty).toList();
      
      setState(() {
        _unidades = unitNames;
        if (widget.articulo != null && widget.articulo!.unidad.isNotEmpty) {
          if (!_unidades.contains(widget.articulo!.unidad)) {
            _unidades.add(widget.articulo!.unidad);
          }
          _seleccionUnidad = widget.articulo!.unidad;
        } else if (_unidades.isNotEmpty && !_unidades.contains(_seleccionUnidad)) {
          _seleccionUnidad = _unidades.first;
        }
      });
      _syncUnidades(silent: true);
    } catch (e) {
      debugPrint("Error cargando unidades: $e");
    }
  }

  Future<void> _syncUnidades({bool silent = false}) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      await dbHelper.syncUnidadesMedida(_drive);

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
      debugPrint("Error sincronizando unidades: $e");
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
        );
      },
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0B0C10) : Colors.grey[50]!;
    final textColor = isDark ? Colors.white : Colors.black87;



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
          widget.articulo?.id == null ? "Nuevo Artículo" : "Editar Artículo",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
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
              onPressed: _guardar,
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
                    onTap: _seleccionarImagen,
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
                          child: _pickedImage != null
                              ? (kIsWeb
                                  ? Image.network(_pickedImage!.path, fit: BoxFit.cover)
                                  : Image.file(File(_pickedImage!.path), fit: BoxFit.cover))
                              : (_imagenFilename != null && _imagenFilename!.isNotEmpty)
                                  ? Image.network(
                                      'https://novaledbolivia.com/sistema/api/uploads/$_imagenFilename',
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey, size: 20),
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
                    child: _buildField("Nombre del Producto", _nombreCtrl, TextInputType.text),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildField("Precio (Bs)", _precioCtrl, TextInputType.number)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildField("Precio Caja (Bs)", _precioCajaCtrl, TextInputType.number)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildField("Cantidad", _cantCtrl, TextInputType.number)),
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
                  Expanded(child: _buildField("Categoría/Familia", _familiaCtrl, TextInputType.text)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildField("Subcategoría", _subcategoriaCtrl, TextInputType.text)),
                ],
              ),
              const SizedBox(height: 16),
              _buildField("Descripción", _descCtrl, TextInputType.multiline, maxLines: 4),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00ADEF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isSaving ? null : _guardar,
                  child: Text(
                    widget.articulo?.id == null ? "AGREGAR ARTÍCULO" : "GUARDAR CAMBIOS",
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
}
