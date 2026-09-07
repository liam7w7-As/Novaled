import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'main.dart';
import 'inventory_screen.dart';
import 'add_art_screen.dart';
import 'drive_service.dart';
import 'product_model.dart';
import 'login_screen.dart';
import 'personal_manage_screen.dart';
import 'local_module/database_helper.dart';
import 'local_module/services/sync_service.dart';
import 'local_module/tenant_helper.dart';

import 'local_module/screens/clients_screen.dart';
import 'local_module/screens/almacenamiento_screen.dart';
import 'local_module/screens/almacenamiento_configuracion_screen.dart';
import 'local_module/screens/cotizaciones_screen.dart';
import 'local_module/screens/crear_cotizacion_screen.dart';
import 'local_module/screens/crear_nota_entrega_screen.dart';
import 'local_module/services/pdf_service.dart';
import 'local_module/services/update_service.dart';
import 'local_module/models/item_cotizacion.dart';
import 'package:printing/printing.dart';
import 'local_module/screens/notas_entrega_screen.dart';
import 'local_module/screens/inventory_screen.dart' as local_inv;
import 'local_module/screens/venta_institucional_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DriveService _drive = DriveService();
  List<Product> _allProducts = [];
  List<Product> _preInventoryProducts = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  final session = Session();
  final GlobalKey<ScaffoldState> _mobileScaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _syncTimer;
  Timer? _searchDebounceTimer;

  // Dashboard active tab (Web only)
  String _activeTab = 'cotizaciones'; // 'inicio', 'cotizaciones', 'catalogo', 'foto_a_arte', 'personal', 'clientes', 'almacenamiento'
  bool _isOtrosExpanded = false;
  bool _isAlmacenamientoExpanded = false;
  bool _isInventarioExpanded = false;
  String _documentFilter = 'todas'; // 'todas', 'sin_nota', 'con_nota'
  String _searchQuery = '';
  final TextEditingController _headerSearchController = TextEditingController();
  String? _expandedCard;
  String _selectedReportPeriod = 'mes';
  DateTime _selectedReportMonthDate = DateTime.now();
  DateTime _selectedReportWeekDate = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
  DateTime _selectedReportTodayDate = DateTime.now();
  DateTimeRange? _customDateRange;
  DateTime _selectedMobileDate = DateTime.now();
  String _selectedStatsPeriod = 'Semana';
  final ScrollController _mobileDateScrollController = ScrollController();
  String _selectedReportSeller = 'todos';
  double _reportProfitMargin = 30.0;
  List<String> _vendedoresSistema = [];
  List<String> _sellersOnly = [];

  List<Map<String, dynamic>> _cotizaciones = [];
  List<Map<String, dynamic>> _notasEntrega = [];
  List<Map<String, dynamic>> _proformas = [];
  List<Map<String, dynamic>> _clientesList = [];
  String? _customCompanyLogoPath;

  List<Map<String, dynamic>> _getVentasEfectivas() {
    final Map<String, Map<String, dynamic>> map = {};
    
    // A. Notas de Entrega (todas cuentan como ventas efectivas)
    for (var n in _notasEntrega) {
      final key = (n['uuid']?.toString().isNotEmpty == true) ? n['uuid'].toString() : 'ne_${n['id']}';
      map[key] = n;
    }
    
    // B. Proformas / Punto de Venta (sólo con estado PAGADO)
    for (var p in _proformas) {
      final st = (p['estado_pago'] ?? p['estado'] ?? '').toString().toLowerCase().trim();
      if (st == 'pagado' || st == 'aprobado' || st == 'completado') {
        final key = (p['uuid']?.toString().isNotEmpty == true) ? p['uuid'].toString() : 'prof_${p['id']}';
        map[key] = p;
      }
    }
    
    // C. Cotizaciones de Punto de Venta con estado PAGADO
    for (var c in _cotizaciones) {
      final tv = (c['tipo_venta'] ?? '').toString().toLowerCase().trim();
      final td = (c['tipo_documento'] ?? '').toString().toLowerCase().trim();
      if (tv == 'punto_venta' || td == 'nota_venta' || td == 'proforma') {
        final st = (c['estado_pago'] ?? c['estado'] ?? '').toString().toLowerCase().trim();
        if (st == 'pagado' || st == 'aprobado' || st == 'completado') {
          final key = (c['uuid']?.toString().isNotEmpty == true) ? c['uuid'].toString() : 'cot_${c['id']}';
          map[key] = c;
        }
      }
    }
    
    return map.values.toList();
  }

  @override
  void initState() {
    super.initState();
    SessionWatchdog.start();
    _initData();
    TenantHelper.syncTenantSettings().then((_) {
      if (mounted) {
        try {
          NovaledApp.of(context).reloadBrandColor();
        } catch (_) {}
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.buscarActualizacion(context, silent: true);
    });
    _headerSearchController.addListener(() {
      _searchDebounceTimer?.cancel();
      _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _searchQuery = _headerSearchController.text;
          });
        }
      });
    });
    // Temporizador periódico silencioso cada 90 segundos para actualizar contadores sin sobrecargar la UI
    _syncTimer = Timer.periodic(const Duration(seconds: 90), (timer) {
      if (mounted && !_isSyncing) {
        _loadAll(showLoading: false, preventSignIn: true);
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _headerSearchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _sortDocuments(List<Map<String, dynamic>> list) {
    final mutable = List<Map<String, dynamic>>.from(list);
    mutable.sort((a, b) {
      // 1. Fecha descendente (más recientes primero)
      final dateA = a['fecha']?.toString() ?? '';
      final dateB = b['fecha']?.toString() ?? '';
      final dateComp = dateB.compareTo(dateA);
      if (dateComp != 0) return dateComp;
      
      // 2. ID descendente
      final idA = a['id'] as int? ?? 0;
      final idB = b['id'] as int? ?? 0;
      final idComp = idB.compareTo(idA);
      if (idComp != 0) return idComp;
      
      // 3. Nombre del cliente (alfabético)
      final nameA = (a['clienteNombre'] ?? '').toString().toLowerCase();
      final nameB = (b['clienteNombre'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });
    return mutable;
  }

  Future<void> _initData() async {
    // 1. Cargar caché inmediatamente
    final cache = await _drive.getLocalCache();
    final preCache = await _drive.getPreInventoryProducts();
    final quotes = await DatabaseHelper.instance.queryAllCotizaciones();
    final notes = await DatabaseHelper.instance.queryAllNotasEntrega();
    final clients = await DatabaseHelper.instance.queryAllClientes();
    final sortedQuotes = _sortDocuments(quotes);
    final sortedNotes = _sortDocuments(notes);
    if (mounted) {
      setState(() {
        _allProducts = cache;
        _preInventoryProducts = preCache;
        _cotizaciones = sortedQuotes;
        _notasEntrega = sortedNotes;
        _clientesList = clients;
        _isLoading = false;
      });
    }
    // 2. Sincronizar (Drive y MySQL) silenciosamente
    _loadAll(showLoading: cache.isEmpty && preCache.isEmpty, preventSignIn: true);
  }

  Future<void> _loadVendedoresSistema() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUsersStr = prefs.getString('novaled_custom_users');
      final Set<String> allUsersSet = {'Dueño'};
      final Set<String> sellersOnlySet = {'joel'}; // Ensure joel is always treated as a seller
      
      try {
        final token = prefs.getString('novaled_jwt_token') ?? '';
        final response = await http.get(
          Uri.parse('https://novaledbolivia.com/sistema/api/get_users.php'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final List<dynamic> usersList = jsonDecode(response.body);
          await prefs.setString('novaled_custom_users', response.body);
          for (var u in usersList) {
            final name = u['username']?.toString();
            final role = u['role']?.toString().toLowerCase().trim();
            if (name != null && name.isNotEmpty) {
              allUsersSet.add(name);
              if (role == 'seller') {
                sellersOnlySet.add(name);
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Error fetching fresh users list: $e");
        if (cachedUsersStr != null) {
          final List<dynamic> usersList = jsonDecode(cachedUsersStr);
          for (var u in usersList) {
            final name = u['username']?.toString();
            final role = u['role']?.toString().toLowerCase().trim();
            if (name != null && name.isNotEmpty) {
              allUsersSet.add(name);
              if (role == 'seller') {
                sellersOnlySet.add(name);
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _vendedoresSistema = allUsersSet.toList()..sort();
          _sellersOnly = sellersOnlySet.toList()..sort();
        });
      }
    } catch (e) {
      debugPrint("Error loading vendedores sistema: $e");
    }
  }

  Future<void> _loadAll({bool showLoading = true, bool forceSignIn = false, bool preventSignIn = false}) async {
    if (showLoading) {
      if (mounted) setState(() => _isSyncing = true);
      if (_allProducts.isEmpty && _preInventoryProducts.isEmpty) {
        if (mounted) setState(() => _isLoading = true);
      }
    }

    // Limpiar caché en memoria para que no se mezcle información entre inquilinos
    _drive.clearMemoryCache();

    // 1. Cargar datos locales inmediatamente
    try {
      final prefs = await SharedPreferences.getInstance();
      final tenantKey = await TenantHelper.getActiveTenantKey();
      final customLogoP = prefs.getString(TenantHelper.k('pdf_company_logo_path', tenantKey));
      final list = await _drive.getLocalCache();
      final preList = await _drive.getPreInventoryProducts();
      final quotes = await DatabaseHelper.instance.queryAllCotizaciones();
      final notes = await DatabaseHelper.instance.queryAllNotasEntrega();
      final proformas = await DatabaseHelper.instance.queryAllProformas();
      final clients = await DatabaseHelper.instance.queryAllClientes();
      final sortedQuotes = _sortDocuments(quotes);
      final sortedNotes = _sortDocuments(notes);
      final sortedProformas = _sortDocuments(proformas);

      if (mounted) {
        setState(() {
          _customCompanyLogoPath = customLogoP;
          _allProducts = list;
          _preInventoryProducts = preList;
          _cotizaciones = sortedQuotes;
          _notasEntrega = sortedNotes;
          _proformas = sortedProformas;
          _clientesList = clients;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading initial local data: $e");
    }

    // 2. Sincronizar en segundo plano sin bloquear el hilo principal
    Future.microtask(() async {
      try {
        final isNovaled = await TenantHelper.isActiveNovaled();
        if (isNovaled) {
          // Sincronizar catálogo de Google Drive a SQLite (Solo Novaled)
          await _drive.syncDriveCatalogToSQLite();

          // Sincronizar con MySQL de Hostinger (Solo Novaled)
          await SyncService.instance.syncEverything();
        }
        
        // Recargar con datos actualizados post-sync
        final list = await _drive.getLocalCache();
        final preList = await _drive.getPreInventoryProducts();
        final quotes = await DatabaseHelper.instance.queryAllCotizaciones();
        final notes = await DatabaseHelper.instance.queryAllNotasEntrega();
        final proformas = await DatabaseHelper.instance.queryAllProformas();
        final clients = await DatabaseHelper.instance.queryAllClientes();
        final sortedQuotes = _sortDocuments(quotes);
        final sortedNotes = _sortDocuments(notes);
        final sortedProformas = _sortDocuments(proformas);

        if (mounted) {
          setState(() {
            _allProducts = list;
            _preInventoryProducts = preList;
            _cotizaciones = sortedQuotes;
            _notasEntrega = sortedNotes;
            _proformas = sortedProformas;
            _clientesList = clients;
            _isLoading = false;
            _isSyncing = false;
          });
        }
        await _loadVendedoresSistema();
      } catch (e) {
        debugPrint("Error en segundo plano sync: $e");
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSyncing = false;
          });
        }
      }
    });
  }

  bool _tieneNotaEntrega(Map<String, dynamic> cot) {
    final cliente = cot['clienteNombre']?.toString().trim().toLowerCase();
    if (cliente == null || cliente.isEmpty) return false;
    final total = (cot['total'] as num?)?.toDouble() ?? 0.0;
    
    return _notasEntrega.any((nota) {
      final notaCliente = nota['clienteNombre']?.toString().trim().toLowerCase();
      final notaTotal = (nota['total'] as num?)?.toDouble() ?? 0.0;
      return notaCliente == cliente && (notaTotal - total).abs() < 0.01;
    });
  }

  Map<String, dynamic>? _getNotaEntregaAsociada(Map<String, dynamic> cot) {
    final cliente = cot['clienteNombre']?.toString().trim().toLowerCase();
    if (cliente == null || cliente.isEmpty) return null;
    final total = (cot['total'] as num?)?.toDouble() ?? 0.0;
    
    try {
      return _notasEntrega.firstWhere((nota) {
        final notaCliente = nota['clienteNombre']?.toString().trim().toLowerCase();
        final notaTotal = (nota['total'] as num?)?.toDouble() ?? 0.0;
        return notaCliente == cliente && (notaTotal - total).abs() < 0.01;
      });
    } catch (_) {
      return null;
    }
  }

  void _duplicarCotizacion(Map<String, dynamic> cot) async {
    final canCreate = await PlanLimitHelper.canCreateCotizacion();
    if (!canCreate) {
      if (mounted) {
        PlanLimitHelper.showUpgradeDialog(context, feature: "cotizaciones", currentLimit: PlanLimitHelper.freeCotizaciones);
      }
      return;
    }

    final Map<String, dynamic> nueva = Map.from(cot);
    nueva.remove('id');
    nueva.remove('uuid');
    nueva['fecha'] = DateTime.now().toString().split('.')[0];

    await DatabaseHelper.instance.insertCotizacion(nueva);
    _loadAll();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Cotización duplicada con éxito"), backgroundColor: Colors.blueGrey),
    );
  }

  void _llevarANotaEntrega(Map<String, dynamic> cot) async {
    final canCreate = await PlanLimitHelper.canCreateNotaEntrega();
    if (!canCreate) {
      if (mounted) {
        PlanLimitHelper.showUpgradeDialog(context, feature: "notas de entrega", currentLimit: PlanLimitHelper.freeNotasEntrega);
      }
      return;
    }

    final Map<String, dynamic> nuevaNota = Map.from(cot);
    nuevaNota.remove('id');
    nuevaNota['fecha'] = DateTime.now().toString().split('.')[0];
    nuevaNota['terminos'] =
        "• Recibí conforme los productos detallados.\n• No se aceptan devoluciones después de 48 hrs.\n• La mercadería viaja por cuenta y riesgo del cliente.";

    await DatabaseHelper.instance.insertNotaEntrega(nuevaNota);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Enviado a Notas de Entrega con éxito"),
        backgroundColor: Colors.green,
      ),
    );
    _loadAll();
  }

  Future<void> _verPDFCotizacion(Map<String, dynamic> cot, int displayId) async {
    if (!mounted) return;
    bool dialogColor = true;

    final List<dynamic> itemsList = jsonDecode(cot['itemsJson'] ?? '[]');
    final List<ItemCotizacion> items = itemsList.map((itemMap) => ItemCotizacion.fromMap(itemMap)).toList();
    final double subtotalOriginal = items.fold(0.0, (sum, item) => sum + item.totalOriginal);
    final double ahorroItems = items.fold(0.0, (sum, item) => sum + item.ahorro);
    
    final String clienteNombre = cot['clienteNombre'] ?? "";
    final double total = (cot['total'] as num?)?.toDouble() ?? 0.0;
    final double descuentoGlobal = (cot['descuento'] as num?)?.toDouble() ?? 0.0;
    final String notas = cot['notas'] ?? "";
    final String terminos = cot['terminos'] ?? "";
    final int docId = displayId;
    final bool incluyeFirmaEmpresa = (cot['incluyeFirmaEmpresa'] ?? 0) == 1;
    final bool incluyeFirmaCliente = (cot['incluyeFirmaCliente'] ?? 0) == 1;
    final bool mostrarTerminos = (cot['mostrarTerminos'] ?? 1) == 1;
    final bool mostrarAhorro = false;
    final String fecha = cot['fecha'] ?? "";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
                title: Text("Previsualización de Cotización #$docId", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  Row(
                    children: [
                      Text("Color", style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
                      Switch(
                        value: dialogColor,
                        activeColor: const Color(0xFF00ADEF),
                        onChanged: (val) {
                          setDialogState(() {
                            dialogColor = val;
                          });
                        },
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.print, color: Color(0xFF00ADEF)),
                    onPressed: () async {
                      final currentBytes = await PdfService.generateCotizacionBytes(
                        clienteNombre: clienteNombre,
                        items: items,
                        subtotalOriginal: subtotalOriginal,
                        ahorroItems: ahorroItems,
                        descuentoGlobal: descuentoGlobal,
                        total: total,
                        notas: notas,
                        terminos: terminos,
                        docId: docId,
                        incluyeFirmaEmpresa: incluyeFirmaEmpresa,
                        incluyeFirmaCliente: incluyeFirmaCliente,
                        mostrarAhorro: mostrarAhorro,
                        mostrarTerminos: mostrarTerminos,
                        isColor: dialogColor,
                        fecha: fecha,
                        sucursal: cot['sucursal']?.toString() ?? '#818',
                      );
                      await Printing.layoutPdf(onLayout: (_) => currentBytes);
                    },
                  ),
                ],
              ),
              body: InteractiveViewer(
                child: PdfPreview(
                  build: (format) => PdfService.generateCotizacionBytes(
                    clienteNombre: clienteNombre,
                    items: items,
                    subtotalOriginal: subtotalOriginal,
                    ahorroItems: ahorroItems,
                    descuentoGlobal: descuentoGlobal,
                    total: total,
                    notas: notas,
                    terminos: terminos,
                    docId: docId,
                    incluyeFirmaEmpresa: incluyeFirmaEmpresa,
                    incluyeFirmaCliente: incluyeFirmaCliente,
                    mostrarAhorro: mostrarAhorro,
                    mostrarTerminos: mostrarTerminos,
                    isColor: dialogColor,
                    fecha: fecha,
                    sucursal: cot['sucursal']?.toString() ?? '#818',
                  ),
                  useActions: false,
                  previewPageMargin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  pdfPreviewPageDecoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [],
                  ),
                  scrollViewDecoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F1F1F) : Theme.of(context).scaffoldBackgroundColor,
                  ),
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _verPDFNotaEntrega(Map<String, dynamic> nota, int displayId) async {
    if (!mounted) return;
    bool dialogColor = true;

    final List<dynamic> itemsList = jsonDecode(nota['itemsJson'] ?? '[]');
    final List<ItemCotizacion> items = itemsList.map((itemMap) => ItemCotizacion.fromMap(itemMap)).toList();
    final double subtotalOriginal = items.fold(0.0, (sum, item) => sum + item.totalOriginal);
    final double ahorroItems = items.fold(0.0, (sum, item) => sum + item.ahorro);
    
    final String clienteNombre = nota['clienteNombre'] ?? "";
    final double total = (nota['total'] as num?)?.toDouble() ?? 0.0;
    final double descuentoGlobal = (nota['descuento'] as num?)?.toDouble() ?? 0.0;
    final String notas = nota['notas'] ?? "";
    final String terminos = nota['terminos'] ?? "";
    final int docId = displayId;
    final bool incluyeFirmaEmpresa = (nota['incluyeFirmaEmpresa'] ?? 0) == 1;
    final bool incluyeFirmaCliente = (nota['incluyeFirmaCliente'] ?? 0) == 1;
    final bool mostrarTerminos = (nota['mostrarTerminos'] ?? 1) == 1;
    final String fecha = nota['fecha'] ?? "";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
                title: Text("Previsualización de Nota de Entrega #$docId", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  Row(
                    children: [
                      Text("Color", style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
                      Switch(
                        value: dialogColor,
                        activeColor: const Color(0xFF00ADEF),
                        onChanged: (val) {
                          setDialogState(() {
                            dialogColor = val;
                          });
                        },
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.print, color: Color(0xFF00ADEF)),
                    onPressed: () async {
                      final currentBytes = await PdfService.generateCotizacionBytes(
                        clienteNombre: clienteNombre,
                        items: items,
                        subtotalOriginal: subtotalOriginal,
                        ahorroItems: ahorroItems,
                        descuentoGlobal: descuentoGlobal,
                        total: total,
                        notas: notas,
                        terminos: terminos,
                        docId: docId,
                        incluyeFirmaEmpresa: incluyeFirmaEmpresa,
                        incluyeFirmaCliente: incluyeFirmaCliente,
                        mostrarTerminos: mostrarTerminos,
                        isColor: dialogColor,
                        fecha: fecha,
                        tituloDocumento: "NOTA DE ENTREGA",
                        sucursal: nota['sucursal']?.toString() ?? '#818',
                      );
                      await Printing.layoutPdf(onLayout: (_) => currentBytes);
                    },
                  ),
                ],
              ),
              body: InteractiveViewer(
                child: PdfPreview(
                  build: (format) => PdfService.generateCotizacionBytes(
                    clienteNombre: clienteNombre,
                    items: items,
                    subtotalOriginal: subtotalOriginal,
                    ahorroItems: ahorroItems,
                    descuentoGlobal: descuentoGlobal,
                    total: total,
                    notas: notas,
                    terminos: terminos,
                    docId: docId,
                    incluyeFirmaEmpresa: incluyeFirmaEmpresa,
                    incluyeFirmaCliente: incluyeFirmaCliente,
                    mostrarTerminos: mostrarTerminos,
                    isColor: dialogColor,
                    fecha: fecha,
                    tituloDocumento: "NOTA DE ENTREGA",
                    sucursal: nota['sucursal']?.toString() ?? '#818',
                  ),
                  useActions: false,
                  previewPageMargin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  pdfPreviewPageDecoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [],
                  ),
                  scrollViewDecoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F1F1F) : Theme.of(context).scaffoldBackgroundColor,
                  ),
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileQuoteList(List<Map<String, dynamic>> quotes, bool isDark, Color primaryCyan) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: quotes.length,
      itemBuilder: (context, index) {
        final quote = quotes[index];
        final int quoteId = quote['id'] as int? ?? 0;
        final displayId = _cotizaciones.length - _cotizaciones.indexWhere((c) => c['id'] == quoteId);
        final formattedId = "#$displayId";
        final cliente = quote['clienteNombre']?.toString() ?? "Sin cliente";
        final fecha = quote['fecha']?.toString() ?? "Sin fecha";
        final totalVal = (quote['total'] as num?)?.toDouble() ?? 0.0;
        final totalStr = totalVal.toStringAsFixed(2);
        final hasNote = _tieneNotaEntrega(quote);

        return Card(
          elevation: 1.5,
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: isDark ? const Color(0xFF131A26) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onTap: () => _mostrarOpcionesDocumento(quote, displayId),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    cliente,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formattedId,
                  style: TextStyle(
                    color: primaryCyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      fecha,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      "$totalStr Bs",
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasNote 
                        ? Colors.green.withOpacity(0.12) 
                        : Colors.blueGrey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: hasNote 
                          ? Colors.green.withOpacity(0.3) 
                          : Colors.blueGrey.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasNote ? Icons.local_shipping : Icons.receipt_long,
                        color: hasNote ? Colors.green : Colors.grey,
                        size: 11,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasNote ? "Nota de Entrega" : "Cotización",
                        style: TextStyle(
                          color: hasNote ? Colors.green : Colors.grey,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _mostrarOpcionesDocumento(Map<String, dynamic> cot, int displayId) {
    final hasNote = _tieneNotaEntrega(cot);
    final associatedNote = _getNotaEntregaAsociada(cot);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext c) {
        final isDark = Theme.of(c).brightness == Brightness.dark;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Opciones para Cotización #$displayId",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                title: const Text("Ver PDF Cotización"),
                onTap: () {
                  Navigator.pop(c);
                  _verPDFCotizacion(cot, displayId);
                },
              ),
              if (hasNote && associatedNote != null)
                ListTile(
                  leading: const Icon(Icons.local_shipping, color: Colors.green),
                  title: const Text("Ver PDF Nota de Entrega"),
                  onTap: () {
                    Navigator.pop(c);
                    _verPDFNotaEntrega(associatedNote, displayId);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text("Editar Cotización"),
                onTap: () {
                  Navigator.pop(c);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CrearCotizacionScreen(cotizacionExistente: cot, displayId: displayId),
                    ),
                  ).then((_) => _loadAll());
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.blueAccent),
                title: const Text("Duplicar Cotización"),
                onTap: () {
                  Navigator.pop(c);
                  _duplicarCotizacion(cot);
                },
              ),
              if (!hasNote) ...[
                ListTile(
                  leading: const Icon(Icons.local_shipping, color: Colors.greenAccent),
                  title: const Text("Llevar a Nota de Entrega"),
                  onTap: () {
                    Navigator.pop(c);
                    _llevarANotaEntrega(cot);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_shopping_cart, color: Colors.orange),
                  title: const Text("Convertir a Nota de Entrega (Manual)"),
                  onTap: () {
                    Navigator.pop(c);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CrearNotaEntregaScreen(
                          notaExistente: null,
                          displayId: _notasEntrega.length + 1,
                          convertFromQuote: cot,
                        ),
                      ),
                    ).then((_) => _loadAll());
                  },
                ),
              ] else
                ListTile(
                  leading: const Icon(Icons.edit_road, color: Colors.purple),
                  title: const Text("Editar Nota de Entrega Asociada"),
                  onTap: () {
                    Navigator.pop(c);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CrearNotaEntregaScreen(
                          notaExistente: associatedNote,
                          displayId: displayId,
                        ),
                      ),
                    ).then((_) => _loadAll());
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Eliminar Cotización"),
                onTap: () async {
                  Navigator.pop(c);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Eliminar Documento"),
                      content: const Text("¿Está seguro que desea eliminar esta cotización? Esta acción no se puede deshacer."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCELAR")),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text("ELIMINAR"),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await DatabaseHelper.instance.deleteRecord('cotizaciones', cot['uuid']);
                    _loadAll();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

@override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (size.width >= 960) {
      return _buildDesktopDashboardLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildDesktopSidebarItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required Color primaryColor,
    required bool isDark,
    String? badge,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: primaryColor.withOpacity(0.08),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isActive ? primaryColor.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? Border.all(color: primaryColor.withOpacity(0.35), width: 1)
                  : Border.all(color: Colors.transparent, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive
                      ? primaryColor
                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive
                          ? (isDark ? Colors.white : primaryColor)
                          : (isDark ? Colors.white70 : const Color(0xFF334155)),
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopDashboardLayout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryPurple = Theme.of(context).primaryColor;
    final Color bgColor = isDark ? const Color(0xFF11130E) : const Color(0xFFF8FAFC);
    final Color cardBgColor = isDark ? const Color(0xFF1E211A) : Colors.white;
    final Color borderColor = isDark ? Colors.white.withOpacity(0.07) : const Color(0xFFE2E8F0);
    
    final String userNameRaw = session.userName ?? 'Usuario';
    final String formattedUserName = userNameRaw.isNotEmpty
        ? (userNameRaw[0].toUpperCase() + userNameRaw.substring(1).toLowerCase())
        : userNameRaw;

    final ventasEfectivas = _getVentasEfectivas();
    final double totalVentasMonto = ventasEfectivas.fold(0.0, (acc, item) {
      final total = double.tryParse((item['total'] ?? item['monto'] ?? 0).toString()) ?? 0.0;
      return acc + total;
    });

    final double totalCotizadoMonto = _cotizaciones.fold(0.0, (acc, item) {
      final total = double.tryParse((item['total'] ?? item['monto'] ?? 0).toString()) ?? 0.0;
      return acc + total;
    });

    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          // 1. BARRA LATERAL (SIDEBAR DESKTOP)
          Container(
            width: 270,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161913) : Colors.white,
              border: Border(right: BorderSide(color: borderColor, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo de Empresa en Cabecera de Sidebar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Row(
                    children: [
                      _buildHeaderLogo(isDark),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.transparent),
                const SizedBox(height: 8),

                // Lista de Secciones
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        child: Text(
                          'MENÚ PRINCIPAL',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                      _buildDesktopSidebarItem(
                        icon: Icons.dashboard_rounded,
                        label: 'Inicio',
                        isActive: true,
                        onTap: () {},
                        primaryColor: primaryPurple,
                        isDark: isDark,
                      ),
                      _buildDesktopSidebarItem(
                        icon: Icons.shopping_cart_rounded,
                        label: 'Cotizaciones',
                        badge: '',
                        isActive: false,
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/cotizaciones',
                            arguments: {'tipoVenta': 'cotizacion'},
                          ).then((_) => _loadAll());
                        },
                        primaryColor: primaryPurple,
                        isDark: isDark,
                      ),
                      _buildDesktopSidebarItem(
                        icon: Icons.point_of_sale_rounded,
                        label: 'Punto de Venta',
                        badge: '',
                        isActive: false,
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/cotizaciones',
                            arguments: {'tipoVenta': 'punto_venta'},
                          ).then((_) => _loadAll());
                        },
                        primaryColor: primaryPurple,
                        isDark: isDark,
                      ),
                      _buildDesktopSidebarItem(
                        icon: Icons.inventory_2_rounded,
                        label: 'Inventario',
                        isActive: false,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const local_inv.InventoryScreen()),
                          ).then((_) => _loadAll());
                        },
                        primaryColor: primaryPurple,
                        isDark: isDark,
                      ),
                      _buildDesktopSidebarItem(
                        icon: Icons.people_alt_rounded,
                        label: 'Clientes',
                        isActive: false,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ClientsScreen()),
                          ).then((_) => _loadAll());
                        },
                        primaryColor: primaryPurple,
                        isDark: isDark,
                      ),
                      if (session.isAdmin) ...[
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                          child: Text(
                            'ADMINISTRACIÓN',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                        _buildDesktopSidebarItem(
                          icon: Icons.badge_rounded,
                          label: 'Personal / Vendedores',
                          isActive: false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const PersonalManageScreen()),
                            ).then((_) => _loadAll());
                          },
                          primaryColor: primaryPurple,
                          isDark: isDark,
                        ),
                        _buildDesktopSidebarItem(
                          icon: Icons.tune_rounded,
                          label: 'Personalización',
                          isActive: false,
                          onTap: () {
                            Navigator.pushNamed(context, '/personalizacion').then((_) => _loadAll());
                          },
                          primaryColor: primaryPurple,
                          isDark: isDark,
                        ),
                      ],
                    ],
                  ),
                ),

                // Footer de la Sidebar (Modo Oscuro + Usuario + Logout)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131510) : const Color(0xFFF1F5F9),
                    border: Border(top: BorderSide(color: borderColor, width: 1)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: primaryPurple.withOpacity(0.2),
                            child: Text(
                              formattedUserName.isNotEmpty ? formattedUserName[0].toUpperCase() : 'U',
                              style: TextStyle(color: primaryPurple, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formattedUserName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  session.role.toString().split('.').last.toUpperCase(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: primaryPurple,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                              size: 19,
                              color: isDark ? Colors.amber : const Color(0xFF64748B),
                            ),
                            tooltip: isDark ? 'Modo Claro' : 'Modo Oscuro',
                            onPressed: () => NovaledApp.of(context).toggleTheme(!isDark),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout_rounded, size: 19, color: Colors.redAccent),
                            tooltip: 'Cerrar Sesión',
                            onPressed: () => Session.forceLogout(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. ÁREA PRINCIPAL DE CONTENIDO (MAIN DESKTOP DASHBOARD)
          Expanded(
            child: Column(
              children: [
                // Top Bar de Contenido
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161913) : Colors.white,
                    border: Border(bottom: BorderSide(color: borderColor, width: 1)),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¡Bienvenido, !',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Panel de control de Novaled Sistema',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (_isSyncing)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: primaryPurple.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: primaryPurple),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Sincronizando...',
                                style: GoogleFonts.poppins(fontSize: 12, color: primaryPurple, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 14),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 16, color: Colors.white),
                        label: Text('Nueva Cotización', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryPurple,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/cotizaciones',
                            arguments: {'tipoVenta': 'cotizacion'},
                          ).then((_) => _loadAll());
                        },
                      ),
                    ],
                  ),
                ),

                // Scroll del Dashboard
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // GRID DE 4 TARJETAS DE MÉTRICAS MODERNAS
                        LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = constraints.maxWidth > 1100 ? 4 : 2;
                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 20,
                              mainAxisSpacing: 20,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: constraints.maxWidth > 1100 ? 1.6 : 2.0,
                              children: [
                                _buildDesktopMetricCard(
                                  title: 'Cotizaciones',
                                  value: '',
                                  subValue: 'Total:  Bs',
                                  icon: Icons.shopping_cart_rounded,
                                  accentColor: primaryPurple,
                                  cardBg: cardBgColor,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                  onTap: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/cotizaciones',
                                      arguments: {'tipoVenta': 'cotizacion'},
                                    ).then((_) => _loadAll());
                                  },
                                ),
                                _buildDesktopMetricCard(
                                  title: 'Punto de Venta',
                                  value: '',
                                  subValue: 'Cobrado:  Bs',
                                  icon: Icons.point_of_sale_rounded,
                                  accentColor: const Color(0xFF10B981),
                                  cardBg: cardBgColor,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                  onTap: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/cotizaciones',
                                      arguments: {'tipoVenta': 'punto_venta'},
                                    ).then((_) => _loadAll());
                                  },
                                ),
                                _buildDesktopMetricCard(
                                  title: 'Inventario / Catálogo',
                                  value: '',
                                  subValue: 'Artículos activos',
                                  icon: Icons.inventory_2_rounded,
                                  accentColor: const Color(0xFFF59E0B),
                                  cardBg: cardBgColor,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const local_inv.InventoryScreen()),
                                    ).then((_) => _loadAll());
                                  },
                                ),
                                _buildDesktopMetricCard(
                                  title: 'Directorio Clientes',
                                  value: '',
                                  subValue: 'Clientes registrados',
                                  icon: Icons.people_alt_rounded,
                                  accentColor: const Color(0xFF00ADEF),
                                  cardBg: cardBgColor,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const ClientsScreen()),
                                    ).then((_) => _loadAll());
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 28),

                        // PANEL DE ESTADÍSTICAS Y CONTROL
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: cardBgColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.bar_chart_rounded, color: primaryPurple, size: 22),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Resumen de Estadísticas',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Selector de Periodo: Hoy, Semana, Mes
                                  Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF131510) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Row(
                                      children: ['Hoy', 'Semana', 'Mes'].map((p) {
                                        final isSel = _selectedStatsPeriod == p;
                                        return GestureDetector(
                                          onTap: () => setState(() => _selectedStatsPeriod = p),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isSel ? primaryPurple : Colors.transparent,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              p,
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                                                color: isSel ? Colors.white : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              
                              // Métricas Detalladas con Comparativa y Tendencias
                              Builder(
                                builder: (context) {
                                  DateTime parseDocDate(String? str) {
                                    if (str == null || str.isEmpty) return DateTime(1970);
                                    try {
                                      return DateTime.parse(str);
                                    } catch (_) {
                                      final p = str.split(' ')[0].split('/');
                                      if (p.length == 3) {
                                        return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
                                      }
                                      return DateTime(1970);
                                    }
                                  }

                                  final now = DateTime.now();
                                  bool isMatchCurrent(DateTime d) {
                                    if (_selectedStatsPeriod == 'Hoy') {
                                      return d.year == now.year && d.month == now.month && d.day == now.day;
                                    } else if (_selectedStatsPeriod == 'Semana') {
                                      final monday = now.subtract(Duration(days: now.weekday - 1));
                                      final sunday = monday.add(const Duration(days: 6));
                                      final dayOnly = DateTime(d.year, d.month, d.day);
                                      final monOnly = DateTime(monday.year, monday.month, monday.day);
                                      final sunOnly = DateTime(sunday.year, sunday.month, sunday.day);
                                      return !dayOnly.isBefore(monOnly) && !dayOnly.isAfter(sunOnly);
                                    } else {
                                      return d.year == now.year && d.month == now.month;
                                    }
                                  }

                                  final allVentas = _getVentasEfectivas();
                                  final filteredVentas = allVentas.where((doc) => isMatchCurrent(parseDocDate(doc['fecha']?.toString()))).toList();
                                  final filteredQuotes = _cotizaciones.where((doc) => isMatchCurrent(parseDocDate(doc['fecha']?.toString()))).toList();
                                  final approvedCount = filteredQuotes.where((doc) {
                                    final st = (doc['estado'] ?? '').toString().toLowerCase();
                                    return st == 'aprobada' || st == 'completado';
                                  }).length;
                                  final porCobrarCount = _notasEntrega.where((doc) {
                                    final total = (doc['total'] as num?)?.toDouble() ?? 0.0;
                                    final cancelado = (doc['saldo_cancelado'] as num?)?.toDouble() ?? 0.0;
                                    return (total - cancelado) > 0.01;
                                  }).length;

                                  return Row(
                                    children: [
                                      Expanded(
                                        child: _buildNewStatCard(
                                          iconPath: 'Iconos/nuevo 13 8 26/inicio/cotizaciones.png',
                                          fallbackIcon: Icons.description_outlined,
                                          value: '',
                                          label: 'Cotizaciones',
                                          trend: 'Activas',
                                          isUp: true,
                                          primaryColor: primaryPurple,
                                          isDark: isDark,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: _buildNewStatCard(
                                          iconPath: 'Iconos/nuevo 13 8 26/inicio/aprobados.png',
                                          fallbackIcon: Icons.check_circle_outline_rounded,
                                          value: '',
                                          label: 'Aprobadas',
                                          trend: 'Ventas cerradas',
                                          isUp: true,
                                          primaryColor: const Color(0xFF10B981),
                                          isDark: isDark,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: _buildNewStatCard(
                                          iconPath: 'Iconos/nuevo 13 8 26/inicio/ventas.png',
                                          fallbackIcon: Icons.shopping_bag_outlined,
                                          value: '',
                                          label: 'Ventas Efectivas',
                                          trend: 'Cobros realizados',
                                          isUp: true,
                                          primaryColor: primaryPurple,
                                          isDark: isDark,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: _buildNewStatCard(
                                          iconPath: 'Iconos/nuevo 13 8 26/inicio/por cobrar.png',
                                          fallbackIcon: Icons.account_balance_wallet_outlined,
                                          value: '',
                                          label: 'Por Cobrar',
                                          trend: 'Pendientes',
                                          isUp: false,
                                          primaryColor: const Color(0xFF00ADEF),
                                          isDark: isDark,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopMetricCard({
    required String title,
    required String value,
    required String subValue,
    required IconData icon,
    required Color accentColor,
    required Color cardBg,
    required Color borderColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subValue,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }




  Widget _buildMobileLayout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryPurple = Theme.of(context).primaryColor;
    final Color iconColor = NovaledApp.of(context).iconColor;
    final Color bgColor = isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor;
    final Color headerBtnColor = isDark ? Colors.white : const Color(0xFF0F172A);

    final String userNameRaw = session.userName ?? 'Usuario';
    final String formattedUserName = userNameRaw.isNotEmpty
        ? (userNameRaw[0].toUpperCase() + userNameRaw.substring(1).toLowerCase())
        : userNameRaw;

    return Scaffold(
      key: _mobileScaffoldKey,
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Cabecera: novaled logo image (dinámico según Modo Edición) + Theme switch (luz.png/luna.png) + Modo edición (modo edicion.png)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  _buildHeaderLogo(isDark),
                  const Spacer(),
                  IconButton(
                    icon: Image.asset(
                      isDark ? 'Iconos/nuevo 13 8 26/inicio/luna.png' : 'Iconos/nuevo 13 8 26/inicio/luz.png',
                      width: 22,
                      height: 22,
                      color: headerBtnColor,
                      errorBuilder: (_, __, ___) => Icon(
                        isDark ? Icons.brightness_2_outlined : Icons.wb_sunny_outlined,
                        color: headerBtnColor,
                        size: 22,
                      ),
                    ),
                    onPressed: () {
                      NovaledApp.of(context).toggleTheme(!isDark);
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Image.asset(
                      'Iconos/nuevo 13 8 26/inicio/modo edicion.png',
                      width: 22,
                      height: 22,
                      color: headerBtnColor,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.settings_outlined,
                        color: headerBtnColor,
                        size: 22,
                      ),
                    ),
                    onPressed: () => Navigator.pushNamed(context, '/personalizacion').then((_) => _loadAll()),
                  ),
                ],
              ),
            ),
            if (_isSyncing)
              const LinearProgressIndicator(
                color: Color(0xFF5842F4),
                backgroundColor: Colors.transparent,
                minHeight: 2,
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF5842F4)))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: IntrinsicHeight(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),
                                  // Saludo "Hola, Almir!" (sin grosor bold)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: "Hola, ",
                                            style: GoogleFonts.poppins(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w400,
                                              color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                                            ),
                                          ),
                                          TextSpan(
                                            text: "$formattedUserName!",
                                            style: GoogleFonts.poppins(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w500,
                                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // ÚNICAMENTE 2 TARJETAS: Cotizaciones y Punto de venta (iconos de carrito.png y dinero.png)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _buildPurpleCard(
                                            title: "Cotizaciones",
                                            iconPath: "Iconos/nuevo 13 8 26/inicio/carrito.png",
                                            fallbackIcon: Icons.shopping_cart_outlined,
                                            primaryPurple: primaryPurple,
                                            onTap: () {
                                              Navigator.pushNamed(
                                                context,
                                                '/cotizaciones',
                                                arguments: {'tipoVenta': 'cotizacion'},
                                              ).then((_) => _loadAll());
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: _buildPurpleCard(
                                            title: "Punto de venta",
                                            iconPath: "Iconos/nuevo 13 8 26/inicio/dinero.png",
                                            fallbackIcon: Icons.attach_money_rounded,
                                            primaryPurple: primaryPurple,
                                            onTap: () {
                                              Navigator.pushNamed(
                                                context,
                                                '/cotizaciones',
                                                arguments: {'tipoVenta': 'punto_venta'},
                                              ).then((_) => _loadAll());
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 16),
                                  const Spacer(),

                                  // Panel Inferior Curvo Blanco: Estadísticas (Anclado 100% abajo)
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF22251F) : Colors.white,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 16,
                                          offset: const Offset(0, -4),
                                        )
                                      ],
                                    ),
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header: "Estadísticas" + Period Selector ("Hoy", "Semana", "Mes")
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              "Estadísticas",
                                              style: GoogleFonts.poppins(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white : const Color(0xFF1A202C),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                                                ),
                                              ),
                                              child: Row(
                                                children: ['Hoy', 'Semana', 'Mes'].map((period) {
                                                  final isSelected = _selectedStatsPeriod == period;
                                                  return GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        _selectedStatsPeriod = period;
                                                      });
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: isSelected ? primaryPurple : Colors.transparent,
                                                        borderRadius: BorderRadius.circular(16),
                                                        boxShadow: isSelected
                                                            ? [
                                                                BoxShadow(
                                                                  color: primaryPurple.withOpacity(0.3),
                                                                  blurRadius: 4,
                                                                  offset: const Offset(0, 1),
                                                                )
                                                              ]
                                                            : null,
                                                      ),
                                                      child: Text(
                                                        period,
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 11,
                                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                                          color: isSelected
                                                              ? Colors.white
                                                              : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        // 4 Stat Cards Grid (4 Column Row)
                                        Builder(
                                          builder: (context) {
                                            final now = DateTime.now();
                                            bool isMatchCurrent(DateTime? d) {
                                              if (d == null) return false;
                                              if (_selectedStatsPeriod == 'Hoy') {
                                                return d.year == now.year && d.month == now.month && d.day == now.day;
                                              } else if (_selectedStatsPeriod == 'Semana') {
                                                final diff = now.difference(d).inDays;
                                                return diff >= 0 && diff < 7;
                                              } else {
                                                return d.year == now.year && d.month == now.month;
                                              }
                                            }

                                            bool isMatchPrevious(DateTime? d) {
                                              if (d == null) return false;
                                              if (_selectedStatsPeriod == 'Hoy') {
                                                final yesterday = now.subtract(const Duration(days: 1));
                                                return d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
                                              } else if (_selectedStatsPeriod == 'Semana') {
                                                final diff = now.difference(d).inDays;
                                                return diff >= 7 && diff < 14;
                                              } else {
                                                final prevMonthDate = DateTime(now.year, now.month - 1, 1);
                                                return d.year == prevMonthDate.year && d.month == prevMonthDate.month;
                                              }
                                            }

                                            Map<String, dynamic> calcTrend(num current, num previous) {
                                              if (previous == 0) {
                                                if (current == 0) {
                                                  return {'trend': '0%', 'isUp': true};
                                                } else {
                                                  return {'trend': '100%', 'isUp': true};
                                                }
                                              }
                                              final pct = ((current - previous) / previous * 100).round();
                                              if (pct >= 0) {
                                                return {'trend': '$pct%', 'isUp': true};
                                              } else {
                                                return {'trend': '${pct.abs()}%', 'isUp': false};
                                              }
                                            }

                                            final filteredQuotes = _cotizaciones.where((doc) {
                                              final d = parseDocDate(doc['fecha']?.toString());
                                              return isMatchCurrent(d);
                                            }).toList();

                                            final prevQuotes = _cotizaciones.where((doc) {
                                              final d = parseDocDate(doc['fecha']?.toString());
                                              return isMatchPrevious(d);
                                            }).toList();

                                            final filteredNotes = _notasEntrega.where((doc) {
                                              final d = parseDocDate(doc['fecha']?.toString());
                                              return isMatchCurrent(d);
                                            }).toList();

                                            final prevNotes = _notasEntrega.where((doc) {
                                              final d = parseDocDate(doc['fecha']?.toString());
                                              return isMatchPrevious(d);
                                            }).toList();

                                            final allVentas = _getVentasEfectivas();
                                            final filteredVentas = allVentas.where((doc) {
                                              final d = parseDocDate(doc['fecha']?.toString());
                                              return isMatchCurrent(d);
                                            }).toList();

                                            final prevVentas = allVentas.where((doc) {
                                              final d = parseDocDate(doc['fecha']?.toString());
                                              return isMatchPrevious(d);
                                            }).toList();

                                            final approvedCount = filteredQuotes.where((doc) {
                                              final st = (doc['estado'] ?? '').toString().toLowerCase();
                                              return st == 'aprobada' || st == 'completado';
                                            }).length;

                                            final prevApprovedCount = prevQuotes.where((doc) {
                                              final st = (doc['estado'] ?? '').toString().toLowerCase();
                                              return st == 'aprobada' || st == 'completado';
                                            }).length;

                                            final porCobrarCount = filteredNotes.where((doc) {
                                              final total = (doc['total'] as num?)?.toDouble() ?? 0.0;
                                              final cancelado = (doc['saldo_cancelado'] as num?)?.toDouble() ?? 0.0;
                                              return (total - cancelado) > 0.01;
                                            }).length;

                                            final prevPorCobrarCount = prevNotes.where((doc) {
                                              final total = (doc['total'] as num?)?.toDouble() ?? 0.0;
                                              final cancelado = (doc['saldo_cancelado'] as num?)?.toDouble() ?? 0.0;
                                              return (total - cancelado) > 0.01;
                                            }).length;

                                            final tQuotes = calcTrend(filteredQuotes.length, prevQuotes.length);
                                            final tApproved = calcTrend(approvedCount, prevApprovedCount);
                                            final tVentas = calcTrend(filteredVentas.length, prevVentas.length);
                                            final tPorCobrar = calcTrend(porCobrarCount, prevPorCobrarCount);

                                            return Row(
                                              children: [
                                                Expanded(
                                                  child: _buildNewStatCard(
                                                    iconPath: "Iconos/nuevo 13 8 26/inicio/cotizaciones.png",
                                                    fallbackIcon: Icons.description_outlined,
                                                    value: "${filteredQuotes.length}",
                                                    label: "Cotizaciones",
                                                    trend: tQuotes['trend'],
                                                    isUp: tQuotes['isUp'],
                                                    primaryColor: primaryPurple,
                                                    isDark: isDark,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: _buildNewStatCard(
                                                    iconPath: "Iconos/nuevo 13 8 26/inicio/aprobados.png",
                                                    fallbackIcon: Icons.check_circle_outline_rounded,
                                                    value: "$approvedCount",
                                                    label: "Aprobadas",
                                                    trend: tApproved['trend'],
                                                    isUp: tApproved['isUp'],
                                                    primaryColor: primaryPurple,
                                                    isDark: isDark,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: _buildNewStatCard(
                                                    iconPath: "Iconos/nuevo 13 8 26/inicio/ventas.png",
                                                    fallbackIcon: Icons.shopping_bag_outlined,
                                                    value: "${filteredVentas.length}",
                                                    label: "Ventas",
                                                    trend: tVentas['trend'],
                                                    isUp: tVentas['isUp'],
                                                    primaryColor: primaryPurple,
                                                    isDark: isDark,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: _buildNewStatCard(
                                                    iconPath: "Iconos/nuevo 13 8 26/inicio/por cobrar.png",
                                                    fallbackIcon: Icons.account_balance_wallet_outlined,
                                                    value: "$porCobrarCount",
                                                    label: "Por cobrar",
                                                    trend: tPorCobrar['trend'],
                                                    isUp: tPorCobrar['isUp'],
                                                    primaryColor: primaryPurple,
                                                    isDark: isDark,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),

                                        // Ventas Chart Card (Punto de Venta PAGADO + Notas de Entrega)
                                        Builder(
                                          builder: (context) {
                                            final now = DateTime.now();
                                            final monday = now.subtract(Duration(days: now.weekday - 1));
                                            final weekDays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

                                            final allVentas = _getVentasEfectivas();
                                            final List<int> dailyCounts = List.generate(7, (index) {
                                              final dayDate = DateTime(monday.year, monday.month, monday.day).add(Duration(days: index));
                                              return allVentas.where((doc) {
                                                final d = parseDocDate(doc['fecha']?.toString());
                                                return d != null && d.year == dayDate.year && d.month == dayDate.month && d.day == dayDate.day;
                                              }).length;
                                            });

                                            int highest = 0;
                                            for (var c in dailyCounts) {
                                              if (c > highest) highest = c;
                                            }
                                            int maxVal = highest < 5 ? 5 : ((highest / 5).ceil() * 5);

                                            return Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                                borderRadius: BorderRadius.circular(18),
                                                border: Border.all(
                                                  color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.02),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 2),
                                                  )
                                                ],
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "Ventas",
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? Colors.white : const Color(0xFF1A202C),
                                                    ),
                                                  ),
                                        const SizedBox(height: 8),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            // Y-Axis Labels
                                            SizedBox(
                                              height: 60,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  Text("$maxVal", style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey[400])),
                                                  Text("${(maxVal * 0.5).round()}", style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey[400])),
                                                  Text("0", style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey[400])),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Bars Area
                                            Expanded(
                                              child: SizedBox(
                                                height: 60,
                                                child: Stack(
                                                  children: [
                                                    // Dashed Grid Lines
                                                    Positioned.fill(
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: List.generate(3, (index) {
                                                          return Container(
                                                            height: 1,
                                                            color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE2E8F0),
                                                          );
                                                        }),
                                                      ),
                                                    ),
                                                    // Bars
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                                      crossAxisAlignment: CrossAxisAlignment.end,
                                                      children: List.generate(7, (index) {
                                                        final count = dailyCounts[index];
                                                        final heightRatio = maxVal > 0 ? (count / maxVal).clamp(0.1, 1.0) : 0.1;
                                                        final barHeight = 60 * heightRatio;
                                                        return Column(
                                                          mainAxisAlignment: MainAxisAlignment.end,
                                                          children: [
                                                            Container(
                                                              width: 10,
                                                              height: barHeight,
                                                              decoration: BoxDecoration(
                                                                color: primaryPurple,
                                                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                                              ),
                                                            ),
                                                          ],
                                                        );
                                                      }),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        // X-Axis Labels
                                        Row(
                                          children: [
                                            const SizedBox(width: 24),
                                            Expanded(
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                                children: weekDays.map((day) {
                                                  return Text(
                                                    day,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w500,
                                                      color: isDark ? Colors.white54 : Colors.grey[500],
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurpleCard({
    required String title,
    required String iconPath,
    required IconData fallbackIcon,
    required Color primaryPurple,
    required VoidCallback onTap,
    bool isWide = false,
  }) {
    final Color iconColor = NovaledApp.of(context).iconColor;

    final hsl = HSLColor.fromColor(primaryPurple);
    final gradStart = hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 0.95)).toColor();
    final gradEnd = hsl.withLightness((hsl.lightness - 0.08).clamp(0.0, 0.95)).toColor();

    return Container(
      height: isWide ? 80 : 118,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradStart, gradEnd],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: primaryPurple.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: isWide
                ? Row(
                    children: [
                      Image.asset(
                        iconPath,
                        width: 32,
                        height: 32,
                        color: iconColor,
                        colorBlendMode: BlendMode.srcIn,
                        errorBuilder: (_, __, ___) => Icon(fallbackIcon, color: iconColor, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Image.asset(
                        iconPath,
                        width: 32,
                        height: 32,
                        color: iconColor,
                        colorBlendMode: BlendMode.srcIn,
                        errorBuilder: (_, __, ___) => Icon(fallbackIcon, color: iconColor, size: 32),
                      ),
                      const SizedBox(height: 12),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          maxLines: 1,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String number, String label, bool isDark) {
    return Column(
      children: [
        Text(
          number,
          style: GoogleFonts.poppins(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w300,
            color: isDark ? Colors.white54 : const Color(0xFF8C98B6),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderLogo(bool isDark) {
    if (_customCompanyLogoPath != null && _customCompanyLogoPath!.trim().isNotEmpty) {
      final pathStr = _customCompanyLogoPath!.trim();
      final file = File(pathStr);
      if (file.existsSync()) {
        return Image.file(
          file,
          height: 38,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildDefaultLogo(isDark),
        );
      } else {
        return Image.asset(
          pathStr,
          height: 38,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildDefaultLogo(isDark),
        );
      }
    }
    return _buildDefaultLogo(isDark);
  }

  Widget _buildDefaultLogo(bool isDark) {
    return Image.asset(
      'icono/logo.png',
      height: 38,
      fit: BoxFit.contain,
      color: isDark ? Colors.white : null,
      errorBuilder: (_, __, ___) => Image.asset(
        'novaled_logo.png',
        height: 38,
        fit: BoxFit.contain,
        color: isDark ? Colors.white : null,
      ),
    );
  }

  Widget _buildNewStatCard({
    required String iconPath,
    required IconData fallbackIcon,
    required String value,
    required String label,
    required String trend,
    required bool isUp,
    required Color primaryColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            iconPath,
            width: 20,
            height: 20,
            color: isDark ? Colors.white70 : const Color(0xFF1E293B),
            errorBuilder: (_, __, ___) => Icon(
              fallbackIcon,
              size: 20,
              color: isDark ? Colors.white70 : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : Colors.grey[400],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 10,
                color: isUp ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 1),
              Text(
                trend,
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: isUp ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(String dayNum, String dayName, bool isSelected, Color primaryPurple, bool isDark, {double? width}) {
    return Container(
      width: width ?? 58,
      height: 64,
      decoration: BoxDecoration(
        color: isSelected ? primaryPurple : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: primaryPurple.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            dayNum,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white60 : const Color(0xFF64748B)),
            ),
          ),
          Text(
            dayName,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w300,
              color: isSelected
                  ? Colors.white70
                  : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }



  // Sidebar item helper tile
  Widget _sidebarTile({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final primaryCyan = const Color(0xFF00ADEF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Container(
        decoration: BoxDecoration(
          color: active ? primaryCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12.0),
          horizontalTitleGap: 8.0,
          leading: Icon(icon, color: active ? Colors.black : Colors.white70, size: 20),
          title: Text(
            label,
            style: TextStyle(
              color: active ? Colors.black : Colors.white70,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
          onTap: () {
            onTap();
            if (MediaQuery.of(context).size.width < 1024) {
              Navigator.pop(context);
            }
          },
        ),
      ),
    );
  }

  Widget _sidebarExpandableTile({
    required IconData icon,
    required String label,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12.0),
          horizontalTitleGap: 8.0,
          leading: Icon(icon, color: Colors.white70, size: 20),
          title: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          trailing: Icon(
            expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: Colors.white70,
            size: 18,
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _sidebarSubTile({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final primaryCyan = const Color(0xFF00ADEF);
    return Padding(
      padding: const EdgeInsets.only(left: 20.0, bottom: 6.0),
      child: Container(
        decoration: BoxDecoration(
          color: active ? primaryCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12.0),
          horizontalTitleGap: 8.0,
          leading: Icon(icon, color: active ? Colors.black : Colors.white70, size: 18),
          title: Text(
            label,
            style: TextStyle(
              color: active ? Colors.black : Colors.white70,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              fontSize: 13.5,
            ),
          ),
          onTap: () {
            onTap();
            if (MediaQuery.of(context).size.width < 1024) {
              Navigator.pop(context);
            }
          },
        ),
      ),
    );
  }

  // Segmented control button in Cotizaciones
  Widget _documentFilterButton({required String label, required String value}) {
    final active = _documentFilter == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _documentFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active 
              ? (isDark ? const Color(0xFF1E293B) : Colors.grey[300]) 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active 
                ? (isDark ? Colors.white10 : Colors.black12)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active 
                ? (isDark ? Colors.white : Colors.black87)
                : Colors.grey,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // Statistical card in home
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Card(
      elevation: 3,
      color: isDark ? const Color(0xFF131A26) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideCard({
    required String title,
    required bool isDark,
    required Color cardBg,
    required Color textColor,
    required Color iconColor,
    required List<BoxShadow> cardShadow,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                AnimatedDashboardIcon(
                  type: 'calculator',
                  color: iconColor,
                  size: 48,
                  customChild: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.description_rounded, size: 48, color: iconColor),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.calculate_rounded, size: 22, color: iconColor),
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSellerMenu({
    required bool isDark,
    required Color cardBg,
    required Color textColor,
    required Color primaryCyan,
    required List<Product> listos,
  }) {
    return [
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.25,
        children: [
          _buildGridCard(
            title: "Cotizaciones",
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFFEFA820),
            onTap: () {
              Navigator.pushNamed(
                context,
                '/cotizaciones',
                arguments: {'tipoVenta': 'cotizacion'},
              ).then((_) => _loadAll());
            },
          ),
          _buildGridCard(
            title: "Punto de Venta",
            icon: Icons.point_of_sale_rounded,
            color: const Color(0xFFEFA820),
            onTap: () {
              Navigator.pushNamed(
                context,
                '/cotizaciones',
                arguments: {'tipoVenta': 'punto_venta'},
              ).then((_) => _loadAll());
            },
          ),
          _buildGridCard(
            title: "Inventario",
            icon: Icons.inventory_2_rounded,
            color: const Color(0xFFEFA820),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: '/inventario'),
                  builder: (c) => const local_inv.InventoryScreen(initialTab: 'oficial'),
                ),
              ).then((_) => _loadAll());
            },
          ),
          _buildGridCard(
            title: "Clientes",
            icon: Icons.people_alt_rounded,
            color: const Color(0xFFEFA820),
            onTap: () {
              Navigator.pushNamed(context, '/clientes').then((_) => _loadAll());
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
      _buildWideBarCard(
        title: "Notas de Entrega",
        icon: Icons.local_shipping_rounded,
        color: const Color(0xFFEFA820),
        onTap: () {
          Navigator.pushNamed(
            context,
            '/cotizaciones',
            arguments: {
              'tipoVenta': 'punto_venta',
              'initialTab': 'notas_entrega',
            },
          ).then((_) => _loadAll());
        },
      ),
    ];
  }

  Widget _buildWideBarCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182232) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182232) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
          width: 1.0,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 36),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DateTime? parseDocDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      try {
        final parts = dateStr.split(' ')[0].split('/');
        if (parts.length == 3) {
          final day = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final year = int.parse(parts[2]);
          return DateTime(year, month, day);
        }
      } catch (e) {
        debugPrint("Error parsing date: $e");
      }
    }
    return null;
  }

  Widget _buildReporteDeVentas() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF182232) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondaryColor = isDark ? Colors.white70 : const Color(0xFF475569);

    final sellersSet = <String>{'todos'};
    if (_vendedoresSistema.isNotEmpty) {
      sellersSet.addAll(_vendedoresSistema);
    } else {
      sellersSet.add('joel');
    }
    for (var c in _cotizaciones) {
      final rawSeller = c['vendedor']?.toString().trim() ?? '';
      final seller = (rawSeller == 'Dueño' || rawSeller == 'Dueño / Administrador' || rawSeller.isEmpty) ? 'joel' : rawSeller;
      sellersSet.add(seller);
    }
    for (var n in _notasEntrega) {
      final rawSeller = n['vendedor']?.toString().trim() ?? '';
      final seller = (rawSeller == 'Dueño' || rawSeller == 'Dueño / Administrador' || rawSeller.isEmpty) ? 'joel' : rawSeller;
      sellersSet.add(seller);
    }
    sellersSet.remove('Dueño');
    sellersSet.remove('Dueño / Administrador');
    final allSellers = sellersSet.toList()..sort();

    final now = DateTime.now();
    final startOfToday = DateTime(_selectedReportTodayDate.year, _selectedReportTodayDate.month, _selectedReportTodayDate.day);
    final startOfWeek = DateTime(_selectedReportWeekDate.year, _selectedReportWeekDate.month, _selectedReportWeekDate.day);
    final startOfMonth = DateTime(_selectedReportMonthDate.year, _selectedReportMonthDate.month, 1);

    final filteredQuotes = _cotizaciones.where((doc) {
      final docDate = parseDocDate(doc['fecha']?.toString());
      if (docDate == null) return false;

      bool dateMatch = false;
      if (_selectedReportPeriod == 'hoy') {
        dateMatch = docDate.isAfter(startOfToday) || docDate.isAtSameMomentAs(startOfToday);
      } else if (_selectedReportPeriod == 'semana') {
        final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));
        dateMatch = (docDate.isAfter(startOfWeek) || docDate.isAtSameMomentAs(startOfWeek)) &&
                    docDate.isBefore(endOfWeek);
      } else if (_selectedReportPeriod == 'mes') {
        dateMatch = docDate.year == _selectedReportMonthDate.year && docDate.month == _selectedReportMonthDate.month;
      } else if (_selectedReportPeriod == 'custom' && _customDateRange != null) {
        dateMatch = (docDate.isAfter(_customDateRange!.start) || docDate.isAtSameMomentAs(_customDateRange!.start)) &&
                    docDate.isBefore(_customDateRange!.end.add(const Duration(days: 1)));
      } else {
        dateMatch = true;
      }

      if (!dateMatch) return false;

      if (_selectedReportSeller != 'todos') {
        final rawSeller = doc['vendedor']?.toString().trim() ?? '';
        final seller = (rawSeller == 'Dueño' || rawSeller == 'Dueño / Administrador' || rawSeller.isEmpty) ? 'joel' : rawSeller;
        if (seller != _selectedReportSeller) return false;
      }

      return true;
    }).toList();

    final filteredNotes = _notasEntrega.where((doc) {
      final docDate = parseDocDate(doc['fecha']?.toString());
      if (docDate == null) return false;

      bool dateMatch = false;
      if (_selectedReportPeriod == 'hoy') {
        dateMatch = docDate.isAfter(startOfToday) || docDate.isAtSameMomentAs(startOfToday);
      } else if (_selectedReportPeriod == 'semana') {
        final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));
        dateMatch = (docDate.isAfter(startOfWeek) || docDate.isAtSameMomentAs(startOfWeek)) &&
                    docDate.isBefore(endOfWeek);
      } else if (_selectedReportPeriod == 'mes') {
        dateMatch = docDate.year == _selectedReportMonthDate.year && docDate.month == _selectedReportMonthDate.month;
      } else if (_selectedReportPeriod == 'custom' && _customDateRange != null) {
        dateMatch = (docDate.isAfter(_customDateRange!.start) || docDate.isAtSameMomentAs(_customDateRange!.start)) &&
                    docDate.isBefore(_customDateRange!.end.add(const Duration(days: 1)));
      } else {
        dateMatch = true;
      }

      if (!dateMatch) return false;

      if (_selectedReportSeller != 'todos') {
        final rawSeller = doc['vendedor']?.toString().trim() ?? '';
        final seller = (rawSeller == 'Dueño' || rawSeller == 'Dueño / Administrador' || rawSeller.isEmpty) ? 'joel' : rawSeller;
        if (seller != _selectedReportSeller) return false;
      }

      return true;
    }).toList();

    final totalQuotesVal = filteredQuotes.fold<double>(0.0, (s, d) => s + ((d['total'] as num?)?.toDouble() ?? 0.0));
    final totalNotesVal = filteredNotes.fold<double>(0.0, (s, d) => s + ((d['total'] as num?)?.toDouble() ?? 0.0));

    final convertedQuotesCount = filteredQuotes.where((c) => _tieneNotaEntrega(c)).length;
    final double conversionRate = filteredQuotes.isEmpty
        ? 0.0
        : (convertedQuotesCount / filteredQuotes.length) * 100.0;

    final sellersPerformance = <Map<String, dynamic>>[];
    for (var s in sellersSet) {
      if (s == 'todos') continue;

      if (_selectedReportSeller != 'todos' && s != _selectedReportSeller) {
        continue;
      }

      if (_selectedReportSeller == 'todos' && !_sellersOnly.contains(s)) {
        continue;
      }

      final sq = _cotizaciones.where((doc) {
        final rawSeller = doc['vendedor']?.toString().trim() ?? '';
        final seller = (rawSeller == 'Dueño' || rawSeller == 'Dueño / Administrador' || rawSeller.isEmpty) ? 'joel' : rawSeller;
        if (seller != s) return false;

        final docDate = parseDocDate(doc['fecha']?.toString());
        if (docDate == null) return false;

        if (_selectedReportPeriod == 'hoy') {
          return docDate.isAfter(startOfToday) || docDate.isAtSameMomentAs(startOfToday);
        } else if (_selectedReportPeriod == 'semana') {
          final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));
          return (docDate.isAfter(startOfWeek) || docDate.isAtSameMomentAs(startOfWeek)) &&
                 docDate.isBefore(endOfWeek);
        } else if (_selectedReportPeriod == 'mes') {
          return docDate.year == _selectedReportMonthDate.year && docDate.month == _selectedReportMonthDate.month;
        } else if (_selectedReportPeriod == 'custom' && _customDateRange != null) {
          return (docDate.isAfter(_customDateRange!.start) || docDate.isAtSameMomentAs(_customDateRange!.start)) &&
                 docDate.isBefore(_customDateRange!.end.add(const Duration(days: 1)));
        }
        return true;
      }).toList();

      final sn = _notasEntrega.where((doc) {
        final rawSeller = doc['vendedor']?.toString().trim() ?? '';
        final seller = (rawSeller == 'Dueño' || rawSeller == 'Dueño / Administrador' || rawSeller.isEmpty) ? 'joel' : rawSeller;
        if (seller != s) return false;

        final docDate = parseDocDate(doc['fecha']?.toString());
        if (docDate == null) return false;

        if (_selectedReportPeriod == 'hoy') {
          return docDate.isAfter(startOfToday) || docDate.isAtSameMomentAs(startOfToday);
        } else if (_selectedReportPeriod == 'semana') {
          final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));
          return (docDate.isAfter(startOfWeek) || docDate.isAtSameMomentAs(startOfWeek)) &&
                 docDate.isBefore(endOfWeek);
        } else if (_selectedReportPeriod == 'mes') {
          return docDate.year == _selectedReportMonthDate.year && docDate.month == _selectedReportMonthDate.month;
        } else if (_selectedReportPeriod == 'custom' && _customDateRange != null) {
          return (docDate.isAfter(_customDateRange!.start) || docDate.isAtSameMomentAs(_customDateRange!.start)) &&
                 docDate.isBefore(_customDateRange!.end.add(const Duration(days: 1)));
        }
        return true;
      }).toList();

      final qVal = sq.fold<double>(0.0, (sum, doc) => sum + ((doc['total'] as num?)?.toDouble() ?? 0.0));
      final nVal = sn.fold<double>(0.0, (sum, doc) => sum + ((doc['total'] as num?)?.toDouble() ?? 0.0));

      sellersPerformance.add({
        'nombre': s,
        'quotesCount': sq.length,
        'quotesTotal': qVal,
        'notesCount': sn.length,
        'notesTotal': nVal,
        'profit': nVal * (_reportProfitMargin / 100),
      });
    }

    sellersPerformance.sort((a, b) => (b['notesTotal'] as double).compareTo(a['notesTotal'] as double));

    // Date range string formatting
    String rangeText = "";
    if (_selectedReportPeriod == 'hoy') {
      rangeText = "${startOfToday.day} ${_getMonthName(startOfToday.month)}";
    } else if (_selectedReportPeriod == 'semana') {
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      rangeText = "${startOfWeek.day} ${_getMonthName(startOfWeek.month)} - ${endOfWeek.day} ${_getMonthName(endOfWeek.month)}";
    } else if (_selectedReportPeriod == 'mes') {
      rangeText = "${_getMonthNameFull(_selectedReportMonthDate.month)} ${_selectedReportMonthDate.year}";
    } else if (_selectedReportPeriod == 'custom' && _customDateRange != null) {
      rangeText = "${_customDateRange!.start.day} ${_getMonthName(_customDateRange!.start.month)} - ${_customDateRange!.end.day} ${_getMonthName(_customDateRange!.end.month)}";
    } else {
      rangeText = "Todo";
    }

    // Chart points generation (7 points)
    DateTime startDate;
    DateTime endDate = now;
    if (_selectedReportPeriod == 'hoy') {
      startDate = startOfToday;
      endDate = startOfToday.add(const Duration(hours: 23, minutes: 59));
    } else if (_selectedReportPeriod == 'semana') {
      startDate = startOfWeek;
      endDate = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));
    } else if (_selectedReportPeriod == 'mes') {
      startDate = startOfMonth;
      endDate = DateTime(_selectedReportMonthDate.year, _selectedReportMonthDate.month + 1, 1).subtract(const Duration(seconds: 1));
    } else if (_selectedReportPeriod == 'custom' && _customDateRange != null) {
      startDate = _customDateRange!.start;
      endDate = _customDateRange!.end.add(const Duration(hours: 23, minutes: 59));
    } else {
      startDate = now.subtract(const Duration(days: 30));
    }

    final duration = endDate.difference(startDate);
    final double intervalMs = duration.inMilliseconds == 0 ? 1000.0 : duration.inMilliseconds / 6.0;
    
    final List<double> quotePoints = List.filled(7, 0.0);
    final List<double> notePoints = List.filled(7, 0.0);
    
    for (int i = 0; i < 7; i++) {
      final intervalStart = startDate.add(Duration(milliseconds: (i * intervalMs).toInt()));
      final intervalEnd = startDate.add(Duration(milliseconds: ((i + 1) * intervalMs).toInt()));
      
      final quotesInInterval = filteredQuotes.where((doc) {
        final docDate = parseDocDate(doc['fecha']?.toString());
        if (docDate == null) return false;
        return (docDate.isAfter(intervalStart) || docDate.isAtSameMomentAs(intervalStart)) &&
               docDate.isBefore(intervalEnd);
      });
      final notesInInterval = filteredNotes.where((doc) {
        final docDate = parseDocDate(doc['fecha']?.toString());
        if (docDate == null) return false;
        return (docDate.isAfter(intervalStart) || docDate.isAtSameMomentAs(intervalStart)) &&
               docDate.isBefore(intervalEnd);
      });
      
      quotePoints[i] = quotesInInterval.fold<double>(0.0, (s, d) => s + ((d['total'] as num?)?.toDouble() ?? 0.0));
      notePoints[i] = notesInInterval.fold<double>(0.0, (s, d) => s + ((d['total'] as num?)?.toDouble() ?? 0.0));
    }

    // Combined list of recent documents
    final List<Map<String, dynamic>> recentDocs = [];
    for (var q in filteredQuotes) {
      recentDocs.add({
        'type': 'cotizacion',
        'id': q['id'],
        'displayId': q['id_cotizacion'] ?? q['id'].toString(),
        'cliente': q['clienteNombre'] ?? '',
        'total': (q['total'] as num?)?.toDouble() ?? 0.0,
        'fecha': q['fecha'],
        'rawDoc': q,
      });
    }
    for (var n in filteredNotes) {
      recentDocs.add({
        'type': 'nota',
        'id': n['id'],
        'displayId': n['id_nota'] ?? n['id'].toString(),
        'cliente': n['clienteNombre'] ?? '',
        'total': (n['total'] as num?)?.toDouble() ?? 0.0,
        'fecha': n['fecha'],
        'rawDoc': n,
      });
    }
    
    recentDocs.sort((a, b) {
      final dateA = parseDocDate(a['fecha']?.toString()) ?? DateTime(2000);
      final dateB = parseDocDate(b['fecha']?.toString()) ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // RANGE SELECTOR ROW
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: () => _shiftPeriod(-1),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _showPeriodSelectorSheet,
                    child: Text(
                      rangeText,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed: () => _shiftPeriod(1),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _showPeriodSelectorSheet,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.filter_list_rounded, color: textColor, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // METRICS SECTION
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            "Metrics",
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildMetricCard(
                title: "Notas de Entrega",
                value: "${totalNotesVal.toStringAsFixed(2)} Bs",
                indicatorColor: const Color(0xFF10B981),
                indicatorLabel: "${filteredNotes.length} notas",
                isDark: isDark,
              ),
              const SizedBox(width: 12),
              _buildMetricCard(
                title: "Cotizaciones",
                value: "${totalQuotesVal.toStringAsFixed(2)} Bs",
                indicatorColor: const Color(0xFF00ADEF),
                indicatorLabel: "${filteredQuotes.length} cotizaciones",
                isDark: isDark,
              ),
              const SizedBox(width: 12),
              _buildConversionCard(
                title: "Tasa de Conversión",
                value: "${conversionRate.toStringAsFixed(0)}%",
                rate: conversionRate,
                isDark: isDark,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // CHART SECTION
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03)),
          ),
          child: Column(
            children: [
              ModernLineChart(quotesData: quotePoints, notesData: notePoints),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(width: 12, height: 3, color: const Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      Text("Notas de Entrega", style: TextStyle(color: textSecondaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Row(
                    children: [
                      Text("- -", style: TextStyle(color: const Color(0xFF00ADEF), fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Text("Cotizaciones", style: TextStyle(color: textSecondaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // DOCUMENTOS RECIENTES
        Text(
          "Documentos Recientes",
          style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 12),
        if (recentDocs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Text("No hay documentos recientes", style: TextStyle(color: textSecondaryColor)),
            ),
          )
        else
          Column(
            children: recentDocs.take(5).map((doc) {
              final bool isNote = doc['type'] == 'nota';
              final int displayId = doc['id'];
              final String label = isNote ? "Nota #${doc['displayId']}" : "Cotización #${doc['displayId']}";
              final String client = doc['cliente'];
              final double total = doc['total'];
              
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isNote 
                            ? const Color(0xFF10B981).withOpacity(0.12)
                            : const Color(0xFF00ADEF).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isNote ? Icons.local_shipping_rounded : Icons.description_rounded,
                        color: isNote ? const Color(0xFF10B981) : const Color(0xFF00ADEF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Cliente: $client  •  ${total.toStringAsFixed(2)} Bs",
                            style: TextStyle(
                              color: textSecondaryColor,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.article_rounded, color: textSecondaryColor, size: 22),
                      onPressed: () {
                        if (isNote) {
                          _mostrarOpcionesNotaEntrega(doc['rawDoc'], displayId);
                        } else {
                          _mostrarOpcionesDocumento(doc['rawDoc'], displayId);
                        }
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 24),

        // SELLER SELECTOR DROPDOWN (KEEP IT AT BOTTOM)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Row(
            children: [
              const Icon(Icons.person, color: Color(0xFF00ADEF)),
              const SizedBox(width: 12),
              const Text("Vendedor:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedReportSeller,
                    dropdownColor: isDark ? const Color(0xFF131A26) : Colors.white,
                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                    items: allSellers.map((s) {
                      return DropdownMenuItem<String>(
                        value: s,
                        child: Text(s == 'todos' ? 'Todos los Vendedores' : s),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedReportSeller = val;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // TABLE RENDIMIENTO POR VENDEDOR
        Text(
          "Rendimiento por Vendedor",
          style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 12),
        if (sellersPerformance.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Text("No se encontraron registros en este período", style: TextStyle(color: textSecondaryColor)),
            ),
          )
        else
          ...sellersPerformance.map((perf) {
            final String name = perf['nombre'];
            final double notesTotal = perf['notesTotal'];
            final double quotesTotal = perf['quotesTotal'];
            final int notesCount = perf['notesCount'];
            final int quotesCount = perf['quotesCount'];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name == 'joel' ? 'joel (Dueño / Administrador)' : name,
                        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00ADEF).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "${notesTotal.toStringAsFixed(2)} Bs",
                          style: const TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: Colors.white10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Cotizaciones", style: TextStyle(color: textSecondaryColor, fontSize: 11)),
                            const SizedBox(height: 2),
                            Text("$quotesCount docs (${quotesTotal.toStringAsFixed(2)} Bs)", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Notas de Entrega", style: TextStyle(color: textSecondaryColor, fontSize: 11)),
                            const SizedBox(height: 2),
                            Text("$notesCount docs (${notesTotal.toStringAsFixed(2)} Bs)", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

  String _getMonthLabel(DateTime date) {
    final List<String> shortMonths = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
    ];
    return "${shortMonths[date.month - 1]} ${date.year.toString().substring(2)}";
  }

  void _showReportMonthPicker() {
    final now = DateTime.now();
    final List<DateTime> months = [];
    for (int i = 0; i < 12; i++) {
      months.add(DateTime(now.year, now.month - i, 1));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<String> monthNames = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
          title: Text(
            "Seleccionar Mes",
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: months.length,
              itemBuilder: (context, index) {
                final date = months[index];
                final monthName = monthNames[date.month - 1];
                final label = "$monthName ${date.year}";
                final isSelected = date.year == _selectedReportMonthDate.year && 
                                    date.month == _selectedReportMonthDate.month;

                return ListTile(
                  title: Text(
                    label,
                    style: TextStyle(
                      color: isSelected 
                          ? const Color(0xFF00ADEF) 
                          : (isDark ? Colors.white70 : Colors.black87),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected 
                      ? const Icon(Icons.check, color: Color(0xFF00ADEF)) 
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedReportMonthDate = date;
                      _selectedReportPeriod = 'mes';
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPeriodChip(String key, String label) {
    final isSelected = _selectedReportPeriod == key;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayLabel = (key == 'mes' && _selectedReportPeriod == 'mes') 
        ? "Mes: ${_getMonthLabel(_selectedReportMonthDate)}" 
        : label;

    return ChoiceChip(
      label: Text(displayLabel),
      selected: isSelected,
      onSelected: (val) {
        if (key == 'mes') {
          _showReportMonthPicker();
        } else {
          if (val) {
            setState(() {
              _selectedReportPeriod = key;
              if (key == 'custom') {
                _showReportDateRangePicker();
              }
            });
          }
        }
      },
      selectedColor: const Color(0xFF00ADEF),
      backgroundColor: isDark ? const Color(0xFF131A26) : Colors.grey[200]!,
      labelStyle: TextStyle(color: isSelected ? Colors.black : (isDark ? Colors.white70 : Colors.black87), fontWeight: FontWeight.bold),
    );
  }

  Future<void> _showReportDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _customDateRange ?? DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now()),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: Color(0xFF00ADEF),
                    onPrimary: Colors.black,
                    surface: Color(0xFF131A26),
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
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
        _customDateRange = picked;
      });
    }
  }

  Widget _buildSellerBarCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182232) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
          width: 1.0,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Row(
              children: [
                Icon(icon, color: color, size: 48),
                const SizedBox(width: 24),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.white.withOpacity(0.5) : Colors.black45,
                  size: 32,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTallCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required Color cardBg,
    required Color textColor,
    required Color iconColor,
    required List<BoxShadow> cardShadow,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Center(
                  child: AnimatedDashboardIcon(
                    type: 'box',
                    icon: icon,
                    color: iconColor,
                    size: 40,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediumCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required Color cardBg,
    required Color textColor,
    required Color iconColor,
    required List<BoxShadow> cardShadow,
    required VoidCallback onTap,
  }) {
    final String animType = title.toLowerCase().contains("foto") ? "palette" : "people";
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Center(
                  child: AnimatedDashboardIcon(
                    type: animType,
                    icon: icon,
                    color: iconColor,
                    size: 40,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Build row inside cotizaciones table
  TableRow _buildTableRow(Map<String, dynamic> quote, int index, bool isDark, Color primaryCyan) {
    final int quoteId = quote['id'] as int? ?? 0;
    final displayId = _cotizaciones.length - _cotizaciones.indexWhere((c) => c['id'] == quoteId);
    
    final formattedId = "#$displayId";
    final cliente = quote['clienteNombre']?.toString() ?? "Sin cliente";
    final fecha = quote['fecha']?.toString() ?? "Sin fecha";
    final totalVal = (quote['total'] as num?)?.toDouble() ?? 0.0;
    final totalStr = totalVal.toStringAsFixed(2);
    final hasNote = _tieneNotaEntrega(quote);

    return TableRow(
      decoration: BoxDecoration(
        color: index % 2 == 0 
            ? (isDark ? const Color(0xFF131A26) : Colors.white) 
            : (isDark ? const Color(0xFF1E293B).withOpacity(0.4) : Colors.grey[50]),
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      children: [
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: InkWell(
            onTap: () => _mostrarOpcionesDocumento(quote, displayId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Text(formattedId, style: TextStyle(color: primaryCyan, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: InkWell(
            onTap: () => _mostrarOpcionesDocumento(quote, displayId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Text(
                cliente,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: InkWell(
            onTap: () => _mostrarOpcionesDocumento(quote, displayId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Text(fecha, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          ),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: InkWell(
            onTap: () => _mostrarOpcionesDocumento(quote, displayId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Text(totalStr, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: InkWell(
            onTap: () => _mostrarOpcionesDocumento(quote, displayId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasNote 
                        ? Colors.green.withOpacity(0.12) 
                        : Colors.blueGrey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: hasNote 
                          ? Colors.green.withOpacity(0.3) 
                          : Colors.blueGrey.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasNote) ...[
                        const Icon(Icons.local_shipping, color: Colors.green, size: 12),
                        const SizedBox(width: 4),
                        const Text(
                          "Nota de Entrega",
                          style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ] else ...[
                        const Icon(Icons.receipt_long, color: Colors.grey, size: 12),
                        const SizedBox(width: 4),
                        const Text(
                          "Cotización",
                          style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- GOOGLE DRIVE DEBUG DIALOG (PRESERVED) ---
  void _showGoogleDebugDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String testResult = "Presiona 'Probar Conexión' para iniciar la prueba.";
        bool isTesting = false;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentUser = _drive.googleSignIn.currentUser;
            final hasDriveApi = _drive.driveApi != null;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final primaryCyan = const Color(0xFF00ADEF);

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.bug_report, color: Colors.redAccent),
                  const SizedBox(width: 10),
                  const Text("Google Debug Panel"),
                ],
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: isDark ? const Color(0xFF1F2833) : Colors.white,
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDebugSectionTitle("Usuario Autenticado"),
                    _buildDebugCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDebugField("Nombre:", currentUser?.displayName ?? "No conectado"),
                          _buildDebugField("Email:", currentUser?.email ?? "No conectado"),
                          _buildDebugField("ID:", currentUser?.id ?? "N/A"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildDebugSectionTitle("Estado de Google Drive"),
                    _buildDebugCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDebugField("API Inicializada:", hasDriveApi ? "SÍ (Conectado)" : "NO (Desconectado)"),
                          _buildDebugField("Último Error:", _drive.lastError ?? "Ninguno"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildDebugSectionTitle("Prueba de Conexión"),
                    _buildDebugCard(
                      isDark: isDark,
                      child: isTesting
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(10.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : Text(
                              testResult,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontFamily: 'monospace',
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text("Probar Conexión"),
                          style: ElevatedButton.styleFrom(backgroundColor: primaryCyan, foregroundColor: Colors.black),
                          onPressed: isTesting
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isTesting = true;
                                  });
                                  final result = await _drive.testConnection();
                                  if (mounted) {
                                    setDialogState(() {
                                      testResult = result;
                                      isTesting = false;
                                    });
                                  }
                                },
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text("Copiar Diagnóstico"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[700], foregroundColor: Colors.white),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: testResult));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("✅ Diagnóstico copiado al portapapeles")),
                            );
                          },
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.login, size: 16),
                          label: const Text("Forzar Login"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                          onPressed: () async {
                            final ok = await _drive.authenticate(forceSignIn: true);
                            if (mounted) {
                              setDialogState(() {
                                testResult = ok ? "Login exitoso!" : "Fallo: ${_drive.lastError}";
                              });
                              _loadAll(showLoading: false);
                            }
                          },
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.vpn_key, size: 16),
                          label: const Text("Pedir Permisos"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
                          onPressed: () async {
                            final granted = await _drive.googleSignIn.requestScopes([
                              'https://www.googleapis.com/auth/drive.file',
                              'https://www.googleapis.com/auth/drive',
                            ]);
                            if (mounted) {
                              setDialogState(() {
                                testResult = granted ? "Permisos concedidos!" : "Permisos denegados.";
                              });
                              _loadAll(showLoading: false);
                            }
                          },
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.logout, size: 16),
                          label: const Text("Salir Google"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                          onPressed: () async {
                            await _drive.signOut();
                            if (mounted) {
                              setDialogState(() {
                                testResult = "Sesión cerrada.";
                              });
                              _loadAll(showLoading: false);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CERRAR"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDebugSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00ADEF),
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildDebugCard({required Widget child, required bool isDark}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: child,
    );
  }

  Widget _buildDebugField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          children: [
            TextSpan(text: "$label ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            TextSpan(
              text: value,
              style: TextStyle(
                color: value.startsWith("Fallo") || value.startsWith("NO") || value.contains("denegados") || value.contains("error") || value.contains("cancelado")
                    ? Colors.redAccent
                    : (value.startsWith("SÍ") || value.startsWith("Éxito") || value.contains("exitoso") ? Colors.green : null),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- NUEVOS MÉTODOS DE LA COMPLEMENTACIÓN DEL DASHBOARD ---
  void _shiftPeriod(int direction) {
    setState(() {
      if (_selectedReportPeriod == 'hoy') {
        _selectedReportTodayDate = _selectedReportTodayDate.add(Duration(days: direction));
      } else if (_selectedReportPeriod == 'semana') {
        _selectedReportWeekDate = _selectedReportWeekDate.add(Duration(days: direction * 7));
      } else if (_selectedReportPeriod == 'mes') {
        _selectedReportMonthDate = DateTime(
          _selectedReportMonthDate.year,
          _selectedReportMonthDate.month + direction,
          1,
        );
      } else if (_selectedReportPeriod == 'custom' && _customDateRange != null) {
        final days = _customDateRange!.end.difference(_customDateRange!.start).inDays + 1;
        _customDateRange = DateTimeRange(
          start: _customDateRange!.start.add(Duration(days: direction * days)),
          end: _customDateRange!.end.add(Duration(days: direction * days)),
        );
      }
    });
  }

  String _getMonthName(int month) {
    const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return months[month - 1];
  }

  String _getMonthNameFull(int month) {
    const months = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return months[month - 1];
  }

  void _showPeriodSelectorSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "FILTRAR PERÍODO",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.today, color: Color(0xFF00ADEF)),
              title: const Text("Hoy"),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedReportPeriod = 'hoy';
                  _selectedReportTodayDate = DateTime.now();
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.view_week, color: Color(0xFF00ADEF)),
              title: const Text("Semana actual"),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedReportPeriod = 'semana';
                  _selectedReportWeekDate = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month, color: Color(0xFF00ADEF)),
              title: const Text("Seleccionar Mes"),
              onTap: () {
                Navigator.pop(context);
                _showReportMonthPicker();
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range, color: Color(0xFF00ADEF)),
              title: const Text("Rango Personalizado"),
              onTap: () {
                Navigator.pop(context);
                _showReportDateRangePicker();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required Color indicatorColor,
    required String indicatorLabel,
    required bool isDark,
  }) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondaryColor = isDark ? Colors.white70 : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.grey[100];
    
    return Container(
      width: 155,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textSecondaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  indicatorLabel,
                  style: TextStyle(
                    color: textSecondaryColor,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConversionCard({
    required String title,
    required String value,
    required double rate,
    required bool isDark,
  }) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondaryColor = isDark ? Colors.white70 : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.grey[100];
    
    return Container(
      width: 165,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textSecondaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: rate / 100.0,
                  strokeWidth: 3.5,
                  backgroundColor: isDark ? Colors.white10 : Colors.black12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00ADEF)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _mostrarOpcionesNotaEntrega(Map<String, dynamic> nota, int displayId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext c) {
        final isDark = Theme.of(c).brightness == Brightness.dark;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Opciones para Nota de Entrega #$displayId",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                title: const Text("Ver PDF Nota de Entrega"),
                onTap: () {
                  Navigator.pop(c);
                  _verPDFNotaEntrega(nota, displayId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text("Editar Nota de Entrega"),
                onTap: () {
                  Navigator.pop(c);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CrearNotaEntregaScreen(notaExistente: nota, displayId: displayId),
                    ),
                  ).then((_) => _loadAll());
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class AnimatedDashboardIcon extends StatefulWidget {
  final IconData? icon;
  final Widget? customChild;
  final String type;
  final Color color;
  final double size;

  const AnimatedDashboardIcon({
    super.key,
    this.icon,
    this.customChild,
    required this.type,
    required this.color,
    required this.size,
  });

  @override
  State<AnimatedDashboardIcon> createState() => _AnimatedDashboardIconState();
}

class _AnimatedDashboardIconState extends State<AnimatedDashboardIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    int durationMs = 2000;
    if (widget.type == 'calculator') durationMs = 1800;
    if (widget.type == 'box') durationMs = 2200;
    if (widget.type == 'palette') durationMs = 2500;
    if (widget.type == 'people') durationMs = 2800;
    if (widget.type == 'truck') durationMs = 1200;
    if (widget.type == 'warehouse') durationMs = 3000;
    if (widget.type == 'checklist') durationMs = 2000;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    // Loop type
    if (widget.type == 'truck' || widget.type == 'box') {
      _controller.repeat();
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = widget.customChild ??
        Icon(
          widget.icon,
          color: widget.color,
          size: widget.size,
        );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, childWidget) {
        final val = _controller.value;
        switch (widget.type) {
          case 'calculator':
            // Subtle pressing/pulsing with micro rotation
            final scale = 1.0 - (0.08 * val);
            final rot = -0.03 + (0.06 * val);
            return Transform.scale(
              scale: scale,
              child: Transform.rotate(
                angle: rot,
                child: childWidget,
              ),
            );

          case 'box':
            // Squash and stretch bounce
            double translationY = 0.0;
            double scaleX = 1.0;
            double scaleY = 1.0;

            if (val < 0.4) {
              // Going up
              final t = val / 0.4;
              translationY = -8.0 * Curves.easeOut.transform(t);
              scaleX = 1.0 - 0.06 * t;
              scaleY = 1.0 + 0.08 * t;
            } else if (val < 0.5) {
              // Peak floating
              translationY = -8.0;
              scaleX = 0.94;
              scaleY = 1.08;
            } else if (val < 0.9) {
              // Going down
              final t = (val - 0.5) / 0.4;
              translationY = -8.0 * (1.0 - Curves.easeIn.transform(t));
              scaleX = 0.94 + 0.06 * t;
              scaleY = 1.08 - 0.08 * t;
            } else {
              // Squash on floor
              final t = (val - 0.9) / 0.1;
              translationY = 0.0;
              final squashFactor = Curves.easeInOut.transform(1.0 - (t - 0.5).abs() * 2);
              scaleX = 1.0 + 0.10 * squashFactor;
              scaleY = 1.0 - 0.10 * squashFactor;
            }

            return Transform.translate(
              offset: Offset(0, translationY),
              child: Transform.scale(
                scaleX: scaleX,
                scaleY: scaleY,
                alignment: Alignment.bottomCenter,
                child: childWidget,
              ),
            );

          case 'palette':
            // Rotation swing (gentle paint sway)
            final angle = -0.12 + (0.24 * val);
            return Transform.rotate(
              angle: angle,
              alignment: Alignment.center,
              child: childWidget,
            );

          case 'people':
            // Breathing scale and subtle horizontal slide
            final scale = 1.0 + (0.06 * val);
            final slideX = -1.5 + (3.0 * val);
            return Transform.translate(
              offset: Offset(slideX, 0),
              child: Transform.scale(
                scale: scale,
                child: childWidget,
              ),
            );

          case 'truck':
            // Fast vibration/driving
            double offsetX = 0.0;
            double offsetY = 0.0;
            double angle = 0.0;
            if (val < 0.25) {
              offsetX = 1.5 * (val / 0.25);
              offsetY = -1.0 * (val / 0.25);
              angle = 0.01 * (val / 0.25);
            } else if (val < 0.5) {
              offsetX = 1.5 + 1.5 * ((val - 0.25) / 0.25);
              offsetY = -1.0 + 1.0 * ((val - 0.25) / 0.25);
              angle = 0.01 - 0.01 * ((val - 0.25) / 0.25);
            } else if (val < 0.75) {
              offsetX = 3.0 - 1.5 * ((val - 0.5) / 0.25);
              offsetY = -0.5 * ((val - 0.5) / 0.25);
              angle = 0.02 * ((val - 0.5) / 0.25);
            } else {
              offsetX = 1.5 - 1.5 * ((val - 0.75) / 0.25);
              offsetY = -0.5 + 0.5 * ((val - 0.75) / 0.25);
              angle = 0.02 - 0.02 * ((val - 0.75) / 0.25);
            }
            return Transform.translate(
              offset: Offset(offsetX, offsetY),
              child: Transform.rotate(
                angle: angle,
                child: childWidget,
              ),
            );

          case 'warehouse':
            // Vertical breathing
            final scaleY = 1.0 + (0.07 * val);
            return Transform.scale(
              scaleX: 1.0,
              scaleY: scaleY,
              alignment: Alignment.bottomCenter,
              child: childWidget,
            );

          case 'checklist':
            // Writing motion
            final dx = 4.0 * val;
            final dy = -4.0 * val;
            final angle = 0.08 * val;
            return Transform.translate(
              offset: Offset(dx, dy),
              child: Transform.rotate(
                angle: angle,
                child: childWidget,
              ),
            );

          default:
            return childWidget!;
        }
      },
      child: child,
    );
  }
}

class ModernLineChart extends StatelessWidget {
  final List<double> quotesData;
  final List<double> notesData;

  const ModernLineChart({
    super.key,
    required this.quotesData,
    required this.notesData,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 200,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: CustomPaint(
        painter: LineChartPainter(
          quotesData: quotesData,
          notesData: notesData,
          isDark: isDark,
        ),
      ),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> quotesData;
  final List<double> notesData;
  final bool isDark;

  LineChartPainter({
    required this.quotesData,
    required this.notesData,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (quotesData.isEmpty || notesData.isEmpty) return;

    double maxVal = 1.0;
    for (var v in quotesData) {
      if (v > maxVal) maxVal = v;
    }
    for (var v in notesData) {
      if (v > maxVal) maxVal = v;
    }
    if (maxVal == 0.0) maxVal = 1.0;
    maxVal *= 1.15;

    final width = size.width;
    final height = size.height;

    final Paint notesPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final Paint quotesPaint = Paint()
      ..color = const Color(0xFF00ADEF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final double stepX = width / 6.0;

    double getY(double val) {
      return height - (val / maxVal * height);
    }

    final Paint gridPaint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03)
      ..strokeWidth = 1.0;
    for (int i = 1; i < 4; i++) {
      final y = height * i / 4.0;
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    final Path notesPath = Path();
    final Path quotesPath = Path();

    notesPath.moveTo(0, getY(notesData[0]));
    quotesPath.moveTo(0, getY(quotesData[0]));

    for (int i = 1; i < 7; i++) {
      final x = i * stepX;
      notesPath.lineTo(x, getY(notesData[i]));
      quotesPath.lineTo(x, getY(quotesData[i]));
    }

    final Path filledPath = Path.from(notesPath);
    filledPath.lineTo(width, height);
    filledPath.lineTo(0, height);
    filledPath.close();

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF10B981).withOpacity(0.18),
          const Color(0xFF10B981).withOpacity(0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTRB(0, 0, width, height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(filledPath, fillPaint);

    canvas.drawPath(notesPath, notesPaint);

    // Draw quotes dashed line by drawing dashed segments between sequential vertices
    for (int i = 0; i < 6; i++) {
      final p1 = Offset(i * stepX, getY(quotesData[i]));
      final p2 = Offset((i + 1) * stepX, getY(quotesData[i + 1]));
      _drawDashedLine(canvas, p1, p2, quotesPaint);
    }

    final Paint notesDotPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;
      
    final Paint quotesDotPaint = Paint()
      ..color = const Color(0xFF00ADEF)
      ..style = PaintingStyle.fill;
      
    final Paint innerDotPaint = Paint()
      ..color = isDark ? const Color(0xFF182232) : Colors.white;

    for (int i = 0; i < 7; i++) {
      final x = i * stepX;
      canvas.drawCircle(Offset(x, getY(notesData[i])), 4.0, notesDotPaint);
      canvas.drawCircle(Offset(x, getY(notesData[i])), 2.0, innerDotPaint);
      
      canvas.drawCircle(Offset(x, getY(quotesData[i])), 4.0, quotesDotPaint);
      canvas.drawCircle(Offset(x, getY(quotesData[i])), 2.0, innerDotPaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dashWidth = 8.0;
    const double dashSpace = 4.0;
    
    final double dx = p2.dx - p1.dx;
    final double dy = p2.dy - p1.dy;
    final double distance = math.sqrt(dx * dx + dy * dy);
    
    if (distance == 0) return;
    
    final double steps = distance / (dashWidth + dashSpace);
    final double stepX = dx / steps;
    final double stepY = dy / steps;
    
    for (int i = 0; i < steps.toInt(); i++) {
      final double startX = p1.dx + stepX * i;
      final double startY = p1.dy + stepY * i;
      final double endX = p1.dx + stepX * i + stepX * (dashWidth / (dashWidth + dashSpace));
      final double endY = p1.dy + stepY * i + stepY * (dashWidth / (dashWidth + dashSpace));
      
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) {
    return oldDelegate.quotesData != quotesData ||
           oldDelegate.notesData != notesData ||
           oldDelegate.isDark != isDark;
  }
}
