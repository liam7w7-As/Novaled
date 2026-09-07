import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'product_model.dart';
import 'add_art_screen.dart';
import 'drive_service.dart';

class InventoryScreen extends StatefulWidget {
  final List<Product> products;
  final Future<void> Function() onRefresh;
  final String? title;
  final Function(bool)? onSelectionModeChanged;
  final bool Function(Product)? filter;
  final bool preferRawThumbnail;
  final bool autoRefresh;
  final bool hideAppBar;

  final String? searchQuery;

  const InventoryScreen({
    super.key, 
    required this.products, 
    required this.onRefresh, 
    this.title,
    this.onSelectionModeChanged,
    this.filter,
    this.preferRawThumbnail = false,
    this.autoRefresh = false,
    this.hideAppBar = false,
    this.searchQuery,
  });

  @override
  State<InventoryScreen> createState() => InventoryScreenState();
}

class InventoryScreenState extends State<InventoryScreen> {
  final DriveService _drive = DriveService();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();
  final Set<String> _selectedProductIds = {};
  bool _isSelectionMode = false;
  late List<Product> _currentProducts;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Timer? _searchDebounceTimer;

  bool _isSyncing = false;

  String _selectedFamilia = "Todas";
  String _selectedProveedor = "Todos";
  String _selectedEstado = "Todos";
  DateTime? _startDate;
  DateTime? _endDate;

  bool _showImages = false;

