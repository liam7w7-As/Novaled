import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'crear_nota_entrega_screen.dart';
import 'crear_cotizacion_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p_path;
import '../database_helper.dart';
import 'dart:convert';
import '../services/sync_service.dart';
import 'package:printing/printing.dart';
import '../services/pdf_service.dart';
import '../models/item_cotizacion.dart';
import '../widgets/zoomable_pdf_preview.dart';
import '../../login_screen.dart';
import '../../drive_service.dart';
import '../widgets/gestionar_pagos_page.dart';
import '../widgets/novaled_toast.dart';
import '../widgets/novaled_thick_icon.dart';
import '../tenant_helper.dart';
import 'cotizacion_vista_previa_screen.dart';
import '../tenant_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CotizacionesScreen extends StatefulWidget {
  final String tipoVenta;
  final String? initialTab;
  const CotizacionesScreen({super.key, this.tipoVenta = 'cotizacion', this.initialTab});

  @override
  State<CotizacionesScreen> createState() => _CotizacionesScreenState();
}

class _CotizacionesScreenState extends State<CotizacionesScreen> {
  List<Map<String, dynamic>> _cotizaciones = [];
  List<Map<String, dynamic>> _notasEntrega = [];
  List<Map<String, dynamic>> _proformas = [];
  List<Map<String, dynamic>> _filteredDocuments = [];
  
  final TextEditingController _searchController = TextEditingController();
  String _activeTab = 'todos'; // 'todos', 'pagados', 'por_cobrar'
  String _sucursalFiltro = 'todas'; // 'todas', '#818', '#840', etc.
  List<String> _listaSucursales = ["#818", "#840"];
  bool _isSyncing = false;
  bool _isSearching = false;
  Timer? _syncTimer;
  final DriveService _drive = DriveService();
  int _tapCount = 0;
  Timer? _tapTimer;

