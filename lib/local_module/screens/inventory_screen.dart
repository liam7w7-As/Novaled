import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../models/articulo.dart';
import 'seleccionar_arte_screen.dart';
import 'almacenamiento_screen.dart';
import 'editar_articulo_screen.dart';
import 'agregar_articulo_screen.dart';
import '../../drive_service.dart';
import '../services/sync_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

const Color brandOrange = Color(0xFFFF9800);

class InventoryScreen extends StatefulWidget {
  final bool hideAppBar;
  final String? searchQuery;
  final String initialTab;
  const InventoryScreen({
    super.key, 
    this.hideAppBar = false, 
    this.searchQuery,
    this.initialTab = 'oficial',
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Articulo> _articulos = [];
  bool _isLoading = true;
  late String _inventoryTab;
  final DriveService _drive = DriveService();

  String? _selectedLetter;
  String? _overlayLetter;
  double _overlayScale = 0.5;
  double _overlayOpacity = 0.0;
  final List<String> _alphabet = const [
    "TODOS", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", 
    "N", "Ñ", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"
  ];

  bool _isSyncing = false;

  Timer? _syncTimer;
  Timer? _searchDebounceTimer;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _selectedFamilia = "Todas";
  String _selectedProveedor = "Todos";
  String _selectedStockStatus = "Todos";
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSelectionMode = false;
  final Set<int> _selectedArticleIds = {};
  bool _showImages = false;
  bool _showSearchField = false;

  void _selectLetter(String letter) {
    setState(() {
      _selectedLetter = letter == 'TODOS' ? null : letter;
      _overlayLetter = letter;
      _overlayScale = 0.5;
      _overlayOpacity = 0.0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _overlayScale = 1.2;
          _overlayOpacity = 1.0;
        });
      }
    });

    Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _overlayScale = 1.5;
          _overlayOpacity = 0.0;
        });
      }
    });

    Timer(const Duration(milliseconds: 650), () {
      if (mounted && _overlayOpacity == 0.0) {
        setState(() {
          _overlayLetter = null;
        });
      }
    });
  }

  Widget _buildVerticalAlphabetBar(BuildContext context, bool isDark) {
    return Container(
      width: 44,
      margin: const EdgeInsets.only(left: 6.0, right: 2.0, bottom: 8.0),
      child: ListView.builder(
        key: const PageStorageKey("vertical_alphabet_bar"),
        itemCount: _alphabet.length,
        padding: const EdgeInsets.only(bottom: 16.0),
        itemBuilder: (context, index) {
          final letter = _alphabet[index];
          final isCurrent = (letter == 'TODOS' && _selectedLetter == null) ||
                            (letter == _selectedLetter);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3.0),
            child: GestureDetector(
              onTap: () => _selectLetter(letter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 32,
                width: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent 
                      ? brandOrange 
                      : (isDark ? const Color(0xFF131A26) : Colors.grey[200]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent 
                        ? brandOrange 
                        : (isDark ? Colors.white10 : Colors.black12),
                    width: 1.0,
                  ),
                ),
                child: Text(
                  letter == 'TODOS' ? 'All' : letter,
                  style: TextStyle(
                    color: isCurrent ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: FontWeight.bold,
                    fontSize: letter == 'TODOS' ? 9 : 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showImages = prefs.getBool('inventory_show_images') ?? false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _inventoryTab = widget.initialTab;
    _searchQuery = widget.searchQuery ?? "";
    _searchController.text = _searchQuery;
    _loadPreferences();
    _refreshData().then((_) => _syncEverything(silent: true));
    // Sincronización automática periódica en tiempo real (cada 2 segundos)
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && !_isSyncing) {
        _syncEverything(silent: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery) {
      setState(() {
        _searchQuery = widget.searchQuery ?? "";
        _searchController.text = _searchQuery;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _syncTimer?.cancel();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    final artData = await DatabaseHelper.instance.queryAllArticulos();
    if (mounted) {
      setState(() {
        _articulos = artData.map((e) => Articulo.fromMap(e)).toList();
        if (!silent) _isLoading = false;
      });
    }
  }

  Future<void> _refreshArticulos() async {
    final data = await DatabaseHelper.instance.queryAllArticulos();
    if (mounted) {
      setState(() {
        _articulos = data.map((e) => Articulo.fromMap(e)).toList();
      });
    }
  }

  void _abrirSeleccionArte() async {
    final products = _drive.inMemoryProducts.where((p) => p.estado.trim().toLowerCase() == 'listo').toList();
    
    final Articulo? artSeleccionado = await Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/inventario/seleccionar_arte'),
        builder: (context) => SeleccionarArteScreen(products: products),
      ),
    );

    if (artSeleccionado != null && mounted) {
      _abrirEditarArticuloScreen(artSeleccionado);
    }
  }

  void _abrirEditarArticuloScreen([Articulo? art]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/inventario/editar'),
        builder: (context) => EditarArticuloScreen(articulo: art),
      ),
    );
    if (result == true) {
      _refreshArticulos();
    }
  }

  void _abrirAgregarArticuloScreen() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/inventario/agregar'),
        builder: (context) => const EditarArticuloScreen(articulo: null),
      ),
    );
    if (result == true) {
      _refreshArticulos();
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
              primary: brandOrange,
              onPrimary: Colors.black,
              surface: Color(0xFF161A22),
              onSurface: Colors.white,
            ),
          ) : ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: brandOrange,
              onPrimary: Colors.white,
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

  Future<void> _exportarExcel(List<Articulo> articulosParaExportar) async {
    final List<List<String>> rows = [
      ["ID", "Nombre", "Precio Unitario (Bs)", "Precio Caja (Bs)", "Unidad de Medida", "Proveedor", "Código de Caja", "Categoría/Familia", "Subcategoría", "Fecha Registro", "Stock Total", "Descripción"]
    ];

    for (var art in articulosParaExportar) {
      int totalStock = 0;
      if (art.stockJson != null && art.stockJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(art.stockJson!);
          if (decoded is Map) {
            decoded.values.forEach((v) {
              if (v is Map) {
                v.values.forEach((subV) => totalStock += (int.tryParse(subV.toString()) ?? 0));
              } else if (v is! bool) {
                totalStock += (int.tryParse(v.toString()) ?? 0);
              }
            });
          }
        } catch (_) {}
      }

      rows.add([
        art.id?.toString() ?? '',
        art.nombre,
        art.precio.toStringAsFixed(2),
        art.precioCaja.toStringAsFixed(2),
        art.unidad,
        art.proveedor ?? 'Novaled',
        art.codCaja ?? '',
        art.familia,
        art.subcategoria,
        art.fecha,
        totalStock.toString(),
        art.descripcion.replaceAll('\n', ' ').replaceAll(';', ','),
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
        final file = File('${tempDir.path}/inventario_novaled.csv');
        await file.writeAsBytes(utf8.encode(csv));
        
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Inventario Novaled',
          text: 'Exportación del Inventario de Productos Novaled.',
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

  void _confirmDelete(Articulo art) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        title: Text("¿Eliminar?", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
        content: Text("Se borrará '${art.nombre}'", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
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
                          const CircularProgressIndicator(color: brandOrange),
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
                // 1. Registrar borrado localmente para sincronización
                if (art.folderId != null && art.folderId!.isNotEmpty) {
                  await DatabaseHelper.instance.recordDeletion('articulos', art.folderId!);
                }
                
                // 2. Borrar de la base de datos local
                await DatabaseHelper.instance.deleteArticulo(art.id!);
                await _refreshArticulos();
                
                // 3. Sincronización silenciosa para refrescar
                await _syncEverything(silent: true);
              } finally {
                // Cerrar diálogo de procesamiento
                if (mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text("S", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionActionBar(List<Articulo> filteredArticulos) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCount = _selectedArticleIds.length;
    final allSelected = filteredArticulos.isNotEmpty && filteredArticulos.every((a) => _selectedArticleIds.contains(a.id));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: brandOrange.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brandOrange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () {
              setState(() {
                _isSelectionMode = false;
                _selectedArticleIds.clear();
              });
            },
            tooltip: "Cancelar selección",
          ),
          const SizedBox(width: 8),
          Text(
            "$selectedCount seleccionados",
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              allSelected ? Icons.check_box : Icons.check_box_outline_blank,
              color: brandOrange,
            ),
            tooltip: allSelected ? "Deseleccionar todos" : "Seleccionar todos",
            onPressed: () {
              setState(() {
                if (allSelected) {
                  for (var art in filteredArticulos) {
                    if (art.id != null) {
                      _selectedArticleIds.remove(art.id!);
                    }
                  }
                } else {
                  for (var art in filteredArticulos) {
                    if (art.id != null) {
                      _selectedArticleIds.add(art.id!);
                    }
                  }
                }
              });
            },
          ),
          IconButton(
            icon: Icon(
              Icons.delete,
              color: selectedCount > 0 ? Colors.redAccent : Colors.grey,
            ),
            tooltip: "Eliminar seleccionados",
            onPressed: selectedCount > 0 ? _deleteSelectedArticles : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSelectionBar(List<Articulo> filteredArticulos) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCount = _selectedArticleIds.length;
    final allSelected = filteredArticulos.isNotEmpty && filteredArticulos.every((a) => _selectedArticleIds.contains(a.id));

    return Container(
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
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom > 0
            ? MediaQuery.of(context).padding.bottom + 8
            : 12,
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: () {
              setState(() {
                _isSelectionMode = false;
                _selectedArticleIds.clear();
              });
            },
            child: Text(
              "Cancelar",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "$selectedCount selec.",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(
              allSelected ? Icons.check_box : Icons.check_box_outline_blank,
              color: brandOrange,
            ),
            tooltip: allSelected ? "Deseleccionar todos" : "Seleccionar todos",
            onPressed: () {
              setState(() {
                if (allSelected) {
                  for (var art in filteredArticulos) {
                    if (art.id != null) {
                      _selectedArticleIds.remove(art.id!);
                    }
                  }
                } else {
                  for (var art in filteredArticulos) {
                    if (art.id != null) {
                      _selectedArticleIds.add(art.id!);
                    }
                  }
                }
              });
            },
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: selectedCount > 0 ? _deleteSelectedArticles : null,
            icon: const Icon(Icons.delete, color: Colors.white, size: 18),
            label: const Text(
              "ELIMINAR",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              disabledBackgroundColor: isDark ? Colors.white12 : Colors.grey[300],
              disabledForegroundColor: isDark ? Colors.white30 : Colors.grey[500],
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelectedArticles() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCount = _selectedArticleIds.length;
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        title: Text("¿Eliminar artículos?", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
        content: Text("Se borrarán los $selectedCount artículos seleccionados de forma definitiva del catálogo y la nube.", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text("NO")),
          TextButton(
            onPressed: () => Navigator.pop(confirmCtx, true),
            child: const Text("ELIMINAR", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
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
                const CircularProgressIndicator(color: brandOrange),
                const SizedBox(width: 20),
                Text(
                  "Eliminando $selectedCount artículos...",
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final dbHelper = DatabaseHelper.instance;
      for (int id in _selectedArticleIds) {
        final art = _articulos.firstWhere((a) => a.id == id, orElse: () => Articulo(nombre: "", precio: 0.0, descripcion: ""));
        if (art.id != null) {
          if (art.folderId != null && art.folderId!.isNotEmpty) {
            await dbHelper.recordDeletion('articulos', art.folderId!);
          }
          await dbHelper.deleteArticulo(art.id!);
        }
      }
      
      setState(() {
        _isSelectionMode = false;
        _selectedArticleIds.clear();
      });
      
      await _refreshArticulos();
      
      await _syncEverything(silent: true);
    } catch (e) {
      debugPrint("Error al eliminar artículos en lote: $e");
    } finally {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }



  void _mostrarFiltros({
    required BuildContext context,
    required List<String> familias,
    required List<String> proveedores,
    required List<Articulo> filteredArticulos,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    showModalBottomSheet(
      context: context,
      backgroundColor: dialogBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final hasActiveFilters = _selectedFamilia != "Todas" ||
                _selectedProveedor != "Todos" ||
                _selectedStockStatus != "Todos" ||
                _startDate != null ||
                _endDate != null;

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Filtros de Inventario",
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: textColor),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 8),
                  
                  // 1. Categoría
                  Text(
                    "Categoría",
                    style: TextStyle(
                      color: textColor.withOpacity(0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedFamilia,
                    dropdownColor: dialogBg,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: brandOrange, width: 2.0),
                      ),
                    ),
                    items: familias.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedFamilia = val ?? "Todas";
                      });
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 16),

                  // 2. Proveedor
                  Text(
                    "Proveedor",
                    style: TextStyle(
                      color: textColor.withOpacity(0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedProveedor,
                    dropdownColor: dialogBg,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: brandOrange, width: 2.0),
                      ),
                    ),
                    items: proveedores.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedProveedor = val ?? "Todos";
                      });
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 16),

                  // 3. Stock
                  Text(
                    "Stock",
                    style: TextStyle(
                      color: textColor.withOpacity(0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedStockStatus,
                    dropdownColor: dialogBg,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: brandOrange, width: 2.0),
                      ),
                    ),
                    items: ["Todos", "Con Stock", "Sin Stock"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedStockStatus = val ?? "Todos";
                      });
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 16),

                  // 4. Visualizar imágenes Switch
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "Visualizar imágenes",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: _showImages,
                    activeColor: brandOrange,
                    onChanged: (val) async {
                      setState(() {
                        _showImages = val;
                      });
                      setSheetState(() {});
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('inventory_show_images', val);
                    },
                  ),
                  const SizedBox(height: 8),

                  // 5. Date Range Selector
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            _seleccionarRangoFechas();
                            Future.delayed(const Duration(seconds: 2), () {
                              if (context.mounted) {
                                setSheetState(() {});
                              }
                            });
                          },
                          icon: const Icon(Icons.calendar_today, size: 16, color: brandOrange),
                          label: Text(
                            _startDate != null && _endDate != null
                                ? "${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}"
                                : "Filtrar por Fechas",
                            style: TextStyle(color: textColor, fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      if (_startDate != null || _endDate != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.redAccent),
                          onPressed: () {
                            setState(() {
                              _startDate = null;
                              _endDate = null;
                            });
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      if (hasActiveFilters) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedFamilia = "Todas";
                                _selectedProveedor = "Todos";
                                _selectedStockStatus = "Todos";
                                _startDate = null;
                                _endDate = null;
                              });
                              setSheetState(() {});
                            },
                            icon: const Icon(Icons.filter_alt_off, color: Colors.redAccent),
                            label: const Text("Limpiar", style: TextStyle(color: Colors.redAccent)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _exportarExcel(filteredArticulos);
                          },
                          icon: const Icon(Icons.file_download, size: 20, color: Colors.black),
                          label: const Text("EXPORTAR EXCEL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    // Calcular las opciones dinámicas para filtros
    final familias = ["Todas"] + _articulos.map((a) => a.familia.trim()).where((f) => f.isNotEmpty).toSet().toList();
    final proveedores = ["Todos"] + _articulos.map((a) => (a.proveedor ?? 'Novaled').trim()).where((p) => p.isNotEmpty).toSet().toList();

    // Validar estados por si se actualiza la lista
    if (!familias.contains(_selectedFamilia)) {
      _selectedFamilia = "Todas";
    }
    if (!proveedores.contains(_selectedProveedor)) {
      _selectedProveedor = "Todos";
    }

    final filteredArticulos = _articulos.where((art) {
      // Filtro de Catálogo vs Pre-inventario
      bool isCatalog = false;
      if (art.stockJson != null && art.stockJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(art.stockJson!);
          if (decoded is Map && decoded['isCatalog'] == true) {
            isCatalog = true;
          }
        } catch (_) {}
      }
      
      if (_inventoryTab == 'oficial') {
        if (!isCatalog) return false;
      } else {
        if (isCatalog) return false;
      }
      
      // Filtro de Letra del Abecedario (A-Z)
      if (_selectedLetter != null) {
        final firstChar = art.nombre.trim().toUpperCase();
        if (firstChar.isEmpty || !firstChar.startsWith(_selectedLetter!)) {
          return false;
        }
      }

      // 1. Filtro de Búsqueda de Texto
      final query = _searchQuery.trim().toLowerCase();
      if (query.isNotEmpty) {
        final matchesQuery = art.nombre.toLowerCase().contains(query) ||
               art.descripcion.toLowerCase().contains(query) ||
               art.familia.toLowerCase().contains(query) ||
               art.subcategoria.toLowerCase().contains(query) ||
               (art.proveedor != null && art.proveedor!.toLowerCase().contains(query));
        if (!matchesQuery) return false;
      }

      // 2. Filtro de Familia / Categoría
      if (_selectedFamilia != "Todas" && art.familia.trim() != _selectedFamilia) {
        return false;
      }

      // 3. Filtro de Proveedor
      final prov = art.proveedor ?? 'Novaled';
      if (_selectedProveedor != "Todos" && prov.trim() != _selectedProveedor) {
        return false;
      }

      // 4. Filtro de Estado de Stock
      int totalStock = 0;
      if (art.stockJson != null && art.stockJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(art.stockJson!);
          if (decoded is Map) {
            decoded.values.forEach((v) {
              if (v is Map) {
                v.values.forEach((subV) => totalStock += (int.tryParse(subV.toString()) ?? 0));
              } else if (v is! bool) {
                totalStock += (int.tryParse(v.toString()) ?? 0);
              }
            });
          }
        } catch (_) {}
      }
      if (_selectedStockStatus == "Con Stock" && totalStock <= 0) {
        return false;
      }
      if (_selectedStockStatus == "Sin Stock" && totalStock > 0) {
        return false;
      }

      // 5. Filtro de Fechas
      if (_startDate != null && _endDate != null) {
        if (art.fecha.isEmpty) return false;
        try {
          final artDate = DateTime.parse(art.fecha);
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

    // Map cada artículo ID al correlativo visible
    final Map<int, int> articleIndexMap = {};
    for (int i = 0; i < filteredArticulos.length; i++) {
      final art = filteredArticulos[i];
      if (art.id != null) {
        articleIndexMap[art.id!] = i + 1;
      }
    }

    final dropdownDecoration = InputDecoration(
      filled: true,
      fillColor: isDark ? const Color(0xFF131A26) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: const BorderSide(color: brandOrange, width: 1.5),
      ),
    );

    Widget buildDropdown({
      required String label,
      required String value,
      required List<String> items,
      required ValueChanged<String?> onChanged,
    }) {
      return Container(
        width: 160,
        margin: const EdgeInsets.only(top: 6, right: 12, bottom: 8),
        child: DropdownButtonFormField<String>(
          value: value,
          decoration: dropdownDecoration.copyWith(
            labelText: label,
            labelStyle: const TextStyle(color: brandOrange, fontSize: 11),
          ),
          dropdownColor: isDark ? const Color(0xFF161A22) : Colors.white,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
          icon: const Icon(Icons.arrow_drop_down, color: brandOrange),
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
          icon: const Icon(Icons.calendar_today, size: 16, color: brandOrange),
          label: Text(
            dateText,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
            side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      );
    }

    final hasActiveFilters = _selectedFamilia != "Todas" ||
        _selectedProveedor != "Todos" ||
        _selectedStockStatus != "Todos" ||
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
              _selectedStockStatus = "Todos";
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
          onPressed: () => _exportarExcel(filteredArticulos),
          icon: const Icon(Icons.file_download, size: 20, color: Colors.black),
          label: const Text(
            "EXPORTAR EXCEL",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: widget.hideAppBar ? null : AppBar(
        backgroundColor: brandOrange,
        foregroundColor: Colors.white,
        title: const Text("INVENTARIO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              _isSelectionMode ? Icons.close : Icons.playlist_add_check_rounded,
              color: Colors.white,
            ),
            tooltip: _isSelectionMode ? "Cancelar selección" : "Selección múltiple",
            onPressed: () {
              setState(() {
                _isSelectionMode = !_isSelectionMode;
                if (!_isSelectionMode) {
                  _selectedArticleIds.clear();
                }
              });
            },
          ),
        ],
      ),
      bottomNavigationBar: _isSelectionMode ? _buildBottomSelectionBar(filteredArticulos) : null,
      floatingActionButton: _isSelectionMode ? null : FloatingActionButton(
        heroTag: "btn_manual",
        onPressed: _abrirAgregarArticuloScreen,
        backgroundColor: brandOrange,
        tooltip: "Agregar Manualmente",
        child: const Icon(Icons.add, color: Colors.black, size: 30),
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          if (widget.hideAppBar) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 24.0, right: 16.0, bottom: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _inventoryTab == 'oficial' ? "Inventario Oficial" : "Pre-inventario",
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isSelectionMode ? Icons.close : Icons.playlist_add_check_rounded,
                      color: brandOrange,
                      size: 28,
                    ),
                    tooltip: _isSelectionMode ? "Cancelar" : "Selección Múltiple",
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = !_isSelectionMode;
                        if (!_isSelectionMode) {
                          _selectedArticleIds.clear();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
             Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  final isSearch = child.key == const ValueKey('search_mode');
                  final offsetTween = isSearch
                      ? Tween<Offset>(begin: const Offset(0.2, 0.0), end: Offset.zero)
                      : Tween<Offset>(begin: const Offset(-0.2, 0.0), end: Offset.zero);

                  return SlideTransition(
                    position: offsetTween.animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  );
                },
                child: _showSearchField
                    ? Row(
                        key: const ValueKey('search_mode'),
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              onChanged: (value) {
                                _searchDebounceTimer?.cancel();
                                _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
                                  if (mounted) {
                                    setState(() {
                                      _searchQuery = value;
                                    });
                                  }
                                });
                              },
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              decoration: InputDecoration(
                                hintText: "Buscar por nombre, descripción...",
                                hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600]),
                                prefixIcon: const Icon(Icons.search, color: brandOrange),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, color: Colors.grey),
                                        onPressed: () {
                                          _searchController.clear();
                                          _searchDebounceTimer?.cancel();
                                          setState(() {
                                            _searchQuery = "";
                                          });
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: isDark ? const Color(0xFF131A26) : Colors.white,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10.0),
                                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10.0),
                                  borderSide: const BorderSide(color: brandOrange, width: 2.0),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _showSearchField = false;
                                _searchQuery = "";
                                _searchController.clear();
                              });
                            },
                            child: Text(
                              "Cancelar",
                              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: const ValueKey('tab_mode'),
                        children: [
                          Expanded(
                            child: Container(
                              height: 45,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF131A26) : Colors.grey[200],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _inventoryTab = 'oficial';
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: _inventoryTab == 'oficial'
                                              ? brandOrange
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          "Inventario",
                                          style: TextStyle(
                                            color: _inventoryTab == 'oficial'
                                                ? Colors.black
                                                : (isDark ? Colors.white70 : Colors.black87),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _inventoryTab = 'pre';
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: _inventoryTab == 'pre'
                                              ? brandOrange
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          "Pre Inventario",
                                          style: TextStyle(
                                            color: _inventoryTab == 'pre'
                                                ? Colors.black
                                                : (isDark ? Colors.white70 : Colors.black87),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              Icons.search,
                              color: _showSearchField ? brandOrange : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            onPressed: () {
                              setState(() {
                                _showSearchField = !_showSearchField;
                                if (!_showSearchField) {
                                  _searchQuery = "";
                                  _searchController.clear();
                                }
                              });
                            },
                          ),
                          Stack(
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.filter_list,
                                  color: hasActiveFilters ? brandOrange : (isDark ? Colors.white70 : Colors.black87),
                                ),
                                onPressed: () {
                                  _mostrarFiltros(
                                    context: context,
                                    familias: familias,
                                    proveedores: proveedores,
                                    filteredArticulos: filteredArticulos,
                                  );
                                },
                              ),
                              if (hasActiveFilters)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        if (_articulos.isEmpty) {
                          await _syncEverything();
                        } else {
                          await _refreshData();
                        }
                      },
                      color: brandOrange,
                      backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.grey[200],
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator(color: brandOrange))
                          : filteredArticulos.isEmpty
                              ? Stack(
                                  children: [
                                    ListView(), // Necesario para que el RefreshIndicator funcione
                                    Center(
                                      child: Text(
                                        _searchQuery.isNotEmpty
                                            ? "No se encontraron resultados"
                                            : "No hay artículos. Desliza para sincronizar con la nube.",
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.all(12),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: MediaQuery.of(context).size.width > 900
                                        ? (MediaQuery.of(context).size.width / 220).floor()
                                        : 1, // 1 artículo por fila en móvil (barritas)
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: MediaQuery.of(context).size.width > 900
                                        ? (_showImages ? 0.65 : 1.3)
                                        : (_showImages ? 3.2 : 4.4), // Proporciones para barrita horizontal
                                  ),
                                  itemCount: filteredArticulos.length,
                                  itemBuilder: (context, index) {
                                    final art = filteredArticulos[index];
                                    final globalIdx = articleIndexMap[art.id] ?? 0;
                                    return _buildArticleGridCard(context, art, globalIdx);
                                  },
                                ),
                    ),
                  ),
                  _buildVerticalAlphabetBar(context, isDark),
                ],
              ),
            ),
          ],
        ),
      if (_overlayLetter != null)
        IgnorePointer(
          child: Center(
            child: AnimatedScale(
              scale: _overlayScale,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: _overlayOpacity,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: brandOrange.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _overlayLetter!,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 55,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  ),
);
}

  Future<void> _syncEverything({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _isSyncing = true);
    try {
      final success = await SyncService.instance.syncTable('articulos').timeout(const Duration(seconds: 30));
      await _refreshData(silent: silent);
      if (!silent && mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Inventario sincronizado"), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Error de sincronización"), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint("Error sync inventory: $e");
      if (!silent && mounted) {
        final cleanMsg = e.toString().replaceFirst('Exception: ', '');
        final isOffline = cleanMsg.contains("Modo Offline");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOffline ? cleanMsg : "Error de sincronización: $cleanMsg"),
            backgroundColor: isOffline ? Colors.orange[800] : Colors.red,
            duration: Duration(seconds: isOffline ? 3 : 5),
          ),
        );
      }
    } finally {
      if (!silent && mounted) setState(() => _isSyncing = false);
    }
  }

  // Los encabezados de familia y subcategoría ya no se utilizan en la vista de cuadrícula.

  Widget _buildArticleGridCard(BuildContext context, Articulo art, int globalIdx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth <= 900;
    
    // Calcular stock total
    int totalStock = 0;
    if (art.stockJson != null && art.stockJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(art.stockJson!);
        if (decoded is Map) {
          decoded.values.forEach((v) {
            if (v is Map) {
              v.values.forEach((subV) => totalStock += (int.tryParse(subV.toString()) ?? 0));
            } else {
              totalStock += (int.tryParse(v.toString()) ?? 0);
            }
          });
        }
      } catch (_) {}
    }

    final iconColor = isDark ? Colors.white60 : Colors.black54;
    final isSelected = _selectedArticleIds.contains(art.id);

    // Mobile list style ("1 fila 1 barrita")
    if (isMobile) {
      return _SlidableArticleTile(
        art: art,
        isSelectionMode: _isSelectionMode,
        onEdit: () => _abrirEditarArticuloScreen(art),
        onLocation: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              settings: const RouteSettings(name: '/almacenamiento'),
              builder: (context) => EditarStockScreen(articulo: art),
            ),
          );
        },
        onDelete: () => _confirmDelete(art),
        child: InkWell(
          onTap: () {
            if (_isSelectionMode) {
              setState(() {
                if (isSelected) {
                  _selectedArticleIds.remove(art.id);
                } else {
                  if (art.id != null) {
                    _selectedArticleIds.add(art.id!);
                  }
                }
              });
            } else {
              _abrirEditarArticuloScreen(art);
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              setState(() {
                _isSelectionMode = true;
                if (art.id != null) {
                  _selectedArticleIds.add(art.id!);
                }
              });
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131A26) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected 
                        ? brandOrange 
                        : (isDark ? Colors.white10 : Colors.black12),
                    width: isSelected ? 1.8 : 1.0,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                child: Row(
                  children: [
                    if (_showImages) ...[
                      Container(
                        width: 85,
                        height: 85,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: (art.imagen != null && art.imagen!.isNotEmpty)
                              ? Image.network(
                                  'https://novaledbolivia.com/sistema/api/uploads/${art.imagen}',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey, size: 24),
                                )
                              : (art.folderId != null && art.finalArtId != null && art.finalArtId!.isNotEmpty)
                                  ? _InventoryThumbnail(
                                      folderId: art.folderId!, 
                                      finalArtId: art.finalArtId,
                                      drive: _drive
                                    )
                                  : const Icon(Icons.inventory_2, color: Colors.grey, size: 24),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            art.nombre,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.0,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                "Bs. ${art.precio.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                  color: brandOrange,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: totalStock > 0 
                                      ? const Color(0xFF10B981).withOpacity(0.12)
                                      : Colors.redAccent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  totalStock > 0 ? "Stock: $totalStock" : "Sin Stock",
                                  style: TextStyle(
                                    color: totalStock > 0 ? const Color(0xFF10B981) : Colors.redAccent,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Box código: ${art.codCaja ?? 'S/C'}",
                            style: const TextStyle(color: Colors.grey, fontSize: 9.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            "Proveedor: ${art.proveedor ?? 'Novaled'}",
                            style: const TextStyle(color: Colors.grey, fontSize: 9.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_isSelectionMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? brandOrange : Colors.black45,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.check,
                      color: isSelected ? Colors.black : Colors.transparent,
                      size: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Desktop/Tablet grid style
    final double imageMargin = 12.0;
    final double detailsPadding = 14.0;
    final double titleFontSize = 14.0;
    final double textFontSize = 11.0;
    final double buttonIconSize = 18.0;
    final double buttonPadding = 8.0;

    return InkWell(
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedArticleIds.remove(art.id);
            } else {
              if (art.id != null) {
                _selectedArticleIds.add(art.id!);
              }
            }
          });
        } else {
          _abrirEditarArticuloScreen(art);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            if (art.id != null) {
              _selectedArticleIds.add(art.id!);
            }
          });
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131A26) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected 
                    ? brandOrange 
                    : (isDark ? Colors.white10 : Colors.black12),
                width: isSelected ? 2.0 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_showImages) ...[
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.all(imageMargin),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: (art.imagen != null && art.imagen!.isNotEmpty)
                            ? Image.network(
                                'https://novaledbolivia.com/sistema/api/uploads/${art.imagen}',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey),
                              )
                            : (art.folderId != null && art.finalArtId != null && art.finalArtId!.isNotEmpty)
                                ? _InventoryThumbnail(
                                    folderId: art.folderId!, 
                                    finalArtId: art.finalArtId,
                                    drive: _drive
                                  )
                                : const Icon(Icons.inventory_2, color: Colors.grey, size: 28),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                ],
                
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: detailsPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        art.nombre,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: titleFontSize,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Bs. ${art.precio.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: titleFontSize,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Box código: ${art.codCaja ?? 'S/C'}",
                        style: TextStyle(color: Colors.grey, fontSize: textFontSize),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Proveedor: ${art.proveedor ?? 'Novaled'}",
                        style: TextStyle(color: Colors.grey, fontSize: textFontSize),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      
                      // Badge de Estado/Stock
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          totalStock > 0 ? "Stock: $totalStock" : "Sin Stock",
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontSize: 9.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                
                // Botones de Acción (Pencil, Trash, Link)
                if (!_isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit_outlined, size: buttonIconSize),
                          color: iconColor,
                          onPressed: () => _abrirEditarArticuloScreen(art),
                          tooltip: "Editar Datos",
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.all(buttonPadding),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: buttonIconSize),
                          color: iconColor,
                          onPressed: () => _confirmDelete(art),
                          tooltip: "Eliminar",
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.all(buttonPadding),
                        ),
                        IconButton(
                          icon: Icon(Icons.link, size: buttonIconSize),
                          color: iconColor,
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                settings: const RouteSettings(name: '/almacenamiento'),
                                builder: (context) => EditarStockScreen(articulo: art),
                              ),
                            );
                          },
                          tooltip: "Gestionar Stock",
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 38),
              ],
            ),
          ),
          if (_isSelectionMode)
            Positioned(
              top: 18,
              right: 18,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? brandOrange : Colors.black45,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.check,
                  color: isSelected ? Colors.black : Colors.transparent,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InventoryThumbnail extends StatefulWidget {
  final String folderId;
  final String? finalArtId;
  final DriveService drive;

  const _InventoryThumbnail({
    required this.folderId, 
    this.finalArtId,
    required this.drive
  });

  @override
  State<_InventoryThumbnail> createState() => _InventoryThumbnailState();
}

class _InventoryThumbnailState extends State<_InventoryThumbnail> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _initFuture();
  }

  @override
  void didUpdateWidget(_InventoryThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.folderId != oldWidget.folderId || widget.finalArtId != oldWidget.finalArtId) {
      _initFuture();
    }
  }

  void _initFuture() {
    _future = widget.drive.getProductThumbnail(widget.folderId, widget.finalArtId);
  }


  @override
  Widget build(BuildContext context) {
    final cached = widget.drive.thumbnailCache[widget.folderId];
    if (cached != null) {
      return Image.memory(cached, fit: BoxFit.contain);
    }

    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(snapshot.data!, fit: BoxFit.contain);
        }
        return const Icon(Icons.image, color: Colors.grey, size: 20);
      },
    );
  }
}