  void _loadShowImagesPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showImages = prefs.getBool('pre_inventory_show_images') ?? false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadShowImagesPreference();
    _searchQuery = widget.searchQuery ?? "";
    _searchController.text = _searchQuery;
    _searchController.addListener(() {
      _searchDebounceTimer?.cancel();
      _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _searchQuery = _searchController.text);
        }
      });
    });
    // Aplicar filtro inmediatamente en el arranque si existe
    if (widget.filter != null) {
      _currentProducts = widget.products.where(widget.filter!).toList();
    } else {
      _currentProducts = List.from(widget.products);
    }

    if (widget.autoRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        refresh();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  // Método público para forzar recarga con animación desde fuera
  Future<void> refresh() async {
    return _refreshIndicatorKey.currentState?.show();
  }

  @override
  void didUpdateWidget(InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery) {
      _searchQuery = widget.searchQuery ?? "";
      _searchController.text = _searchQuery;
    }
    // Sincronización incondicional: Si el padre cambia, aplicamos su filtro a nuestra memoria
    final isPreInventory = widget.title?.trim().toLowerCase() == 'pre-inventario';
    if (isPreInventory) {
      setState(() {
        _currentProducts = List.from(widget.products);
      });
    } else {
      final mem = _drive.inMemoryProducts;
      setState(() {
        final source = mem.isNotEmpty ? mem : widget.products;
        if (widget.filter != null) {
          _currentProducts = source.where(widget.filter!).toList();
        } else {
          _currentProducts = List.from(source);
        }
      });
    }
  }

  Future<void> _handleRefresh() async {
    if (mounted) setState(() => _isSyncing = true);
    final isPreInventory = widget.title?.trim().toLowerCase() == 'pre-inventario';
    try {
      // 1. Prioridad máxima: Memoria RAM (Instantáneo)
      final mem = isPreInventory ? _drive.inMemoryPreProducts : _drive.inMemoryProducts;
      if (mem.isNotEmpty && mounted) {
        setState(() {
          _currentProducts = widget.filter != null ? mem.where(widget.filter!).toList() : List.from(mem);
        });
      }

      // 2. Refrescar desde Caché Local (Disco) por si acaso
      final cache = isPreInventory 
          ? await _drive.getPreInventoryProducts() 
          : await _drive.getLocalCache();
      if (mounted) {
        setState(() {
          if (widget.filter != null) {
            _currentProducts = cache.where(widget.filter!).toList();
          } else {
            _currentProducts = List.from(cache);
          }
        });
      }

      // 3. Sincronización remota lenta (Drive)
      if (isPreInventory) {
        widget.onRefresh().then((_) async {
          final finalCache = await _drive.getPreInventoryProducts();
          if (mounted) {
            setState(() {
              if (widget.filter != null) {
                _currentProducts = finalCache.where(widget.filter!).toList();
              } else {
                _currentProducts = List.from(finalCache);
              }
            });
          }
        }).catchError((e) {
          debugPrint("Error in background pre-inventory sync: $e");
        });
      } else {
        await widget.onRefresh();

        // 4. Actualización final tras sincronización
        final finalCache = await _drive.getLocalCache();
        if (mounted) {
          setState(() {
            if (widget.filter != null) {
              _currentProducts = finalCache.where(widget.filter!).toList();
            } else {
              _currentProducts = List.from(finalCache);
            }
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _seleccionarRangoFechas() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: isDark ? ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00ADEF),
              onPrimary: Colors.black,
              surface: Color(0xFF161A22),
              onSurface: Colors.white,
            ),
          ) : ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF00ADEF),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _exportarExcel(List<Product> productosParaExportar) async {
    final List<List<String>> rows = [
      [
        "ID Carpeta",
        "Nombre / Título",
        "Precio (Bs)",
        "Estado",
        "Categoría/Familia",
        "Subcategoría",
        "Cód Tienda",
        "Cód Caja",
        "Watts",
        "Proveedor / Marca",
        "Fecha Registro",
        "Medidas",
        "Descripción / Detalles"
      ]
    ];

    for (var prod in productosParaExportar) {
      final String medidasStr = prod.medidas.entries
          .where((e) => e.value.trim().isNotEmpty)
          .map((e) => "${e.key}: ${e.value}")
          .join(", ");

      rows.add([
        prod.folderId ?? '',
        prod.titulo,
        prod.precio,
        prod.estado.toUpperCase(),
        prod.familia,
        prod.subcategoria,
        prod.codTienda,
        prod.codCaja,
        prod.watts,
        prod.marca,
        prod.fecha,
        medidasStr,
        prod.detalles.replaceAll('\n', ' ').replaceAll(';', ','),
      ]);
    }

    String csv = '\uFEFF';
    for (var row in rows) {
      csv += row.map((field) {
        String f = field.replaceAll('"', '""');
        if (f.contains(';') || f.contains(',') || f.contains('\n') || f.contains('\r') || f.contains('"')) {
          return '"$f"';
        }
        return f;
      }).join(';') + '\r\n';
    }

    try {
      if (kIsWeb) {
        final uri = Uri.dataFromString(
          csv,
          mimeType: 'text/csv',
          encoding: utf8,
        );
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          throw Exception("No se pudo iniciar la descarga.");
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/inventario_novaled_catalogo.csv');
        await file.writeAsBytes(utf8.encode(csv));
        
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Inventario Catálogo Novaled',
          text: 'Exportación del Inventario de Catálogo de Productos Novaled.',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al exportar: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedProductIds.clear();
      if (widget.onSelectionModeChanged != null) {
        widget.onSelectionModeChanged!(_isSelectionMode);
      }
    });
  }

  void _toggleSelection(String? id) {
    if (id == null) return;
    setState(() {
      if (_selectedProductIds.contains(id)) {
        _selectedProductIds.remove(id);
      } else {
        _selectedProductIds.add(id);
      }
      if (_selectedProductIds.isEmpty) toggleSelectionMode();
    });
  }

  // --- ACCIONES GRUPALES ---

  Future<void> _shareSelected() async {
    if (_selectedProductIds.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Preparando imágenes en alta resolución...", style: TextStyle(fontWeight: FontWeight.bold))),
    );
    
    try {
      final tempDir = await getTemporaryDirectory();
      
      // Descarga en paralelo para máximo rendimiento
      final downloadTasks = _selectedProductIds.map((id) async {
        final product = widget.products.firstWhere((p) => p.folderId == id);
        final bytes = await _drive.getProductHighRes(id, product.finalArtId) ?? _drive.thumbnailCache[id];
        if (bytes != null) {
          final safeTitle = product.titulo.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
          final file = File('${tempDir.path}/share_$safeTitle.jpg');
          await file.writeAsBytes(bytes);
          return XFile(file.path);
        }
        return null;
      });

      final filesToShare = (await Future.wait(downloadTasks)).whereType<XFile>().toList();

      if (filesToShare.isNotEmpty && mounted) {
        await Share.shareXFiles(filesToShare, text: 'Catálogo Novaled System');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al compartir: $e")));
      }
    }
  }

  Future<void> _saveSelected() async {
    if (_selectedProductIds.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Guardando lote de imágenes HD...", style: TextStyle(fontWeight: FontWeight.bold))),
    );
    
    try {
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) directory = await getExternalStorageDirectory();
      } else {
        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      if (directory == null) throw Exception("No se pudo acceder al directorio de descargas");

      // Descarga y guardado en paralelo
      final saveTasks = _selectedProductIds.map((id) async {
        final product = widget.products.firstWhere((p) => p.folderId == id);
        final bytes = await _drive.getProductHighRes(id, product.finalArtId) ?? _drive.thumbnailCache[id];
        if (bytes != null) {
          final safeTitle = product.titulo.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
          final file = File('${directory!.path}/$safeTitle.jpg');
          await file.writeAsBytes(bytes);
          return true;
        }
        return false;
      });

      final results = await Future.wait(saveTasks);
      int savedCount = results.where((r) => r).length;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("✅ $savedCount imágenes guardadas en: ${directory.path.split('/').last}"),
          backgroundColor: const Color(0xFF00ADEF),
        ));
        toggleSelectionMode();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al guardar: $e")));
      }
    }
  }

  Future<void> _deleteSelected() async {
    final int count = _selectedProductIds.length;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("⚠️ ELIMINAR $count PRODUCTOS"),
        content: const Text("¿Estás seguro? Se borrarán de Google Drive permanentemente.\nEsta acción es irreversible."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text("ELIMINAR TODO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final idsToDelete = List<String>.from(_selectedProductIds);
      
      // 1. BORRADO ATÓMICO EN UI: Desaparecen instantáneamente
      setState(() {
        _currentProducts.removeWhere((p) => idsToDelete.contains(p.folderId));
        _selectedProductIds.clear();
        _isSelectionMode = false;
        if (widget.onSelectionModeChanged != null) widget.onSelectionModeChanged!(false);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Eliminando $count productos en segundo plano..."), duration: const Duration(seconds: 3))
        );
      }

      // 2. Ejecución en segundo plano sin bloquear la UI
      try {
        await _drive.deleteMultipleFiles(idsToDelete);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Borrado completado con éxito"), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        debugPrint("Error en borrado por lotes: $e");
        // Notificar al usuario pero no restaurar los items (el usuario quería borrarlos)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Aviso: Algunos productos podrían no haberse borrado en la nube"), backgroundColor: Colors.orange),
          );
        }
      }
    }
  }

  void _openEditProduct(Product p) {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/productos/editar'),
        builder: (c) => AddArtScreen(
          product: p,
          isCatalog: widget.title?.trim().toLowerCase() != 'pre-inventario',
        ),
      ),
    ).then((v) {
      if (v == true) {
        // 1. Remoción agresiva inmediata de la UI local
        setState(() {
          _currentProducts.removeWhere((item) => item.folderId == p.folderId);
        });
        
        // 2. Forzar actualización desde memoria
        refresh();

        // 3. Redirigir al catálogo si estamos en la pantalla de inicio o Foto a Arte
        if (widget.title == null || widget.title == "Foto a Arte") {
          final listos = _drive.inMemoryProducts.where((prod) => prod.estado.trim().toLowerCase() == 'listo').toList();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              settings: const RouteSettings(name: '/catalogo'),
              builder: (c) => InventoryScreen(
                products: listos,
                onRefresh: widget.onRefresh,
                title: "CATÁLOGO",
                filter: (prod) => prod.estado.trim().toLowerCase() == 'listo',
                autoRefresh: true,
              ),
            ),
          ).then((_) => widget.onRefresh());
        }
      }
    });
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Calcular las opciones dinámicas para filtros
    final familias = ["Todas"] + _currentProducts.map((p) => p.familia.trim()).where((f) => f.isNotEmpty).toSet().toList();
    final proveedores = ["Todos"] + _currentProducts.map((p) => p.marca.trim()).where((m) => m.isNotEmpty).toSet().toList();

    // Validar estados por si se actualiza la lista
    if (!familias.contains(_selectedFamilia)) {
      _selectedFamilia = "Todas";
    }
    if (!proveedores.contains(_selectedProveedor)) {
      _selectedProveedor = "Todos";
    }

    // 1. Aplicar filtros de búsqueda sobre los productos actuales
    List<Product> filtered = _currentProducts.where((p) {
      // Filtro de Familia / Categoría
      if (_selectedFamilia != "Todas" && p.familia.trim() != _selectedFamilia) {
        return false;
      }

      // Filtro de Proveedor / Marca
      if (_selectedProveedor != "Todos" && p.marca.trim() != _selectedProveedor) {
        return false;
      }

      // Filtro de Estado
      if (_selectedEstado != "Todos") {
        if (_selectedEstado == "Listo" && p.estado.trim().toLowerCase() != "listo") {
          return false;
        }
        if (_selectedEstado == "Pendiente" && p.estado.trim().toLowerCase() != "pendiente") {
          return false;
        }
      }

      // Filtro de Fechas
      if (_startDate != null && _endDate != null) {
        if (p.fecha.isEmpty) return false;
        try {
          final artDate = DateTime.parse(p.fecha);
          final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
          final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
          if (artDate.isBefore(start) || artDate.isAfter(end)) {
            return false;
          }
        } catch (_) {
          return false;
        }
      }

      return true;
    }).toList();

    // 2. Aplicar filtro de búsqueda de texto
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((p) => 
        p.titulo.toLowerCase().contains(q) || 
        p.familia.toLowerCase().contains(q) || 
        p.subcategoria.toLowerCase().contains(q) ||
        p.marca.toLowerCase().contains(q) ||
        p.detalles.toLowerCase().contains(q)
      ).toList();
    }

    final int totalFilteredCount = filtered.length;
    final bool isTruncated = filtered.length > 80;
    if (isTruncated) {
      filtered = filtered.take(80).toList();
    }

    Map<String, Map<String, List<Product>>> grouped = {};
    for (var p in filtered) {
      String f = p.familia.isEmpty ? "SIN CATEGORÍA" : p.familia.toUpperCase();
      String s = p.subcategoria.isEmpty ? "SIN SUBCATEGORÍA" : p.subcategoria.toUpperCase();
      grouped.putIfAbsent(f, () => {});
      grouped[f]!.putIfAbsent(s, () => []);
      grouped[f]![s]!.add(p);
    }

    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final isTablet = size.width >= 600 && size.width < 1000;
    final int chunkSize = isMobile ? 2 : (isTablet ? 3 : 5);

    final List<_VisualItem> visualItems = [];
    if (widget.title != null) {
      visualItems.add(_TitleItem(widget.title!.toUpperCase()));
    }

    grouped.forEach((familia, subcats) {
      visualItems.add(_FamiliaHeaderItem(familia));
      subcats.forEach((subcat, productsList) {
        visualItems.add(_SubcategoriaHeaderItem(subcat));
        for (int i = 0; i < productsList.length; i += chunkSize) {
          final chunk = productsList.sublist(
            i, 
            i + chunkSize > productsList.length ? productsList.length : i + chunkSize
          );
          visualItems.add(_ProductRowItem(chunk));
        }
      });
    });

    final bool showLocalAppBar = (widget.title != null && !widget.hideAppBar) || _isSelectionMode;

    // Decoraciones de dropdowns
    final dropdownDecoration = InputDecoration(
      filled: true,
      fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey[200],
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Color(0xFF00ADEF), width: 1),
      ),
    );

    Widget buildDropdown({
      required String label,
      required String value,
      required List<String> items,
      required ValueChanged<String?> onChanged,
    }) {
      return Container(
        width: 165,
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        child: DropdownButtonFormField<String>(
          value: value,
          decoration: dropdownDecoration.copyWith(
            labelText: label,
            labelStyle: const TextStyle(color: Color(0xFF00ADEF), fontSize: 11),
          ),
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00ADEF)),
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        ),
      );
    }

    Widget buildDatePickerButton() {
      final dateText = _startDate != null && _endDate != null
          ? "${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}"
          : "Filtrar por Fechas";
      return Container(
        height: 48,
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        child: OutlinedButton.icon(
          onPressed: _seleccionarRangoFechas,
          icon: const Icon(Icons.calendar_today, size: 16, color: Color(0xFF00ADEF)),
          label: Text(
            dateText,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey[200],
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      );
    }

    final hasActiveFilters = _selectedFamilia != "Todas" ||
        _selectedProveedor != "Todos" ||
        _selectedEstado != "Todos" ||
        _startDate != null ||
        _endDate != null;

    Widget buildClearButton() {
      if (!hasActiveFilters) return const SizedBox.shrink();
      return Container(
        height: 48,
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        child: IconButton(
          icon: const Icon(Icons.filter_alt_off, color: Colors.redAccent),
          tooltip: "Limpiar Filtros",
          onPressed: () {
            setState(() {
              _selectedFamilia = "Todas";
              _selectedProveedor = "Todos";
              _selectedEstado = "Todos";
              _startDate = null;
              _endDate = null;
            });
          },
        ),
      );
    }

    Widget buildExcelButton() {
      return Container(
        height: 48,
        margin: const EdgeInsets.only(bottom: 8),
        child: ElevatedButton.icon(
          onPressed: () => _exportarExcel(filtered),
          icon: const Icon(Icons.file_download, size: 20, color: Colors.black),
          label: const Text(
            "EXPORTAR EXCEL",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: showLocalAppBar ? AppBar(
        title: Text(_isSelectionMode ? "${_selectedProductIds.length} SELECCIONADOS" : (widget.title ?? "INVENTARIO")),
        leading: _isSelectionMode 
          ? IconButton(icon: const Icon(Icons.close), onPressed: toggleSelectionMode)
          : (widget.title != null ? const BackButton() : null),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(icon: const Icon(Icons.download), onPressed: _saveSelected, tooltip: "Guardar en celular"),
            IconButton(icon: const Icon(Icons.share), onPressed: _shareSelected, tooltip: "Enviar grupo"),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: _deleteSelected, tooltip: "Borrar grupo"),
          ] else ...[
            if (_isSyncing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Center(
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00ADEF)),
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Center(
                  child: Icon(Icons.cloud_done, color: Colors.green, size: 20),
                ),
              ),
            IconButton(icon: const Icon(Icons.checklist_rtl), onPressed: toggleSelectionMode, tooltip: "Selección Múltiple"),
          ]
        ],
      ) : null,
      body: Column(
        children: [
          _buildSearchBar(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
            child: Row(
              children: [
                buildDatePickerButton(),
                buildDropdown(
                  label: "Categoría",
                  value: _selectedFamilia,
                  items: familias,
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedFamilia = val);
                  },
                ),
                buildDropdown(
                  label: "Proveedor",
                  value: _selectedProveedor,
                  items: proveedores,
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedProveedor = val);
                  },
                ),
                buildDropdown(
                  label: "Estado",
                  value: _selectedEstado,
                  items: ["Todos", "Listo", "Pendiente"],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedEstado = val);
                  },
                ),
                buildClearButton(),
                const SizedBox(width: 8),
                buildExcelButton(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Card(
              color: isDark ? const Color(0xFF131A26) : Colors.white,
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _showImages ? Icons.image_rounded : Icons.image_not_supported_rounded,
                      color: const Color(0xFF00ADEF),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Visualizar imágenes",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    Switch(
                      value: _showImages,
                      activeColor: const Color(0xFF00ADEF),
                      onChanged: (val) async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('pre_inventory_show_images', val);
                        setState(() {
                          _showImages = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isTruncated)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.amber.withOpacity(0.12) : Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Mostrando 80 de $totalFilteredCount productos. Use la barra de búsqueda para refinar.",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.amber[200] : Colors.amber[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              key: _refreshIndicatorKey,
              onRefresh: _handleRefresh,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: visualItems.length,
                itemBuilder: (context, index) {
                  final item = visualItems[index];
                  if (item is _TitleItem) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    );
                  } else if (item is _FamiliaHeaderItem) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Text(item.name, style: const TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold, fontSize: 20)),
                        const Divider(color: Color(0xFF00ADEF), thickness: 2.5),
                      ],
                    );
                  } else if (item is _SubcategoriaHeaderItem) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 10, top: 15, bottom: 8),
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                    );
                  } else if (item is _ProductRowItem) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const double spacing = 16.0;
                          final double itemWidth = (constraints.maxWidth - (chunkSize - 1) * spacing) / chunkSize;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: List.generate(chunkSize, (i) {
                              if (i < item.products.length) {
                                final p = item.products[i];
                                return Container(
                                  width: itemWidth,
                                  margin: EdgeInsets.only(right: i == chunkSize - 1 ? 0 : spacing),
                                  child: AspectRatio(
                                    aspectRatio: _showImages ? 0.65 : (isMobile ? 1.1 : 1.3),
                                    child: _ProductCard(
                                      product: p,
                                      showImages: _showImages,
                                      isSelected: _selectedProductIds.contains(p.folderId),
                                      isSelectionMode: _isSelectionMode,
                                      thumbnail: _drive.thumbnailCache[widget.preferRawThumbnail ? "${p.folderId}_raw" : (p.folderId ?? "")],
                                      preferRawThumbnail: widget.preferRawThumbnail,
                                      onTap: () {
                                        if (_isSelectionMode) {
                                          _toggleSelection(p.folderId);
                                        }
                                      },
                                      onDoubleTap: _isSelectionMode ? null : () => _openEditProduct(p),
                                      onLongPress: () {
                                        if (!_isSelectionMode) {
                                          toggleSelectionMode();
                                        }
                                        _toggleSelection(p.folderId);
                                      },
                                      onImageTap: (bytes) => _showImagePreview(p, bytes),
                                      onDelete: () => _confirmDelete(p),
                                      onDrive: () async {
                                        if (p.folderId != null) {
                                          final url = 'https://drive.google.com/drive/folders/${p.folderId}';
                                          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                        }
                                      },
                                    ),
                                  ),
                                );
                              } else {
                                return SizedBox(width: itemWidth);
                              }
                            }),
                          );
                        },
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: (widget.title == "Foto a Arte" || widget.title?.trim().toLowerCase() == "pre-inventario")
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF00ADEF),
              tooltip: "Subir nueva foto/arte",
              child: const Icon(Icons.add, color: Colors.white, size: 28),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: '/productos/editar'),
                  builder: (c) => AddArtScreen(isCatalog: widget.title?.trim().toLowerCase() != 'pre-inventario'),
                ),
              ).then((_) => _handleRefresh()),
            )
          : null,
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 5),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
        decoration: InputDecoration(
          hintText: "Buscar en ${widget.title ?? 'INICIO'}...",
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF00ADEF), size: 20),
          suffixIcon: _searchQuery.isNotEmpty 
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey, size: 20),
                onPressed: () => _searchController.clear(),
              ) 
            : null,
          filled: true,
          fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey[200],
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00ADEF), width: 1),
          ),
        ),
      ),
    );
  }



  void _showImagePreview(Product p, Uint8List initialBytes) {
    Uint8List? displayBytes = initialBytes;
    bool isHighResLoading = true;
    bool hasStartedLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Iniciar la carga solo una vez al abrir el diálogo
            if (!hasStartedLoading) {
              hasStartedLoading = true;
              _drive.getProductHighRes(p.folderId!, p.finalArtId).then((highRes) {
                if (highRes != null && ctx.mounted) {
                  setDialogState(() {
                    displayBytes = highRes;
                    isHighResLoading = false;
                  });
                  // Notificación rápida de que ya está en HD
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text("✅ Alta Resolución Lista"),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.only(bottom: 100, left: 20, right: 20),
                    ),
                  );
                }
              });
            }

            return Dialog.fullscreen(
              backgroundColor: Colors.black,
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      child: Image.memory(
                        displayBytes ?? initialBytes,
                        fit: BoxFit.contain,
                      ),
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
                          
                          final bytesToSave = displayBytes; // Usar lo que ya esté cargado
                          if (bytesToSave != null && directory != null) {
                            final safeTitle = p.titulo.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
                            final file = File('${directory.path}/$safeTitle.jpg');
                            await file.writeAsBytes(bytesToSave);
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
                          final bytesToShare = displayBytes;
                          if (bytesToShare != null) {
                            final file = File('${tempDir.path}/share_${p.titulo}.jpg');
                            await file.writeAsBytes(bytesToShare);
                            await Share.shareXFiles([XFile(file.path)], text: 'Producto: ${p.titulo}');
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

  Future<void> _confirmDelete(Product p) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("⚠️ ¿ELIMINAR PRODUCTO?"),
        content: Text("¿Borrar permanentemente '${p.titulo}'?\nEsta acción no se puede deshacer."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true), 
            child: const Text("SÍ, BORRAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );

    if (confirm == true && p.folderId != null) {
      // 1. Remoción visual inmediata
      setState(() {
        _currentProducts.removeWhere((item) => item.folderId == p.folderId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Eliminando '${p.titulo}'..."), duration: const Duration(seconds: 2))
        );
      }

      try {
        // 2. Borrado en Drive y actualización de caché (RAM + Disco)
        await _drive.deleteFile(p.folderId!);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Producto eliminado con éxito"), backgroundColor: Colors.red)
          );
        }
      } catch (e) {
        // 3. Si hay error, informar pero mantener la UI limpia (el usuario ya lo dio por borrado)
        debugPrint("Error al borrar en la nube: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Aviso: Se borró localmente pero falló en la nube"), backgroundColor: Colors.orange)
          );
        }
      }
    }
  }
}