  @override
  void initState() {
    super.initState();
    _loadSucursales();
    if (widget.tipoVenta == 'punto_venta') {
      _activeTab = 'todos';
    } else {
      _activeTab = 'cotizaciones';
    }
    if (widget.initialTab != null) {
      _activeTab = widget.initialTab!;
    }
    _refreshDocuments().then((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _syncEverything(silent: true);
          }
        });
      }
    });
    // Sincronización automática periódica en tiempo real (cada 10 segundos)
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_isSyncing) {
        _syncEverything(silent: true);
      }
    });
  }

  Future<void> _loadSucursales() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tenantKey = await TenantHelper.getActiveTenantKey();
      final isNovaled = tenantKey == 'novaled';
      final saved = prefs.getStringList(TenantHelper.k('system_sucursales', tenantKey));
      if (mounted) {
        setState(() {
          _listaSucursales = saved ?? (isNovaled ? ["C. Isaac Tamayo #840 La Paz - Bolivia"] : []);
        });
      }
    } catch (_) {}
  }

  String _getDocSucursal(Map<String, dynamic> doc) {
    final isNovaled = TenantHelper.isNovaled(Session().userName);
    final rawSucursal = doc['sucursal']?.toString().trim();
    if (rawSucursal != null && rawSucursal.isNotEmpty && rawSucursal != 'null') {
      if (isNovaled && (rawSucursal == '#840' || rawSucursal == '#818')) {
        return "C. Isaac Tamayo $rawSucursal La Paz - Bolivia";
      }
      return rawSucursal;
    }
    final nota = _getNotaEntregaAsociada(doc);
    final notaSucursal = nota?['sucursal']?.toString().trim();
    if (notaSucursal != null && notaSucursal.isNotEmpty && notaSucursal != 'null') {
      if (isNovaled && (notaSucursal == '#840' || notaSucursal == '#818')) {
        return "C. Isaac Tamayo $notaSucursal La Paz - Bolivia";
      }
      return notaSucursal;
    }
    return _listaSucursales.isNotEmpty ? _listaSucursales.first : "";
  }

  List<String> _getAvailableSucursales() {
    final Set<String> sucursales = {..._listaSucursales};
    for (var doc in [..._cotizaciones, ..._proformas, ..._notasEntrega]) {
      final s = _getDocSucursal(doc);
      if (s.isNotEmpty) {
        sucursales.add(s);
      }
    }
    final list = sucursales.toList();
    list.sort();
    return list;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _tapTimer?.cancel();
    _searchController.dispose();
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

  List<Map<String, dynamic>> _getPuntoVentaMasterList() {
    final Map<String, Map<String, dynamic>> mapByUuid = {};
    final List<Map<String, dynamic>> itemsSinUuid = [];

    for (var p in _proformas) {
      final uuid = p['uuid']?.toString();
      final docMap = {...p, 'tipo': p['tipo_documento'] ?? 'proforma'};
      if (uuid != null && uuid.isNotEmpty) {
        mapByUuid[uuid] = docMap;
      } else {
        itemsSinUuid.add(docMap);
      }
    }

    for (var n in _notasEntrega) {
      final uuid = n['uuid']?.toString();
      final docMap = {...n, 'tipo': n['tipo_documento'] ?? 'nota_entrega'};
      if (uuid != null && uuid.isNotEmpty) {
        if (!mapByUuid.containsKey(uuid)) {
          mapByUuid[uuid] = docMap;
        }
      } else {
        itemsSinUuid.add(docMap);
      }
    }

    for (var c in _cotizaciones) {
      if (c['tipo_venta'] == 'punto_venta') {
        final uuid = c['uuid']?.toString();
        final docMap = {...c, 'tipo': 'cotizacion'};
        if (uuid != null && uuid.isNotEmpty) {
          if (!mapByUuid.containsKey(uuid)) {
            mapByUuid[uuid] = docMap;
          }
        } else {
          itemsSinUuid.add(docMap);
        }
      }
    }

    List<Map<String, dynamic>> masterList = [...mapByUuid.values, ...itemsSinUuid];

    // Orden cronológico (del más antiguo al más reciente: 1, 2, 3... N)
    masterList.sort((a, b) {
      final dateA = a['fecha']?.toString() ?? '';
      final dateB = b['fecha']?.toString() ?? '';
      final dateComp = dateA.compareTo(dateB);
      if (dateComp != 0) return dateComp;

      final idA = a['id'] as int? ?? 0;
      final idB = b['id'] as int? ?? 0;
      return idA.compareTo(idB);
    });

    return masterList;
  }

  int _getDisplayId(Map<String, dynamic> doc) {
    if (widget.tipoVenta == 'punto_venta') {
      final masterList = _getPuntoVentaMasterList();
      final uuid = doc['uuid']?.toString();
      int idx = -1;
      if (uuid != null && uuid.isNotEmpty) {
        idx = masterList.indexWhere((m) => m['uuid']?.toString() == uuid);
      }
      if (idx == -1) {
        idx = masterList.indexWhere((m) => m['id'] == doc['id'] && m['tipo'] == doc['tipo']);
      }
      if (idx == -1) {
        idx = masterList.indexWhere((m) => m['id'] == doc['id']);
      }
      return idx != -1 ? (idx + 1) : (doc['id'] as int? ?? 0);
    }

    final uuid = doc['uuid']?.toString();
    final isCot = doc['tipo'] == 'cotizacion' || (doc['tipo'] == null && doc.containsKey('impuesto'));
    
    if (isCot) {
      final idx = _cotizaciones.indexWhere((c) => c['id'] == doc['id']);
      return idx != -1 ? (_cotizaciones.length - idx) : (doc['id'] as int? ?? 0);
    } else {
      if (uuid != null && uuid.isNotEmpty) {
        final quoteIdx = _cotizaciones.indexWhere((c) => c['uuid']?.toString() == uuid);
        if (quoteIdx != -1) {
          return _cotizaciones.length - quoteIdx;
        }
      }
      final idx = _notasEntrega.indexWhere((n) => n['id'] == doc['id']);
      return idx != -1 ? (_notasEntrega.length - idx) : (doc['id'] as int? ?? 0);
    }
  }

  Future<void> _refreshDocuments() async {
    final quotesData = await DatabaseHelper.instance.queryAllCotizaciones(tipoVenta: widget.tipoVenta);
    final notesData = await DatabaseHelper.instance.queryAllNotasEntrega(tipoVenta: widget.tipoVenta);
    final proformasData = await DatabaseHelper.instance.queryAllProformas(tipoVenta: widget.tipoVenta);

    final sortedQuotes = _sortDocuments(quotesData);
    final sortedNotes = _sortDocuments(notesData);
    final sortedProformas = _sortDocuments(proformasData);

    if (mounted) {
      setState(() {
        _cotizaciones = sortedQuotes;
        _notasEntrega = sortedNotes;
        _proformas = sortedProformas;
      });
      _filterDocuments();
    }
  }

  void _filterDocuments() {
    if (widget.tipoVenta == 'cotizacion') {
      List<Map<String, dynamic>> baseList = _cotizaciones.map((c) => {...c, 'tipo': 'cotizacion'}).toList();
      baseList = _sortDocuments(baseList);

      if (_sucursalFiltro != 'todas') {
        baseList = baseList.where((doc) => _getDocSucursal(doc) == _sucursalFiltro).toList();
      }

      final query = _searchController.text.toLowerCase().trim();
      if (query.isEmpty) {
        setState(() {
          _filteredDocuments = baseList;
        });
      } else {
        setState(() {
          _filteredDocuments = baseList.where((doc) {
            final cliente = (doc['clienteNombre'] ?? '').toString().toLowerCase();
            final idStr = doc['id'].toString();
            final displayIdStr = _getDisplayId(doc).toString();

            return cliente.contains(query) || idStr.contains(query) || displayIdStr.contains(query);
          }).toList();
        });
      }
    } else {
      // Punto de Venta (Solo Proformas y Notas de Entrega)
      final Map<String, Map<String, dynamic>> mapByUuid = {};
      final List<Map<String, dynamic>> itemsSinUuid = [];

      for (var p in _proformas) {
        final uuid = p['uuid']?.toString();
        final docMap = {...p, 'tipo': p['tipo_documento'] ?? 'proforma'};
        if (uuid != null && uuid.isNotEmpty) {
          mapByUuid[uuid] = docMap;
        } else {
          itemsSinUuid.add(docMap);
        }
      }

      for (var n in _notasEntrega) {
        final uuid = n['uuid']?.toString();
        final docMap = {...n, 'tipo': n['tipo_documento'] ?? 'nota_entrega'};
        if (uuid != null && uuid.isNotEmpty) {
          if (!mapByUuid.containsKey(uuid)) {
            mapByUuid[uuid] = docMap;
          }
        } else {
          itemsSinUuid.add(docMap);
        }
      }

      List<Map<String, dynamic>> baseList = [...mapByUuid.values, ...itemsSinUuid];
      baseList = _sortDocuments(baseList);

      if (_sucursalFiltro != 'todas') {
        baseList = baseList.where((doc) => _getDocSucursal(doc) == _sucursalFiltro).toList();
      }

      if (_activeTab == 'pagados') {
        baseList = baseList.where((doc) {
          final estadoPago = (doc['estado_pago'] ?? '').toString().toLowerCase();
          final comprobado = doc['comprobado'] as int? ?? 0;
          final estado = (doc['estado'] ?? '').toString().toLowerCase();
          return (estadoPago == 'pagado' || estadoPago == 'cobrado' || comprobado == 1 || estado == 'aprobada') && estado != 'anulada' && estadoPago != 'anulada';
        }).toList();
      } else if (_activeTab == 'por_cobrar') {
        baseList = baseList.where((doc) {
          final estadoPago = (doc['estado_pago'] ?? '').toString().toLowerCase();
          final comprobado = doc['comprobado'] as int? ?? 0;
          final estado = (doc['estado'] ?? '').toString().toLowerCase();
          return estadoPago != 'pagado' && estadoPago != 'cobrado' && comprobado == 0 && estado != 'aprobada' && estado != 'anulada' && estadoPago != 'anulada';
        }).toList();
      }

      final query = _searchController.text.toLowerCase().trim();
      if (query.isEmpty) {
        setState(() {
          _filteredDocuments = baseList;
        });
      } else {
        setState(() {
          _filteredDocuments = baseList.where((doc) {
            final cliente = (doc['clienteNombre'] ?? '').toString().toLowerCase();
            final idStr = doc['id'].toString();
            final displayIdStr = _getDisplayId(doc).toString();

            return cliente.contains(query) || idStr.contains(query) || displayIdStr.contains(query);
          }).toList();
        });
      }
    }
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

  void _irANotaEntregaAsociada(Map<String, dynamic> cot) {
    final nota = _getNotaEntregaAsociada(cot);
    if (nota != null) {
      final displayId = _getDisplayId({...nota, 'tipo': 'nota_entrega'});
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => CrearNotaEntregaScreen(notaExistente: nota, displayId: displayId)),
      ).then((_) => _refreshDocuments());
    }
  }
  void _compartirDocumento({
    required BuildContext context,
    required String type,
    required String formattedId,
    required String clienteNombre,
    required double total,
    required Future<Uint8List> Function() generateBytes,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Enviar Documento",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Selecciona el método de envío. Para emuladores (BlueStacks), utiliza la opción de WhatsApp para evitar cierres.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.message_rounded, color: Color(0xFF25D366)),
                  ),
                  title: Text(
                    "Compartir por WhatsApp",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: const Text("Guarda el PDF local y copia el mensaje de texto"),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final bytes = await generateBytes();
                      Directory? directory;
                      if (Platform.isAndroid) {
                        directory = Directory('/storage/emulated/0/Download');
                        if (!await directory.exists()) {
                          directory = await getExternalStorageDirectory();
                        }
                      } else {
                        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
                      }
                      if (directory == null) throw Exception("No se pudo acceder a descargas");
                      
                      final filename = type == 'cotizacion' ? 'Cotizacion_COT-$formattedId.pdf' : 'Nota_de_entrega_NE-$formattedId.pdf';
                      final file = File('${directory.path}/$filename');
                      await file.writeAsBytes(bytes);
                      
                      final String msg = type == 'cotizacion'
                          ? "Hola. Le envío la Cotización #COT-$formattedId para $clienteNombre por un total de ${total.toStringAsFixed(2)} Bs. El PDF ha sido guardado en la carpeta de Descargas de su dispositivo."
                          : "Hola. Le envío la Nota de Entrega #NE-$formattedId para $clienteNombre por un total de ${total.toStringAsFixed(2)} Bs. El PDF ha sido guardado en la carpeta de Descargas de su dispositivo.";
                      
                      await Clipboard.setData(ClipboardData(text: msg));
                      
                      final url = Uri.parse("whatsapp://send?text=${Uri.encodeComponent(msg)}");
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } else {
                        final webUrl = Uri.parse("https://wa.me/?text=${Uri.encodeComponent(msg)}");
                        if (await canLaunchUrl(webUrl)) {
                          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
                        }
                      }
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("PDF guardado y mensaje copiado. Abriendo WhatsApp..."),
                            backgroundColor: const Color(0xFF25D366),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Error: $e"),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00ADEF).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.share_rounded, color: Color(0xFF00ADEF)),
                  ),
                  title: Text(
                    "Compartir Directo (Correo/Otros)",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: const Text("Abre la hoja de compartir nativa (puede fallar en emuladores)"),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final bytes = await generateBytes();
                      final filename = type == 'cotizacion' ? 'Cotizacion_COT-$formattedId.pdf' : 'Nota_de_entrega_NE-$formattedId.pdf';
                      await Printing.sharePdf(bytes: bytes, filename: filename);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Error al compartir: $e"),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _verPDFCotizacion(Map<String, dynamic> cot, int displayId) async {
    if (!mounted) return;

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
          final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
          final String formattedId = docId.toString().padLeft(5, '0');

          Future<Uint8List> getPdfBytes() {
            return PdfService.generateCotizacionBytes(
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
              isColor: true,
              fecha: fecha,
              sucursal: _getDocSucursal(cot),
              vendedor: cot['vendedor']?.toString(),
            );
          }

          return Dialog.fullscreen(
            child: Scaffold(
              backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
              appBar: AppBar(
                backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
                elevation: 0,
                leading: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: NovaledThickIcon(
                        assetPath: 'Iconos/pantalla 3/atras.png',
                        size: 24,
                        color: textColor,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                title: Text(
                  "Cotización lista",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    fontSize: 19,
                  ),
                ),
                centerTitle: true,
                actions: [
                  IconButton(
                    icon: Icon(Icons.print_outlined, color: textColor),
                    onPressed: () async {
                      final bytes = await getPdfBytes();
                      await Printing.layoutPdf(onLayout: (format) async => bytes);
                    },
                  ),
                ],
              ),
              body: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: PdfPreview(
                          build: (format) => getPdfBytes(),
                          useActions: false,
                          previewPageMargin: EdgeInsets.zero,
                          padding: EdgeInsets.zero,
                          pdfPreviewPageDecoration: const BoxDecoration(
                            color: Colors.white,
                            boxShadow: [],
                          ),
                          scrollViewDecoration: BoxDecoration(
                            color: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
                          ),
                          canChangeOrientation: false,
                          canChangePageFormat: false,
                          canDebug: false,
                          loadingWidget: const Center(
                            child: CircularProgressIndicator(color: Color(0xFF5842F4)),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          GestureDetector(
                            onTap: () async {
                              try {
                                final currentBytes = await getPdfBytes();
                                Directory? directory;
                                if (Platform.isAndroid) {
                                  directory = Directory('/storage/emulated/0/Download');
                                  if (!await directory.exists()) {
                                    directory = await getExternalStorageDirectory();
                                  }
                                } else {
                                  directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
                                }
                                if (directory != null) {
                                  final file = File('${directory.path}/Cotizacion_COT-$formattedId.pdf');
                                  await file.writeAsBytes(currentBytes);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("PDF guardado en: ${directory.path.split('/').last}/Cotizacion_COT-$formattedId.pdf"),
                                        backgroundColor: const Color(0xFF00ADEF),
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                debugPrint("Error al descargar PDF: $e");
                              }
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF262822) : Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Icon(Icons.file_download_outlined, color: textColor, size: 24),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Descargar",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              _editarDocumento(cot, docId);
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF262822) : Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Icon(Icons.edit_outlined, color: textColor, size: 24),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Editar",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final bytes = await getPdfBytes();
                              await Printing.sharePdf(
                                bytes: bytes,
                                filename: "Cotizacion_COT-$formattedId.pdf",
                              );
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF262822) : Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Icon(Icons.share_outlined, color: textColor, size: 24),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Compartir",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5842F4),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: Text(
                            "Volver a cotizaciones",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
    final String notas = nota['notas'] ?? nota['notes'] ?? "";
    final String terminos = nota['terminos'] ?? "";
    final int docId = displayId;
    final bool incluyeFirmaEmpresa = (nota['incluyeFirmaEmpresa'] ?? 0) == 1;
    final bool incluyeFirmaCliente = (nota['incluyeFirmaCliente'] ?? 0) == 1;
    final bool mostrarTerminos = (nota['mostrarTerminos'] ?? 1) == 1;
    final bool mostrarAhorro = false;
    final String fecha = nota['fecha'] ?? "";

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CotizacionVistaPreviaScreen(
          titulo: "Nota de entrega",
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
          tituloDocumento: "NOTA DE ENTREGA",
          fecha: fecha,
          sucursal: _getDocSucursal(nota),
          vendedor: nota['vendedor']?.toString(),
          returnButtonText: "Volver a notas de entrega",
          onEdit: () {
            Navigator.pop(context);
            _editarDocumento(nota, docId);
          },
        ),
      ),
    );
  }

  Future<void> _syncEverything({bool silent = false}) async {
    if (!mounted) return;
    setState(() => _isSyncing = true);

    try {
      final success1 = await SyncService.instance.syncTable('cotizaciones').timeout(const Duration(seconds: 30));
      final success2 = await SyncService.instance.syncTable('notas_entrega').timeout(const Duration(seconds: 30));
      final success3 = await SyncService.instance.syncTable('proformas').timeout(const Duration(seconds: 30));
      await _refreshDocuments();
      if (!silent && mounted) {
        if (success1 && success2 && success3) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Sincronización completa exitosa"), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Error al sincronizar con el servidor"), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint("Error sync: $e");
      if (!silent && mounted) {
        final cleanMsg = e.toString().replaceFirst('Exception: ', '');
        final isOffline = cleanMsg.contains("Modo Offline");
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _confirmarEliminacion(Map<String, dynamic> item) async {
    final String tipoDoc = item['tipo']?.toString() ?? '';
    final bool isCotizacion = tipoDoc == 'cotizacion' && widget.tipoVenta != 'punto_venta';

    // Registrar borrado localmente
    try {
      final uuidVal = item['uuid']?.toString() ?? item['folderId']?.toString();
      if (uuidVal != null && uuidVal.isNotEmpty) {
        final tableName = isCotizacion ? 'cotizaciones' : 'proformas';
        await DatabaseHelper.instance.recordDeletion(tableName, uuidVal);
      }
    } catch (e) {
      debugPrint("Error al registrar borrado: $e");
    }

    // Borrado en base de datos local
    try {
      final id = item['id'];
      if (id != null) {
        if (widget.tipoVenta == 'punto_venta') {
          await DatabaseHelper.instance.deleteProforma(id);
          await DatabaseHelper.instance.deleteNotaEntrega(id);
        } else if (isCotizacion) {
          await DatabaseHelper.instance.deleteCotizacion(id);
        } else {
          await DatabaseHelper.instance.deleteProforma(id);
          await DatabaseHelper.instance.deleteNotaEntrega(id);
        }
      }
    } catch (e) {
      debugPrint("Error al borrar localmente: $e");
    }

    if (mounted) {
      setState(() {
        _filteredDocuments.removeWhere((doc) => doc['id'] == item['id']);
        _proformas.removeWhere((doc) => doc['id'] == item['id']);
        _notasEntrega.removeWhere((doc) => doc['id'] == item['id']);
        _cotizaciones.removeWhere((doc) => doc['id'] == item['id']);
      });
      NovaledToast.borrado(context);
      await _refreshDocuments();
      _syncEverything(silent: true);
    }
  }

  void _editarDocumento(Map<String, dynamic> doc, int displayId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CrearCotizacionScreen(
          cotizacionExistente: doc,
          displayId: displayId,
          tipoVenta: widget.tipoVenta,
        ),
      ),
    ).then((_) => _refreshDocuments());
  }

  void _duplicarDocumento(Map<String, dynamic> doc) async {
    final isCotizacion = doc['tipo'] == 'cotizacion';

    if (isCotizacion) {
      final canCreate = await PlanLimitHelper.canCreateCotizacion();
      if (!canCreate) {
        if (mounted) {
          PlanLimitHelper.showUpgradeDialog(context, feature: "cotizaciones", currentLimit: PlanLimitHelper.freeCotizaciones);
        }
        return;
      }
    } else {
      final canCreate = await PlanLimitHelper.canCreateNotaEntrega();
      if (!canCreate) {
        if (mounted) {
          PlanLimitHelper.showUpgradeDialog(context, feature: "notas de entrega", currentLimit: PlanLimitHelper.freeNotasEntrega);
        }
        return;
      }
    }

    final Map<String, dynamic> nuevo = Map.from(doc);
    nuevo.remove('id');
    nuevo.remove('tipo');
    nuevo.remove('uuid');
    nuevo['fecha'] = DateTime.now().toString().split('.')[0];
    nuevo['tipo_venta'] = widget.tipoVenta;

    if (isCotizacion) {
      await DatabaseHelper.instance.insertCotizacion(nuevo);
    } else {
      await DatabaseHelper.instance.insertNotaEntrega(nuevo);
    }
    _refreshDocuments();
  }

  Future<void> _anularVenta(Map<String, dynamic> doc) async {
    try {
      final id = doc['id'] as int?;
      if (id == null) return;

      final isCot = doc['tipo'] == 'cotizacion';
      final isNota = doc['tipo'] == 'nota_entrega';
      final table = isNota ? 'notas_entrega' : (isCot ? 'cotizaciones' : 'proformas');

      final db = await DatabaseHelper.instance.database;
      await DatabaseHelper.instance.setTableDirty(table);
      await db.update(
        table,
        {
          'estado': 'anulada',
          'estado_pago': 'anulada',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final uuid = doc['uuid']?.toString();
      if (uuid != null && uuid.isNotEmpty) {
        for (var t in ['cotizaciones', 'proformas', 'notas_entrega']) {
          if (t != table) {
            try {
              await DatabaseHelper.instance.setTableDirty(t);
              await db.update(
                t,
                {'estado': 'anulada', 'estado_pago': 'anulada'},
                where: 'uuid = ?',
                whereArgs: [uuid],
              );
            } catch (_) {}
          }
        }
      }

      SyncService.instance.syncTable(table).catchError((e) {});
      _refreshDocuments();
    } catch (e) {
      debugPrint("Error al anular venta: $e");
    }
  }

  Future<void> _llevarANotaEntrega(Map<String, dynamic> cot) async {
    final canCreate = await PlanLimitHelper.canCreateNotaEntrega();
    if (!canCreate) {
      if (mounted) {
        PlanLimitHelper.showUpgradeDialog(context, feature: "notas de entrega", currentLimit: PlanLimitHelper.freeNotasEntrega);
      }
      return;
    }

    final Map<String, dynamic> nuevaNota = Map.from(cot);
    nuevaNota.remove('id');
    nuevaNota.remove('tipo');
    nuevaNota.remove('estado');
    nuevaNota['fecha'] = DateTime.now().toString().split('.')[0];
    nuevaNota['terminos'] =
        "• Recibí conforme los productos detallados.\n• No se aceptan devoluciones después de 48 hrs.\n• La mercadería viaja por cuenta y riesgo del cliente.";
    nuevaNota['tipo_venta'] = widget.tipoVenta;

    await DatabaseHelper.instance.insertNotaEntrega(nuevaNota);
    _refreshDocuments();
  }

  Future<void> _llevarAPuntoDeVenta(Map<String, dynamic> nota) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final uuid = nota['uuid']?.toString() ?? '';
      if (uuid.isEmpty) {
        throw Exception("El documento no tiene un identificador único (UUID).");
      }
      
      // Verificar si ya existe en proformas
      final List<Map<String, dynamic>> existingProforma = await db.query(
        'proformas',
        where: 'uuid = ?',
        whereArgs: [uuid],
      );

      if (existingProforma.isNotEmpty) {
        return;
      }

      final canCreate = await PlanLimitHelper.canCreateNotaVenta();
      if (!canCreate) {
        if (mounted) {
          PlanLimitHelper.showUpgradeDialog(context, feature: "notas de venta", currentLimit: PlanLimitHelper.freeNotasVenta);
        }
        return;
      }

      final Map<String, dynamic> proforma = Map<String, dynamic>.from(nota);
      proforma.remove('id');
      proforma.remove('tipo');
      proforma.remove('estado');
      proforma['uuid'] = uuid;
      proforma['tipo_venta'] = 'venta_institucional';
      proforma['estado_pago'] = 'por_cobrar';
      proforma['metodo_pago'] = nota['metodo_pago'] ?? 'Transferencia';
      proforma['fecha'] = DateTime.now().toString().split('.')[0];

      final proformaId = await DatabaseHelper.instance.insertProforma(proforma);

      // Sincronizar proforma en segundo plano
      final allProformas = await DatabaseHelper.instance.queryAllProformas();
      final matchProforma = allProformas.firstWhere((p) => p['id'] == proformaId);
      _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(matchProforma)).then((newFolderId) async {
        if (newFolderId != null && newFolderId != matchProforma['folderId']) {
          final updated = Map<String, dynamic>.from(matchProforma)..['folderId'] = newFolderId;
          await DatabaseHelper.instance.updateProforma(updated);
        }
        SyncService.instance.syncEverything().catchError((e) {
          debugPrint("Silent Hostinger sync error (proformas): $e");
        });
      });

      _refreshDocuments();
    } catch (e) {
      debugPrint("Error al llevar nota a punto de venta: $e");
    }
  }

  Future<void> _generarCopiaProforma(Map<String, dynamic> doc) async {
    try {
      final canCreate = await PlanLimitHelper.canCreateNotaVenta();
      if (!canCreate) {
        if (mounted) {
          PlanLimitHelper.showUpgradeDialog(context, feature: "notas de venta", currentLimit: PlanLimitHelper.freeNotasVenta);
        }
        return;
      }

      final Map<String, dynamic> proforma = Map<String, dynamic>.from(doc);
      proforma.remove('id');
      proforma.remove('tipo');
      proforma.remove('estado');
      proforma['uuid'] = DatabaseHelper.instance.generateUUID();
      proforma['tipo_venta'] = 'punto_venta';
      proforma['tipo_documento'] = 'proforma';
      proforma['estado_pago'] = 'por_cobrar';
      proforma['metodo_pago'] = doc['metodo_pago'] ?? 'Transferencia';
      proforma['fecha'] = DateTime.now().toString().split('.')[0];

      final proformaId = await DatabaseHelper.instance.insertProforma(proforma);

      final allProformas = await DatabaseHelper.instance.queryAllProformas();
      final matchProforma = allProformas.firstWhere((p) => p['id'] == proformaId, orElse: () => proforma);
      _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(matchProforma)).then((newFolderId) async {
        if (newFolderId != null && newFolderId != matchProforma['folderId']) {
          final updated = Map<String, dynamic>.from(matchProforma)..['folderId'] = newFolderId;
          await DatabaseHelper.instance.updateProforma(updated);
        }
        SyncService.instance.syncEverything().catchError((e) {
          debugPrint("Silent Hostinger sync error (proformas): $e");
        });
      });

      _refreshDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Se generó la proforma en Punto de Venta"),
            backgroundColor: Color(0xFF5842F4),
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/cotizaciones',
            arguments: {'tipoVenta': 'punto_venta'},
          );
        }
      }
    } catch (e) {
      debugPrint("Error al generar copia proforma: $e");
    }
  }

  Future<void> _generarCopiaNotaEntrega(Map<String, dynamic> doc) async {
    try {
      final canCreate = await PlanLimitHelper.canCreateNotaVenta();
      if (!canCreate) {
        if (mounted) {
          PlanLimitHelper.showUpgradeDialog(context, feature: "notas de venta", currentLimit: PlanLimitHelper.freeNotasVenta);
        }
        return;
      }

      final Map<String, dynamic> nota = Map<String, dynamic>.from(doc);
      nota.remove('id');
      nota.remove('tipo');
      nota.remove('estado');
      nota['uuid'] = DatabaseHelper.instance.generateUUID();
      nota['tipo_venta'] = 'punto_venta';
      nota['tipo_documento'] = 'nota_entrega';
      nota['estado_pago'] = 'por_cobrar';
      nota['metodo_pago'] = doc['metodo_pago'] ?? 'Transferencia';
      nota['fecha'] = DateTime.now().toString().split('.')[0];

      final notaId = await DatabaseHelper.instance.insertProforma(nota);

      final allProformas = await DatabaseHelper.instance.queryAllProformas();
      final matchNota = allProformas.firstWhere((p) => p['id'] == notaId, orElse: () => nota);
      _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(matchNota)).then((newFolderId) async {
        if (newFolderId != null && newFolderId != matchNota['folderId']) {
          final updated = Map<String, dynamic>.from(matchNota)..['folderId'] = newFolderId;
          await DatabaseHelper.instance.updateProforma(updated);
        }
        SyncService.instance.syncEverything().catchError((e) {
          debugPrint("Silent Hostinger sync error (proformas): $e");
        });
      });

      _refreshDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Se generó la nota de entrega en Punto de Venta"),
            backgroundColor: Color(0xFF5842F4),
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/cotizaciones',
            arguments: {'tipoVenta': 'punto_venta'},
          );
        }
      }
    } catch (e) {
      debugPrint("Error al generar copia nota entrega: $e");
    }
  }

  void _mostrarDialogoPagos(Map<String, dynamic> doc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCotizacion = doc['tipo'] == 'cotizacion';
    final table = isCotizacion ? 'cotizaciones' : 'notas_entrega';
    final id = doc['id'] as int;
    final total = (doc['total'] as num?)?.toDouble() ?? 0.0;

    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (dialogContext) {
          return GestionarPagosPage(
            doc: doc,
            onImagePicker: () => _seleccionarImagenComprobante(),
            onSave: (finalSaldoCancelado, currentComprobanteImg, currentComprobado, currentMetodoPago) async {
              final finalEstadoPago = (finalSaldoCancelado >= total - 0.01) ? 'cobrado' : 'por_cobrar';
              
              await DatabaseHelper.instance.updateDocumentPago(
                table: table,
                id: id,
                saldoCancelado: finalSaldoCancelado,
                comprobanteImg: currentComprobanteImg,
                comprobado: currentComprobado,
              );
              
              final db = await DatabaseHelper.instance.database;
              
              if (isCotizacion) {
                final String finalEstado = (currentComprobado == 1) ? 'aprobada' : 'pendiente';
                await db.update(
                  'cotizaciones',
                  {
                    'metodo_pago': currentMetodoPago,
                    'estado_pago': finalEstadoPago,
                    'estado': finalEstado,
                  },
                  where: 'id = ?',
                  whereArgs: [id],
                );
              } else {
                await db.update(
                  table,
                  {
                    'metodo_pago': currentMetodoPago,
                    'estado_pago': finalEstadoPago,
                  },
                  where: 'id = ?',
                  whereArgs: [id],
                );
              }

              if (isCotizacion && currentComprobado == 1) {
                final updatedList = await DatabaseHelper.instance.queryAllCotizaciones(tipoVenta: widget.tipoVenta);
                final updatedDoc = updatedList.firstWhere((c) => c['id'] == id);

                String uuid = updatedDoc['uuid']?.toString() ?? '';
                if (uuid.isEmpty) {
                  uuid = DatabaseHelper.instance.generateUUID();
                  await db.update(
                    'cotizaciones',
                    {'uuid': uuid},
                    where: 'id = ?',
                    whereArgs: [id],
                  );
                }

                if (!_tieneNotaEntrega(updatedDoc)) {
                  await _llevarANotaEntrega(updatedDoc);
                }

                // Copiar copia exacta a Venta Institucional (proformas)
                try {
                  final List<Map<String, dynamic>> existingProforma = await db.query(
                    'proformas',
                    where: 'uuid = ?',
                    whereArgs: [uuid],
                  );
                  if (existingProforma.isEmpty) {
                    final Map<String, dynamic> proforma = Map<String, dynamic>.from(updatedDoc);
                    proforma.remove('id');
                    proforma.remove('estado');
                    proforma['uuid'] = uuid;
                    proforma['tipo_venta'] = 'venta_institucional';
                    proforma['estado_pago'] = 'por_cobrar';
                    proforma['metodo_pago'] = currentMetodoPago;
                    
                    final proformaId = await DatabaseHelper.instance.insertProforma(proforma);
                    
                    // Sincronizar proforma en segundo plano
                    final allProformas = await DatabaseHelper.instance.queryAllProformas();
                    final matchProforma = allProformas.firstWhere((p) => p['id'] == proformaId);
                    _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(matchProforma)).then((newFolderId) async {
                      if (newFolderId != null && newFolderId != matchProforma['folderId']) {
                        final updated = Map<String, dynamic>.from(matchProforma)..['folderId'] = newFolderId;
                        await DatabaseHelper.instance.updateProforma(updated);
                      }
                      SyncService.instance.syncEverything().catchError((e) {
                        debugPrint("Silent Hostinger sync error (proformas): $e");
                      });
                    });
                  } else {
                    final Map<String, dynamic> proforma = Map<String, dynamic>.from(updatedDoc);
                    proforma.remove('id');
                    proforma.remove('estado');
                    proforma['uuid'] = uuid;
                    proforma['tipo_venta'] = 'venta_institucional';
                    proforma['estado_pago'] = finalEstadoPago;
                    proforma['metodo_pago'] = currentMetodoPago;
                    
                    final match = existingProforma.first;
                    await db.update(
                      'proformas',
                      proforma,
                      where: 'id = ?',
                      whereArgs: [match['id']],
                    );

                    final allProformas = await DatabaseHelper.instance.queryAllProformas();
                    final matchProforma = allProformas.firstWhere((p) => p['id'] == match['id']);
                    _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(matchProforma)).then((newFolderId) async {
                      if (newFolderId != null && newFolderId != matchProforma['folderId']) {
                        final updated = Map<String, dynamic>.from(matchProforma)..['folderId'] = newFolderId;
                        await DatabaseHelper.instance.updateProforma(updated);
                      }
                      SyncService.instance.syncEverything().catchError((e) {
                        debugPrint("Silent Hostinger sync error (proformas): $e");
                      });
                    });
                  }
                } catch (e) {
                  debugPrint("Error al copiar cotización aprobada a proforma: $e");
                }
              } else if (isCotizacion && currentComprobado == 0) {
                try {
                  final list = await DatabaseHelper.instance.queryAllCotizaciones(tipoVenta: widget.tipoVenta);
                  final matchCot = list.firstWhere((c) => c['id'] == id);
                  String uuid = matchCot['uuid']?.toString() ?? '';
                  if (uuid.isNotEmpty) {
                    await db.delete(
                      'proformas',
                      where: 'uuid = ?',
                      whereArgs: [uuid],
                    );
                    debugPrint("PAGOS-uncheck: Eliminada proforma asociada con uuid $uuid");
                  }
                } catch (e) {
                  debugPrint("Error al eliminar proforma asociada en desmarcado: $e");
                }
              }

              _refreshDocuments();
              _syncEverything(silent: true);

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
          );
        },
      ),
    );
  }

  Future<String?> _seleccionarImagenComprobante() async {
    final picker = ImagePicker();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white,
        title: const Text("Seleccionar origen del comprobante"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.camera_alt, color: Color(0xFF00ADEF)),
            label: const Text("Cámara", style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(context, ImageSource.camera),
          ),
          TextButton.icon(
            icon: const Icon(Icons.photo_library, color: Color(0xFF00ADEF)),
            label: const Text("Galería", style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    );

    if (source == null) return null;

    try {
      final pickedFile = await picker.pickImage(source: source, imageQuality: 80);
      if (pickedFile == null) return null;

      // Comprimir inteligentemente y subir a la nube Hostinger
      return await TenantHelper.processAndUploadReceipt(pickedFile);
    } catch (e) {
      debugPrint("Error picking/uploading receipt image: $e");
      return null;
    }
  }

  void _mostrarOpciones(Map<String, dynamic> doc, int displayId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCotizacion = doc['tipo'] == 'cotizacion';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black26, borderRadius: BorderRadius.circular(10)),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF00ADEF)),
              title: Text(isCotizacion ? "Editar Cotización" : "Editar Nota de Entrega", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _editarDocumento(doc, displayId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.blueAccent),
              title: Text(isCotizacion ? "Duplicar Cotización" : "Duplicar Nota de Entrega", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _duplicarDocumento(doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.payment_outlined, color: Colors.green),
              title: Text("Gestionar Pagos", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _mostrarDialogoPagos(doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert_rounded, color: Colors.orangeAccent),
              title: Text("Mover posición (Re-numerar)", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _mostrarDialogoMover(doc);
              },
            ),
            if (isCotizacion)
              ListTile(
                leading: const Icon(Icons.local_shipping, color: Colors.greenAccent),
                title: Text("Llevar a Nota de Entrega", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                onTap: () {
                  Navigator.pop(context);
                  _llevarANotaEntrega(doc);
                },
              ),
            if (!isCotizacion)
              ListTile(
                leading: const Icon(Icons.point_of_sale, color: Colors.amberAccent),
                title: Text("Llevar a Punto de Venta", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                onTap: () {
                  Navigator.pop(context);
                  _llevarAPuntoDeVenta(doc);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: Text("Eliminar permanentemente", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _confirmarEliminacion(doc);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoMover(Map<String, dynamic> doc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCotizacion = doc['tipo'] == 'cotizacion';
    final table = isCotizacion ? 'cotizaciones' : 'notas_entrega';
    final list = isCotizacion ? _cotizaciones : _notasEntrega;
    final n = list.length;
    
    // Encontrar su displayId actual.
    final entireIndex = isCotizacion
        ? _cotizaciones.indexWhere((c) => c['id'] == doc['id'])
        : _notasEntrega.indexWhere((n) => n['id'] == doc['id']);
    final currentDisplayId = entireIndex != -1 ? (n - entireIndex) : (doc['id'] as int? ?? 0);

    final textController = TextEditingController(text: currentDisplayId.toString());

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF161A22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.swap_vert_rounded, color: Colors.orangeAccent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Mover posición",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Cambia el orden del documento. Esto re-numerará consecutivamente los demás documentos.",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Posición actual: #$currentDisplayId",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF00ADEF),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: textController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: "Nueva posición (1 - $n)",
                labelStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.white30 : Colors.black26),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00ADEF)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              "CANCELAR",
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              final val = int.tryParse(textController.text);
              if (val == null || val < 1 || val > n) {
                return;
              }
              
              Navigator.pop(dialogContext);

              // Mostrar un loader
              bool operationFinished = false;
              BuildContext? progressDialogContext;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (progContext) {
                  progressDialogContext = progContext;
                  return const AlertDialog(
                    content: Row(
                      children: [
                        CircularProgressIndicator(color: Color(0xFF00ADEF)),
                        SizedBox(width: 20),
                        Text("Re-numerando..."),
                      ],
                    ),
                  );
                },
              );

              try {
                await DatabaseHelper.instance.compactAndMoveDocument(table, doc['id'] as int, val);
                
                operationFinished = true;
                if (progressDialogContext != null && Navigator.canPop(progressDialogContext!)) {
                  Navigator.pop(progressDialogContext!);
                }

                await _refreshDocuments();

                _syncEverything(silent: true);

              } catch (e) {
                operationFinished = true;
                if (progressDialogContext != null && Navigator.canPop(progressDialogContext!)) {
                  Navigator.pop(progressDialogContext!);
                }
              }
            },
            child: const Text("MOVER", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _mostrarOpcionesDeCreacion() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black26, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "CREAR NUEVO DOCUMENTO",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.calculate_rounded, size: 24),
              label: const Text("NUEVA COTIZACIÓN", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00ADEF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  '/cotizaciones/creacion',
                  arguments: {'tipoVenta': widget.tipoVenta},
                ).then((_) {
                  _refreshDocuments();
                  _syncEverything(silent: true);
                });
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.local_shipping_rounded, size: 24),
              label: const Text("NUEVA NOTA DE ENTREGA", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CrearNotaEntregaScreen(
                      displayId: _notasEntrega.length + 1,
                      tipoVenta: widget.tipoVenta,
                    ),
                  ),
                ).then((_) {
                  _refreshDocuments();
                  _syncEverything(silent: true);
                });
              },
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomFAB() {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/cotizaciones/creacion',
          arguments: {'tipoVenta': widget.tipoVenta},
        ).then((_) {
          _refreshDocuments();
          _syncEverything(silent: true);
        });
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).primaryColor,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).primaryColor.withOpacity(0.4),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Image.asset(
            'Iconos/pantalla 3/mas.png',
            width: 17,
            height: 17,
            color: Colors.white,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.add,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTabs(bool isDark) {
    if (widget.tipoVenta != 'punto_venta') {
      return const SizedBox.shrink();
    }
    final brandColor = Theme.of(context).primaryColor;
    final cardBg = isDark ? const Color(0xFF1E222B) : Colors.white;
    final isFilterActive = _sucursalFiltro != 'todas';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildFilterPill("Todos", 'todos', isDark),
          const SizedBox(width: 6),
          _buildFilterPill("Pagados", 'pagados', isDark),
          const SizedBox(width: 6),
          _buildFilterPill("Por cobrar", 'por_cobrar', isDark),
          const SizedBox(width: 6),
          // Botón de Filtro por Sucursal
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _mostrarModalFiltroSucursales(context, isDark),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isFilterActive ? brandColor : cardBg,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isFilterActive
                    ? [
                        BoxShadow(
                          color: brandColor.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Icon(
                Icons.tune_rounded,
                color: isFilterActive
                    ? (brandColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
                    : (isDark ? Colors.white70 : const Color(0xFF0F172A)),
                size: 19,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarModalFiltroSucursales(BuildContext context, bool isDark) {
    final brandColor = Theme.of(context).primaryColor;
    final available = _getAvailableSucursales();
    final cardBg = isDark ? const Color(0xFF1E222B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secTextColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: brandColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.store_mall_directory_rounded,
                          color: brandColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Filtrar por Sucursal",
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            Text(
                              "Selecciona para filtrar el historial",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: secTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_sucursalFiltro != 'todas')
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _sucursalFiltro = 'todas';
                              _filterDocuments();
                            });
                            Navigator.pop(ctx);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                          ),
                          child: Text(
                            "Limpiar",
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: brandColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Opción: Todas las sucursales
                  _buildSucursalOption(
                    title: "Todas las sucursales",
                    value: 'todas',
                    isDark: isDark,
                    brandColor: brandColor,
                    textColor: textColor,
                    secTextColor: secTextColor,
                    onTap: () {
                      setState(() {
                        _sucursalFiltro = 'todas';
                        _filterDocuments();
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Color(0xFFE2E8F0), height: 1),
                  const SizedBox(height: 8),

                  // Lista de Sucursales
                  ...available.map((suc) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: _buildSucursalOption(
                        title: suc.startsWith('#') ? "Sucursal $suc" : suc,
                        value: suc,
                        isDark: isDark,
                        brandColor: brandColor,
                        textColor: textColor,
                        secTextColor: secTextColor,
                        onTap: () {
                          setState(() {
                            _sucursalFiltro = suc;
                            _filterDocuments();
                          });
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSucursalOption({
    required String title,
    required String value,
    required bool isDark,
    required Color brandColor,
    required Color textColor,
    required Color secTextColor,
    required VoidCallback onTap,
  }) {
    final isSelected = _sucursalFiltro == value;
    final cardBg = isDark
        ? (isSelected ? brandColor.withOpacity(0.15) : const Color(0xFF262A34))
        : (isSelected ? brandColor.withOpacity(0.08) : const Color(0xFFF8FAFC));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? brandColor
                : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              value == 'todas' ? Icons.all_inclusive_rounded : Icons.store_outlined,
              color: isSelected ? brandColor : secTextColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? (isDark ? Colors.white : brandColor) : textColor,
                ),
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: brandColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(String title, String tabKey, bool isDark) {
    final bool isSelected = _activeTab == tabKey;
    final cardBg = isDark ? const Color(0xFF1E222B) : Colors.white;
    final unselectedText = isDark ? Colors.white38 : Colors.black.withOpacity(0.5);
    final brandColor = Theme.of(context).primaryColor;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          setState(() {
            _activeTab = tabKey;
            _filterDocuments();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? brandColor : cardBg,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: brandColor.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Text(
            title,
            style: GoogleFonts.poppins(
              color: isSelected ? Colors.white : unselectedText,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
      appBar: _isSearching
          ? AppBar(
              backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
              elevation: 0,
              leadingWidth: 56,
              leading: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: NovaledThickIcon(
                      assetPath: 'Iconos/pantalla 3/atras.png',
                      size: 24,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchController.clear();
                        _filterDocuments();
                      });
                    },
                  ),
                ),
              ),
              title: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 16),
                decoration: InputDecoration(
                  hintText: "Buscar por cliente...",
                  hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                  border: InputBorder.none,
                ),
                onChanged: (_) => _filterDocuments(),
              ),
              actions: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.clear, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                    onPressed: () {
                      _searchController.clear();
                      _filterDocuments();
                    },
                  ),
              ],
            )
          : AppBar(
              title: Text(
                widget.tipoVenta == 'punto_venta' ? 'Punto de venta' : 'Cotizaciones',
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w600,
                  fontSize: 19,
                ),
              ),
              centerTitle: true,
              backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
              elevation: 0,
              leadingWidth: 56,
              leading: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: NovaledThickIcon(
                      assetPath: 'Iconos/pantalla 3/atras.png',
                      size: 24,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              actions: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: NovaledThickIcon(
                        assetPath: 'Iconos/pantalla 3/buscador.png',
                        size: 24,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fallbackIcon: Icons.search_rounded,
                      ),
                      onPressed: () {
                        setState(() {
                          _isSearching = true;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () => _syncEverything(),
        child: Column(
          children: [
            _buildFilterTabs(isDark),
            // LISTADO DE COTIZACIONES
            Expanded(
              child: _cotizaciones.isEmpty && _isSyncing
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF5842F4)))
                  : _filteredDocuments.isEmpty
                      ? Stack(
                          children: [
                            ListView(),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.description_outlined,
                                    size: 80,
                                    color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    "No hay cotizaciones encontradas.",
                                    style: GoogleFonts.poppins(
                                      color: isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 0, bottom: 16),
                          itemCount: _filteredDocuments.length,
                          itemBuilder: (context, index) {
                            final doc = _filteredDocuments[index];
                            final displayId = _getDisplayId(doc);

                            return _SlidableCotizacionTile(
                              cot: doc,
                              displayId: displayId,
                              hasDeliveryNote: _tieneNotaEntrega(doc),
                              tipoVenta: widget.tipoVenta,
                              onTap: () => _editarDocumento(doc, displayId),
                              onLongPress: () => _mostrarOpciones(doc, displayId),
                              onDelete: () => _confirmarEliminacion(doc),
                              onDuplicate: () => _duplicarDocumento(doc),
                              onPayments: () => _generarCopiaProforma(doc),
                              onMove: () => _generarCopiaNotaEntrega(doc),
                              onAnular: () => _anularVenta(doc),
                              onIconTap: () => _verPDFCotizacion(doc, displayId),
                              onDeliveryNoteTap: () => _irANotaEntregaAsociada(doc),
                              onRefresh: () => _refreshDocuments(),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isSearching ? null : _buildCustomFAB(),
    );
  }
}

class _SlidableCotizacionTile extends StatefulWidget {
  final Map<String, dynamic> cot;
  final int displayId;
  final bool hasDeliveryNote;
  final String tipoVenta;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onPayments;
  final VoidCallback onMove;
  final VoidCallback onAnular;
  final VoidCallback onIconTap;
  final VoidCallback onDeliveryNoteTap;
  final VoidCallback onRefresh;

  const _SlidableCotizacionTile({
    required this.cot,
    required this.displayId,
    required this.hasDeliveryNote,
    this.tipoVenta = 'cotizacion',
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onDuplicate,
    required this.onPayments,
    required this.onMove,
    required this.onAnular,
    required this.onIconTap,
    required this.onDeliveryNoteTap,
    required this.onRefresh,
  });

  @override
  State<_SlidableCotizacionTile> createState() => _SlidableCotizacionTileState();
}

class StatusTagInfo {
  final String label;
  final Color color;
  StatusTagInfo(this.label, this.color);
}

class _SlidableCotizacionTileState extends State<_SlidableCotizacionTile> {
  double _offset = 0;
  String? _actionOverlayText;
  int _localTapCount = 0;
  Timer? _localTapTimer;

  @override
  void dispose() {
    _localTapTimer?.cancel();
    super.dispose();
  }

  StatusTagInfo _getStatusTagInfo(Map<String, dynamic> doc) {
    final estado = (doc['estado'] ?? '').toString().toLowerCase();
    final estadoPago = (doc['estado_pago'] ?? '').toString().toLowerCase();
    final comprobado = doc['comprobado'] as int? ?? 0;

    if (estado == 'anulada' || estadoPago == 'anulada' || estado == 'anulado' || estadoPago == 'anulado') {
      return StatusTagInfo('Anulada', const Color(0xFFEF4444)); // Rojo
    }
    if (estadoPago == 'pagado' || estadoPago == 'cobrado' || comprobado == 1 || estado == 'aprobada') {
      return StatusTagInfo('Pagado', const Color(0xFF10B981)); // Verde
    }
    return StatusTagInfo('Por Cobrar', const Color(0xFF00ADEF)); // Celeste
  }

  void _triggerActionEffect(String text, VoidCallback onComplete) async {
    setState(() {
      _offset = 0;
      _actionOverlayText = text;
    });
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) {
      setState(() {
        _actionOverlayText = null;
      });
    }
    onComplete();
  }

  void _handleTap() {
    _localTapCount++;
    _localTapTimer?.cancel();
    
    _localTapTimer = Timer(const Duration(milliseconds: 300), () async {
      if (_localTapCount == 1) {
        widget.onTap();
      } else if (_localTapCount == 2) {
        await _marcarComprobadoFast(1);
      } else if (_localTapCount >= 3) {
        await _marcarComprobadoFast(0);
      }
      _localTapCount = 0;
    });
  }

  Future<void> _marcarComprobadoFast(int comprobado) async {
    if (!Session().isAdmin) {
      return;
    }

    final isCotizacion = widget.cot['tipo'] == 'cotizacion';
    final table = isCotizacion ? 'cotizaciones' : 'notas_entrega';
    final id = widget.cot['id'] as int;

    setState(() {
      _actionOverlayText = comprobado == 1 ? "Aprobado" : "Desmarcado";
    });

    await DatabaseHelper.instance.updateDocumentPago(
      table: table,
      id: id,
      saldoCancelado: (widget.cot['saldo_cancelado'] as num?)?.toDouble() ?? 0.0,
      comprobanteImg: widget.cot['comprobante_img']?.toString(),
      comprobado: comprobado,
    );

    final db = await DatabaseHelper.instance.database;

    if (isCotizacion) {
      final String finalEstado = (comprobado == 1) ? 'aprobada' : 'pendiente';
      await db.update(
        'cotizaciones',
        {
          'comprobado': comprobado,
          'estado': finalEstado,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      
      if (comprobado == 1) {
        try {
          final List<Map<String, dynamic>> cotList = await db.query('cotizaciones', where: 'id = ?', whereArgs: [id]);
          if (cotList.isNotEmpty) {
            final updatedDoc = cotList.first;
            
            String uuid = updatedDoc['uuid']?.toString() ?? '';
            if (uuid.isEmpty) {
              uuid = DatabaseHelper.instance.generateUUID();
              await db.update(
                'cotizaciones',
                {'uuid': uuid},
                where: 'id = ?',
                whereArgs: [id],
              );
            }

            final List<Map<String, dynamic>> existingNote = await db.query(
              'notas_entrega',
              where: 'uuid = ?',
              whereArgs: [uuid],
            );
            if (existingNote.isEmpty) {
              final Map<String, dynamic> nuevaNota = Map.from(updatedDoc);
              nuevaNota.remove('id');
              nuevaNota.remove('tipo');
              nuevaNota.remove('estado');
              nuevaNota['uuid'] = uuid;
              nuevaNota['fecha'] = DateTime.now().toString().split('.')[0];
              nuevaNota['terminos'] =
                  "• Recibí conforme los productos detallados.\n• No se aceptan devoluciones después de 48 hrs.\n• La mercadería viaja por cuenta y riesgo del cliente.";
              nuevaNota['tipo_venta'] = updatedDoc['tipo_venta'] ?? 'punto_venta';
              await db.insert('notas_entrega', nuevaNota);
            }

            final List<Map<String, dynamic>> existingProforma = await db.query(
              'proformas',
              where: 'uuid = ?',
              whereArgs: [uuid],
            );
            if (existingProforma.isEmpty) {
              final Map<String, dynamic> proforma = Map<String, dynamic>.from(updatedDoc);
              proforma.remove('id');
              proforma.remove('estado');
              proforma['uuid'] = uuid;
              proforma['tipo_venta'] = 'venta_institucional';
              proforma['estado_pago'] = 'por_cobrar';
              proforma['metodo_pago'] = updatedDoc['metodo_pago'] ?? 'Transferencia';
              
              final proformaId = await db.insert('proformas', proforma);
              
              final allProformas = await DatabaseHelper.instance.queryAllProformas();
              final matchProforma = allProformas.firstWhere((p) => p['id'] == proformaId);
              DriveService().syncItemToDrive('proformas', Map<String, dynamic>.from(matchProforma)).then((newFolderId) async {
                if (newFolderId != null && newFolderId != matchProforma['folderId']) {
                  final updated = Map<String, dynamic>.from(matchProforma)..['folderId'] = newFolderId;
                  await DatabaseHelper.instance.updateProforma(updated);
                }
                SyncService.instance.syncEverything().catchError((e) {
                  debugPrint("Silent Hostinger sync error (proformas): $e");
                });
              });
            }
          }
        } catch (e) {
          debugPrint("Error al realizar copia automática desde tile: $e");
        }
      } else {
        // comprobado == 0
        String uuid = '';
        try {
          final List<Map<String, dynamic>> list = await db.query(
            'cotizaciones',
            columns: ['uuid'],
            where: 'id = ?',
            whereArgs: [id],
          );
          if (list.isNotEmpty) {
            uuid = list.first['uuid']?.toString() ?? '';
          }
        } catch (e) {
          debugPrint("Error al consultar uuid en _marcarComprobadoFast: $e");
        }

        if (uuid.isNotEmpty) {
          try {
            await db.delete(
              'proformas',
              where: 'uuid = ?',
              whereArgs: [uuid],
            );
            debugPrint("Fast-uncheck: Eliminada proforma asociada con uuid $uuid");
          } catch (e) {
            debugPrint("Error al eliminar proforma en fast-uncheck: $e");
          }
        }
      }
    } else {
      // isCotizacion is false (nota_entrega tile)
      // DatabaseHelper.instance.updateDocumentPago already updated the status above.
    }

    await Future.delayed(const Duration(milliseconds: 1200));

    if (mounted) {
      setState(() {
        _actionOverlayText = null;
      });
    }

    widget.onRefresh();
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final d = raw.split(' ')[0];
    final p = d.split('-');
    if (p.length == 3) {
      return "${p[2]}-${p[1]}-${p[0]}";
    }
    return d;
  }

  String _formatPrice(dynamic val) {
    final double t = (val as num?)?.toDouble() ?? 0.0;
    if (t == t.toInt()) {
      final String s = t.toInt().toString();
      return s.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => "${m[1]}.");
    } else {
      final parts = t.toStringAsFixed(2).split('.');
      final String intPart = parts[0].replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => "${m[1]}.");
      return "$intPart.${parts[1]}";
    }
  }

  Widget _buildTileContent(bool isDark) {
    final String rawCliente = widget.cot['clienteNombre']?.toString().trim() ?? '';
    final String clienteNombre = rawCliente.isNotEmpty ? rawCliente : "Sin Cliente";
    final String totalMonto = "Bs. ${_formatPrice(widget.cot['total'])}";
    final String fechaStr = _formatDate(widget.cot['fecha']?.toString());
    final String rawVendedor = widget.cot['vendedor']?.toString().trim() ?? '';
    final isNovaled = TenantHelper.isNovaled(Session().userName);
    final String vendedorStr = rawVendedor.isNotEmpty ? rawVendedor : (isNovaled ? "JOEL" : (Session().userName ?? ""));

    final String rawSucursal = widget.cot['sucursal']?.toString().trim() ?? '';
    final String sucursalStr = rawSucursal.isNotEmpty && rawSucursal != 'null'
        ? rawSucursal
        : (isNovaled ? "#818" : "");

    final badgeBg = isDark ? const Color(0xFF262A34) : const Color(0xFFF3F6FB);
    final badgeBorder = isDark ? Colors.white12 : const Color(0xFFE2E8F0);
    final badgeText = isDark ? Colors.white70 : Colors.black.withOpacity(0.5);

    final darkBadgeBg = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final darkBadgeText = isDark ? Colors.white : Colors.black.withOpacity(0.5);

    Widget buildBadge({required Widget icon, required String label, bool isDarkBadge = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: isDarkBadge ? darkBadgeBg : badgeBg,
          borderRadius: BorderRadius.circular(999),
          border: isDarkBadge ? null : Border.all(color: badgeBorder, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            if (icon is! SizedBox) const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDarkBadge ? darkBadgeText : badgeText,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          clienteNombre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. #ID Badge
                    buildBadge(
                      icon: const SizedBox.shrink(),
                      label: "#${widget.displayId}",
                      isDarkBadge: true,
                    ),
                    const SizedBox(width: 6),
                    // 2. Money Badge
                    buildBadge(
                      icon: Icon(Icons.attach_money_rounded, size: 13, color: isDark ? Colors.white54 : Colors.black.withOpacity(0.5)),
                      label: totalMonto,
                    ),
                    const SizedBox(width: 6),
                    // 3. Date Badge
                    buildBadge(
                      icon: Icon(Icons.calendar_today_outlined, size: 12, color: isDark ? Colors.white54 : Colors.black.withOpacity(0.5)),
                      label: fechaStr,
                    ),
                    const SizedBox(width: 6),
                    // 4. Seller Badge
                    buildBadge(
                      icon: Icon(Icons.person_outline_rounded, size: 13, color: isDark ? Colors.white54 : Colors.black.withOpacity(0.5)),
                      label: vendedorStr,
                    ),
                    if (widget.tipoVenta == 'punto_venta') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: _getStatusTagInfo(widget.cot).color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _getStatusTagInfo(widget.cot).color.withOpacity(0.3), width: 0.8),
                        ),
                        child: Text(
                          _getStatusTagInfo(widget.cot).label,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _getStatusTagInfo(widget.cot).color,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: isDark ? Colors.white38 : Colors.black.withOpacity(0.5),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPuntoVenta = widget.tipoVenta == 'punto_venta';
    final double maxOffset = isPuntoVenta ? -230.0 : -288.0;

    return Container(
      margin: EdgeInsets.zero,
      child: Stack(
        children: [
          if (_offset != 0)
            Positioned.fill(
              child: Builder(
                builder: (context) {
                  final Color brandColor = Theme.of(context).primaryColor;
                  final hsl = HSLColor.fromColor(brandColor);
                  final gradLight = hsl.withLightness((hsl.lightness + 0.22).clamp(0.0, 0.95)).toColor();
                  final gradMidLight = hsl.withLightness((hsl.lightness + 0.10).clamp(0.0, 0.95)).toColor();
                  final gradMain = brandColor;
                  final gradDark = hsl.withLightness((hsl.lightness - 0.14).clamp(0.0, 0.95)).toColor();

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          gradLight,
                          gradMidLight,
                          gradMain,
                          gradDark,
                        ],
                      ),
                      borderRadius: const BorderRadius.all(Radius.circular(22)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            color: Colors.transparent,
                          ),
                        ),
                        if (isPuntoVenta) ...[
                          // BOTÓN 1: ANULAR VENTA ($)
                          InkWell(
                            onTap: () {
                              _triggerActionEffect("Venta anulada", widget.onAnular);
                            },
                            child: Container(
                              width: 86,
                              alignment: Alignment.center,
                              color: Colors.transparent,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.attach_money_rounded, color: Colors.white, size: 24),
                              const SizedBox(height: 4),
                              Text(
                                "Anular venta",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // BOTÓN 2: BORRAR (Basurero)
                      InkWell(
                        onTap: () {
                          _triggerActionEffect("Borrado", widget.onDelete);
                        },
                        child: Container(
                          width: 72,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'Iconos/pantalla 3/Recurso 29@30x-8.png',
                                width: 22,
                                height: 22,
                                color: Colors.white,
                                errorBuilder: (_, __, ___) => const Icon(Icons.delete_outline, color: Colors.white, size: 22),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Borrar",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // BOTÓN 3: COPIAR (Documentos)
                      InkWell(
                        onTap: () {
                          _triggerActionEffect("Copiado", widget.onDuplicate);
                        },
                        child: Container(
                          width: 72,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'Iconos/pantalla 3/Recurso 32@30x-8.png',
                                width: 22,
                                height: 22,
                                color: Colors.white,
                                errorBuilder: (_, __, ___) => const Icon(Icons.copy_outlined, color: Colors.white, size: 22),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Copiar",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // BOTONES PARA PESTAÑA COTIZACIONES STANDARD
                      InkWell(
                        onTap: () {
                          _triggerActionEffect("Se generó la proforma", widget.onPayments);
                        },
                        child: Container(
                          width: 84,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'Iconos/pantalla 3/Recurso 6@30x-8.png',
                                width: 24,
                                height: 24,
                                color: Colors.white,
                                errorBuilder: (_, __, ___) => const Icon(Icons.attach_money_rounded, color: Colors.white, size: 24),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Generar venta",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          _triggerActionEffect("Se generó la nota de entrega", widget.onMove);
                        },
                        child: Container(
                          width: 70,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'Iconos/pantalla 3/Recurso 30@30x-8.png',
                                width: 25,
                                height: 25,
                                color: Colors.white,
                                errorBuilder: (_, __, ___) => const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 24),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "N. entrega",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          _triggerActionEffect("Borrado", widget.onDelete);
                        },
                        child: Container(
                          width: 67,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'Iconos/pantalla 3/Recurso 29@30x-8.png',
                                width: 24,
                                height: 24,
                                color: Colors.white,
                                errorBuilder: (_, __, ___) => const Icon(Icons.delete_outline, color: Colors.white, size: 24),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Borrar",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          _triggerActionEffect("Copiado", widget.onDuplicate);
                        },
                        child: Container(
                          width: 67,
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'Iconos/pantalla 3/Recurso 32@30x-8.png',
                                width: 24,
                                height: 24,
                                color: Colors.white,
                                errorBuilder: (_, __, ___) => const Icon(Icons.copy_outlined, color: Colors.white, size: 24),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Copiar",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ],
                    ],
                  ),
                );
                },
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _actionOverlayText != null
                    ? Container(
                        key: const ValueKey("overlay"),
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5842F4),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF5842F4).withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: 0.0,
                                child: _buildTileContent(isDark),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _actionOverlayText!,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : InkWell(
                        key: const ValueKey("normal_card"),
                        onTap: () {
                          if (_offset != 0) {
                            setState(() => _offset = 0);
                          } else {
                            widget.onTap();
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF262822) : Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02),
                              width: 1.0,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
                            child: _buildTileContent(isDark),
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
}

class BlinkingDot extends StatefulWidget {
  final Color color;
  final bool shouldBlink;

  const BlinkingDot({super.key, required this.color, required this.shouldBlink});

  @override
  State<BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<BlinkingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animation = Tween<double>(begin: 1.0, end: 0.15).animate(_controller);
    if (widget.shouldBlink) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(BlinkingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldBlink != oldWidget.shouldBlink) {
      if (widget.shouldBlink) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.shouldBlink ? _animation : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