abstract class InventoryListItem {}

class FamilyHeaderItem extends InventoryListItem {
  final String name;
  FamilyHeaderItem(this.name);
}

class SubcategoryHeaderItem extends InventoryListItem {
  final String name;
  SubcategoryHeaderItem(this.name);
}

class ArticleItem extends InventoryListItem {
  final Articulo articulo;
  final int globalIndex;
  ArticleItem(this.articulo, this.globalIndex);
}

class _SlidableArticleTile extends StatefulWidget {
  final Articulo art;
  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onLocation;
  final VoidCallback onDelete;
  final bool isSelectionMode;

  const _SlidableArticleTile({
    required this.art,
    required this.child,
    required this.onEdit,
    required this.onLocation,
    required this.onDelete,
    required this.isSelectionMode,
  });

  @override
  State<_SlidableArticleTile> createState() => _SlidableArticleTileState();
}

class _SlidableArticleTileState extends State<_SlidableArticleTile> {
  double _offset = 0;


  @override
  Widget build(BuildContext context) {
    if (widget.isSelectionMode) {
      return widget.child;
    }

    const double maxOffset = -210;

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: () {
                    setState(() => _offset = 0);
                    widget.onEdit();
                  },
                  child: Container(
                    width: 70,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                        SizedBox(height: 4),
                        Text("EDITAR",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() => _offset = 0);
                    widget.onLocation();
                  },
                  child: Container(
                    width: 70,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF97316),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.room_outlined, color: Colors.white, size: 20),
                        SizedBox(height: 4),
                        Text("UBICACIÓN",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() => _offset = 0);
                    widget.onDelete();
                  },
                  child: Container(
                    width: 70,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline, color: Colors.white, size: 20),
                        SizedBox(height: 4),
                        Text("BORRAR",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _offset += details.delta.dx;
              if (_offset > 0) _offset = 0;
              if (_offset < maxOffset) _offset = maxOffset;
            });
          },
          onHorizontalDragEnd: (details) {
            setState(() {
              if (_offset < maxOffset / 2) {
                _offset = maxOffset;
              } else {
                _offset = 0;
              }
            });
          },
          child: Transform.translate(
            offset: Offset(_offset, 0),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