class _ProductCard extends StatefulWidget {
  final Product product;
  final bool isSelected;
  final bool isSelectionMode;
  final Uint8List? thumbnail;
  final bool preferRawThumbnail;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback onLongPress;
  final Function(Uint8List) onImageTap;
  final VoidCallback onDelete;
  final VoidCallback onDrive;
  final bool showImages;

  const _ProductCard({
    required this.product,
    required this.isSelected,
    required this.isSelectionMode,
    this.thumbnail,
    this.preferRawThumbnail = false,
    required this.onTap,
    this.onDoubleTap,
    required this.onLongPress,
    required this.onImageTap,
    required this.onDelete,
    required this.onDrive,
    required this.showImages,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  Uint8List? _thumbnail;
  bool _isLoadingThumbnail = false;

  @override
  void initState() {
    super.initState();
    _thumbnail = widget.thumbnail;
    if (_thumbnail == null && widget.product.folderId != null) {
      _loadThumbnail();
    }
  }

  @override
  void didUpdateWidget(_ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.thumbnail != null) {
      if (widget.thumbnail != oldWidget.thumbnail) {
        setState(() {
          _thumbnail = widget.thumbnail;
        });
      }
    } else {
      if (widget.product.folderId != oldWidget.product.folderId ||
          widget.product.finalArtId != oldWidget.product.finalArtId ||
          oldWidget.thumbnail != null) {
        setState(() {
          _thumbnail = null;
        });
        _loadThumbnail();
      }
    }
  }

  Future<void> _loadThumbnail() async {
    if (widget.product.folderId == null || _isLoadingThumbnail) return;

    final cacheKey = widget.preferRawThumbnail ? "${widget.product.folderId}_raw" : widget.product.folderId!;
    final cached = DriveService().thumbnailCache[cacheKey];
    if (cached != null) {
      if (mounted) setState(() => _thumbnail = cached);
      return;
    }

    setState(() => _isLoadingThumbnail = true);
    try {
      final bytes = await DriveService().getProductThumbnail(
        widget.product.folderId!, 
        widget.product.finalArtId,
        preferFinalArt: !widget.preferRawThumbnail,
      );
      if (mounted) {
        setState(() {
          _thumbnail = bytes;
          _isLoadingThumbnail = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingThumbnail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131A26) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isSelected 
              ? const Color(0xFF00ADEF) 
              : (isDark ? Colors.white10 : Colors.black12),
          width: widget.isSelected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showImages) ...[
              // Contenedor de la Imagen (Blanco y Adaptable)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: GestureDetector(
                      onTap: _thumbnail != null ? () => widget.onImageTap(_thumbnail!) : null,
                      child: _thumbnail != null 
                          ? Image.memory(_thumbnail!, fit: BoxFit.contain)
                          : (_isLoadingThumbnail 
                              ? const Center(child: SizedBox(width: 25, height: 25, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00ADEF))))
                              : const Icon(Icons.inventory_2, color: Colors.grey, size: 36)),
                    ),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
            ],
            // DETALLES
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.product.titulo,
                    style: TextStyle(
                      fontSize: 14, 
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Bs. ${double.tryParse(widget.product.precio)?.toStringAsFixed(2) ?? (widget.product.precio.isEmpty ? '0.00' : widget.product.precio)}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Box código: ${widget.product.codCaja.isEmpty ? 'S/C' : widget.product.codCaja}",
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Proveedor: ${widget.product.marca.isEmpty ? 'Novaled' : widget.product.marca}",
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  if (widget.product.verificadoPor != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        children: [
                          Icon(Icons.verified, size: 10, color: isDark ? const Color(0xFFCCFF00) : const Color(0xFF2E7D32)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              "VERIF: ${widget.product.verificadoPor}",
                              style: TextStyle(
                                color: isDark ? const Color(0xFFCCFF00) : const Color(0xFF2E7D32),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.product.estado.trim().toLowerCase() == 'pendiente' && widget.product.camposModificados.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        "Pendiente: ${widget.product.camposModificados.join(', ')}",
                        style: const TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  
                  // Badge de Estado (tipo "Status" del mockup)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.product.cantidad > 0 ? "Stock: ${widget.product.cantidad}" : "Sin Stock",
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // BOTONES DE ACCIÓN (Pencil, Trash, Link)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (widget.isSelectionMode)
                    Icon(widget.isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: const Color(0xFF00ADEF), size: 18)
                  else ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      color: iconColor,
                      onPressed: () {
                        if (widget.onDoubleTap != null) widget.onDoubleTap!();
                      },
                      tooltip: "Editar Datos",
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(8),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: iconColor,
                      onPressed: widget.onDelete,
                      tooltip: "Eliminar Producto",
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(8),
                    ),
                    IconButton(
                      icon: const Icon(Icons.link, size: 18),
                      color: iconColor,
                      onPressed: widget.onDrive,
                      tooltip: "Ver en Drive",
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(8),
                    ),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

abstract class _VisualItem {}
class _TitleItem extends _VisualItem { final String title; _TitleItem(this.title); }
class _FamiliaHeaderItem extends _VisualItem { final String name; _FamiliaHeaderItem(this.name); }
class _SubcategoriaHeaderItem extends _VisualItem { final String name; _SubcategoriaHeaderItem(this.name); }
class _ProductRowItem extends _VisualItem { final List<Product> products; _ProductRowItem(this.products); }
