import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database_helper.dart';
import 'dart:convert';
import '../services/sync_service.dart';
import 'package:printing/printing.dart';
import '../services/pdf_service.dart';
import '../models/item_cotizacion.dart';
import '../widgets/zoomable_pdf_preview.dart';
import '../../drive_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p_path;
import '../widgets/gestionar_pagos_page.dart';
import '../tenant_helper.dart';
import 'crear_cotizacion_screen.dart';

class VentaInstitucionalScreen extends StatefulWidget {
  final String tipoVenta;
  const VentaInstitucionalScreen({super.key, this.tipoVenta = 'venta_institucional'});

  @override
  State<VentaInstitucionalScreen> createState() => _VentaInstitucionalScreenState();
}

class _VentaInstitucionalScreenState extends State<VentaInstitucionalScreen> {
  List<Map<String, dynamic>> _proformas = [];
  List<Map<String, dynamic>> _filteredProformas = [];
  
  final TextEditingController _searchController = TextEditingController();
  String _activeTab = 'por_cobrar'; // 'por_cobrar', 'cobrado'
  String _selectedMetodoPago = 'Todos'; // 'Todos', 'Efectivo', 'Transferencia Bancaria', 'Cheque'
  bool _isSyncing = false;
  Timer? _syncTimer;
  final DriveService _drive = DriveService();

  @override
  void initState() {
    super.initState();
    _refreshProformas().then((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _syncEverything(silent: true);
          }
        });
      }
    });
    // Silent background auto sync every 10 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_isSyncing) {
        _syncEverything(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _sortProformas(List<Map<String, dynamic>> list) {
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
      return idB.compareTo(idA);
    });
    return mutable;
  }

  Future<void> _refreshProformas() async {
    final proformasData = await DatabaseHelper.instance.queryAllProformas(tipoVenta: widget.tipoVenta);
    final sortedProformas = _sortProformas(proformasData);

    if (mounted) {
      setState(() {
        _proformas = sortedProformas;
      });
      _filterProformas();
    }
  }

  void _filterProformas() {
    List<Map<String, dynamic>> baseList = _proformas;

    // Filter by tab/status
    baseList = baseList.where((p) => p['estado_pago'] == _activeTab).toList();

    // Filter by payment method
    if (_selectedMetodoPago != 'Todos') {
      baseList = baseList.where((p) => _matchMetodoPago(p['metodo_pago'], _selectedMetodoPago)).toList();
    }

    setState(() {
      _filteredProformas = baseList;
    });
  }

  Future<void> _syncEverything({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _isSyncing = true);

    try {
      final success = await SyncService.instance.syncTable('proformas').timeout(const Duration(seconds: 30));
      await _refreshProformas();
      if (!silent && mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Sincronización de Proformas exitosa"), backgroundColor: Colors.green),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOffline ? cleanMsg : "Error de Sincronización: $cleanMsg"),
            backgroundColor: isOffline ? Colors.orange[800] : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _compartirDocumento({
    required BuildContext context,
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
                      
                      final file = File('${directory.path}/Proforma_PR-$formattedId.pdf');
                      await file.writeAsBytes(bytes);
                      
                      final String msg = "Hola. Le envío la Proforma #PR-$formattedId para $clienteNombre por un total de ${total.toStringAsFixed(2)} Bs. El PDF ha sido guardado en la carpeta de Descargas de su dispositivo.";
                      
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
                      await Printing.sharePdf(bytes: bytes, filename: 'Proforma_PR-$formattedId.pdf');
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

  void _confirmarEliminacion(Map<String, dynamic> proforma) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final id = proforma['id'] as int;
    final cliente = proforma['clienteNombre']?.toString().toUpperCase() ?? 'CLIENTE';

    showDialog(
      context: context,
      builder: (confirmDialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF161A22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "¿Eliminar Nota de Venta?",
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
              "¿Estás seguro de que deseas eliminar permanentemente esta nota de venta?",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2833) : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.black12,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Documento: Nota de Venta #${id.toString().padLeft(5, '0')}",
                    style: TextStyle(
                      color: const Color(0xFFEFA820),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Cliente: $cliente",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (proforma['total'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      "Monto: ${(proforma['total'] as num).toStringAsFixed(2)} Bs",
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmDialogContext),
            child: Text(
              "CANCELAR",
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              Navigator.pop(confirmDialogContext);
              
              bool operationFinished = false;
              BuildContext? progressDialogContext;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogCtx) {
                  progressDialogContext = dialogCtx;
                  if (operationFinished) {
                    Future.microtask(() {
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    });
                  }
                  return PopScope(
                    canPop: false,
                    child: AlertDialog(
                      backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      content: Row(
                        children: [
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEFA820)),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Text(
                              "Eliminando proforma...",
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );

              // 1. Delete in Drive
              try {
                if (proforma['folderId'] != null && proforma['folderId'].toString().isNotEmpty) {
                  await _drive.deleteFile(proforma['folderId'].toString()).timeout(const Duration(seconds: 10));
                }
              } catch (e) {
                debugPrint("Error al borrar proforma en Drive: $e");
              }

              // 2. Delete in local DB
              try {
                await DatabaseHelper.instance.deleteProforma(id);
              } catch (e) {
                debugPrint("Error al borrar proforma local: $e");
              }

              operationFinished = true;
              if (progressDialogContext != null && progressDialogContext!.mounted) {
                try {
                  Navigator.pop(progressDialogContext!);
                } catch (_) {}
              }

              if (mounted) {
                _refreshProformas();
                _syncEverything(silent: true);
              }
            },
            child: const Text("ELIMINAR", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _verPDFProforma(Map<String, dynamic> proforma, int displayId) async {
    if (!mounted) return;

    bool dialogColor = true;
    final List<dynamic> itemsList = jsonDecode(proforma['itemsJson'] ?? '[]');
    final List<ItemCotizacion> items = itemsList.map((itemMap) => ItemCotizacion.fromMap(itemMap)).toList();
    final double subtotalOriginal = items.fold(0.0, (sum, item) => sum + item.totalOriginal);
    final double ahorroItems = items.fold(0.0, (sum, item) => sum + item.ahorro);
    
    final String clienteNombre = proforma['clienteNombre'] ?? "";
    final double total = (proforma['total'] as num?)?.toDouble() ?? 0.0;
    final double descuentoGlobal = (proforma['descuento'] as num?)?.toDouble() ?? 0.0;
    final String notas = proforma['notas'] ?? proforma['notes'] ?? "";
    final String terminos = proforma['terminos'] ?? "";
    final int docId = displayId;
    final bool incluyeFirmaEmpresa = (proforma['incluyeFirmaEmpresa'] ?? 0) == 1;
    final bool incluyeFirmaCliente = (proforma['incluyeFirmaCliente'] ?? 0) == 1;
    final bool mostrarTerminos = (proforma['mostrarTerminos'] ?? 1) == 1;
    final bool mostrarAhorro = false;
    final String fecha = proforma['fecha'] ?? "";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final String formattedId = docId.toString().padLeft(5, '0');
          String estadoPago = proforma['estado_pago'] ?? 'por_cobrar';

          return Dialog.fullscreen(
            child: Scaffold(
              backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              appBar: AppBar(
                backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                elevation: 0,
                iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
                title: Row(
                  children: [
                    Text(
                      "Nota de Venta #NV-$formattedId",
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: estadoPago == 'cobrado'
                            ? Colors.green.withOpacity(0.15)
                            : Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        estadoPago == 'cobrado' ? "Cobrado" : "Por Cobrar",
                        style: TextStyle(
                          color: estadoPago == 'cobrado' ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black87, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  Row(
                    children: [
                      Text("Color", style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
                      Switch(
                        value: dialogColor,
                        activeColor: const Color(0xFFEFA820),
                        onChanged: (val) async {
                          dialogColor = val;
                          setDialogState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    child: ZoomablePdfPreview(
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
                          tituloDocumento: "NOTA DE VENTA",
                          isColor: dialogColor,
                          fecha: fecha,
                          sucursal: proforma['sucursal']?.toString() ?? '#818',
                        ),
                        allowPrinting: false,
                        previewPageMargin: EdgeInsets.zero,
                        padding: EdgeInsets.zero,
                        pdfPreviewPageDecoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [],
                        ),
                        scrollViewDecoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : Theme.of(context).scaffoldBackgroundColor,
                        ),
                        allowSharing: false,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        canDebug: false,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                                    foregroundColor: isDark ? Colors.white : Colors.black87,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  icon: const Icon(Icons.cloud_download_rounded, size: 20, color: Color(0xFFEFA820)),
                                  label: const Text("Descargar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  onPressed: () async {
                                    try {
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
                                        tituloDocumento: "NOTA DE VENTA",
                                        isColor: dialogColor,
                                        fecha: fecha,
                                        sucursal: proforma['sucursal']?.toString() ?? '#818',
                                      );

                                      Directory? directory;
                                      if (Platform.isAndroid) {
                                        directory = Directory('/storage/emulated/0/Download');
                                        if (!await directory.exists()) {
                                          directory = await getExternalStorageDirectory();
                                        }
                                      } else {
                                        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
                                      }

                                      if (directory == null) {
                                        throw Exception("No se pudo acceder al directorio de descargas");
                                      }

                                      final file = File('${directory.path}/Proforma_PR-$formattedId.pdf');
                                      await file.writeAsBytes(currentBytes);

                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text("PDF guardado en: ${directory.path.split('/').last}/Proforma_PR-$formattedId.pdf"),
                                            backgroundColor: const Color(0xFF00ADEF),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      debugPrint("Error al descargar PDF: $e");
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text("Error al guardar PDF: $e"),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                                    foregroundColor: isDark ? Colors.white : Colors.black87,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  icon: const Icon(Icons.send_rounded, size: 20, color: Color(0xFFEFA820)),
                                  label: const Text("Enviar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  onPressed: () async {
                                    _compartirDocumento(
                                      context: context,
                                      formattedId: formattedId,
                                      clienteNombre: clienteNombre,
                                      total: total,
                                      generateBytes: () async {
                                        return await PdfService.generateCotizacionBytes(
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
                                          tituloDocumento: "NOTA DE VENTA",
                                          isColor: dialogColor,
                                          fecha: fecha,
                                          sucursal: proforma['sucursal']?.toString() ?? '#818',
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (estadoPago == 'por_cobrar') ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.check_circle_outline_rounded),
                              label: const Text(
                                "Marcar como cobrado",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              onPressed: () async {
                                final pId = proforma['id'];
                                if (pId != null) {
                                  await DatabaseHelper.instance.updateProformaPago(pId, 'cobrado');
                                  setDialogState(() {
                                    estadoPago = 'cobrado';
                                    proforma['estado_pago'] = 'cobrado';
                                  });
                                  _refreshProformas(); // Refresh list on screen
                                  
                                  // Sync with Drive & Hostinger MySQL
                                  final all = await DatabaseHelper.instance.queryAllProformas();
                                  final match = all.firstWhere((p) => p['id'] == pId);
                                  _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(match)).then((newFolderId) async {
                                    if (newFolderId != null && newFolderId != match['folderId']) {
                                      final updated = Map<String, dynamic>.from(match)..['folderId'] = newFolderId;
                                      await DatabaseHelper.instance.updateProforma(updated);
                                    }
                                    SyncService.instance.syncEverything().catchError((e) {
                                      debugPrint("Silent Hostinger sync error (proformas): $e");
                                    });
                                  });
                                  
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Nota de Venta marcada como cobrada correctamente"),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _seleccionarMetodoPagoDialog(Map<String, dynamic> proforma) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Mapear método guardado si es antiguo
    String currentMethod = proforma['metodo_pago'] ?? 'Transferencia';
    if (currentMethod == 'Transferencia Bancaria') {
      currentMethod = 'Transferencia';
    } else if (currentMethod == 'Tarjeta de Crédito/Débito' || currentMethod == 'Otros') {
      currentMethod = 'Tarjeta';
    } else if (currentMethod == 'Cheque') {
      currentMethod = 'Transferencia';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Método de Pago",
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['QR', 'Transferencia', 'Efectivo', 'Tarjeta'].map((method) {
            final isSelected = currentMethod == method;
            return ListTile(
              title: Text(
                method,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: isSelected ? const Icon(Icons.check, color: Color(0xFFEFA820)) : null,
              onTap: () async {
                Navigator.pop(ctx);
                final id = proforma['id'] as int;
                await DatabaseHelper.instance.updateProformaPago(id, proforma['estado_pago'] ?? 'por_cobrar', metodoPago: method);
                
                // Trigger Drive & hostinger sync
                final all = await DatabaseHelper.instance.queryAllProformas();
                final match = all.firstWhere((p) => p['id'] == id);
                _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(match)).then((newFolderId) async {
                  if (newFolderId != null && newFolderId != match['folderId']) {
                    final updated = Map<String, dynamic>.from(match)..['folderId'] = newFolderId;
                    await DatabaseHelper.instance.updateProforma(updated);
                  }
                  SyncService.instance.syncEverything().catchError((e) {
                    debugPrint("Silent Hostinger sync error (proformas): $e");
                  });
                });

                _refreshProformas();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  bool _matchMetodoPago(String? dbValue, String selected) {
    if (selected == 'Todos') return true;
    if (dbValue == null) return false;
    final dbValLower = dbValue.toLowerCase();
    final selLower = selected.toLowerCase();
    
    if (selLower == 'transferencia') {
      return dbValLower.contains('transferencia');
    }
    if (selLower == 'tarjeta') {
      return dbValLower.contains('tarjeta');
    }
    return dbValLower == selLower;
  }

  Future<void> _aprobarProforma(Map<String, dynamic> proforma) async {
    final id = proforma['id'] as int;
    String uuid = proforma['uuid']?.toString() ?? '';

    final db = await DatabaseHelper.instance.database;

    // Si no tiene uuid, generar uno y guardarlo en la proforma
    if (uuid.isEmpty) {
      uuid = DatabaseHelper.instance.generateUUID();
      await db.update(
        'proformas',
        {'uuid': uuid},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    // 1. Actualizar comprobado a 1 en la base de datos local (tabla proformas)
    await DatabaseHelper.instance.updateProformaComprobado(id, 1);

    // 2. Verificar si ya existe una copia en la tabla cotizaciones con el mismo uuid
    final List<Map<String, dynamic>> existing = await db.query(
      'cotizaciones',
      where: 'uuid = ?',
      whereArgs: [uuid],
    );

    int? newCotizacionId;
    if (existing.isEmpty) {
      // 3. Si no existe, insertar copia con tipo_venta = 'punto_venta' y estado = 'aprobada'
      final Map<String, dynamic> copy = Map<String, dynamic>.from(proforma);
      copy.remove('id');
      copy['uuid'] = uuid;
      copy['tipo_venta'] = 'punto_venta';
      copy['estado'] = 'aprobada';
      copy['comprobado'] = 1;
      newCotizacionId = await db.insert('cotizaciones', copy);
      debugPrint("Copia de proforma aprobada insertada en cotizaciones. ID: $newCotizacionId");
    } else {
      // Si ya existe, actualizamos su estado y comprobado a aprobada/1
      await db.update(
        'cotizaciones',
        {
          'estado': 'aprobada',
          'comprobado': 1,
        },
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      debugPrint("Copia de proforma aprobada actualizada en cotizaciones.");
    }

    // 4. Actualizar interfaz local
    await _refreshProformas();

    // 5. Sincronizar en segundo plano ambos documentos a Google Drive y Hostinger MySQL
    try {
      final allProformas = await DatabaseHelper.instance.queryAllProformas();
      final matchProforma = allProformas.firstWhere((p) => p['id'] == id);
      _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(matchProforma)).then((newFolderId) async {
        if (newFolderId != null && newFolderId != matchProforma['folderId']) {
          final updated = Map<String, dynamic>.from(matchProforma)..['folderId'] = newFolderId;
          await DatabaseHelper.instance.updateProforma(updated);
        }
        SyncService.instance.syncEverything().catchError((e) {
          debugPrint("Silent Hostinger sync error (proformas): $e");
        });
      });
    } catch (e) {
      debugPrint("Error al iniciar sync de proforma aprobada: $e");
    }

    if (newCotizacionId != null) {
      try {
        final allCotizaciones = await DatabaseHelper.instance.queryAllCotizaciones();
        final matchCotizacion = allCotizaciones.firstWhere((c) => c['id'] == newCotizacionId);
        _drive.syncItemToDrive('cotizaciones', Map<String, dynamic>.from(matchCotizacion)).then((newFolderId) async {
          if (newFolderId != null && newFolderId != matchCotizacion['folderId']) {
            final updated = Map<String, dynamic>.from(matchCotizacion)..['folderId'] = newFolderId;
            await DatabaseHelper.instance.updateCotizacion(updated);
          }
          SyncService.instance.syncEverything().catchError((e) {
            debugPrint("Silent Hostinger sync error (cotizaciones): $e");
          });
        });
      } catch (e) {
        debugPrint("Error al iniciar sync de cotización copiada: $e");
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Nota de Venta aprobada. Copia enviada a Punto de Venta."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _desaprobarProforma(Map<String, dynamic> proforma) async {
    final id = proforma['id'] as int;
    final uuid = proforma['uuid']?.toString() ?? '';
    final db = await DatabaseHelper.instance.database;
    await DatabaseHelper.instance.updateProformaComprobado(id, 0);
    if (uuid.isNotEmpty) {
      await db.delete('cotizaciones', where: 'uuid = ?', whereArgs: [uuid]);
    }
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

  void _mostrarDialogoPagos(Map<String, dynamic> doc) {
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
              
              final db = await DatabaseHelper.instance.database;
              
              // 1. Update the proforma itself
              await db.update(
                'proformas',
                {
                  'saldo_cancelado': finalSaldoCancelado,
                  'comprobante_img': currentComprobanteImg,
                  'comprobado': currentComprobado,
                  'metodo_pago': currentMetodoPago,
                  'estado_pago': finalEstadoPago,
                },
                where: 'id = ?',
                whereArgs: [id],
              );
              
              // 2. Synchronize with the cotización in the database if it has a matching uuid
              final String uuid = doc['uuid']?.toString() ?? '';
              if (uuid.isNotEmpty) {
                try {
                  final List<Map<String, dynamic>> matchingCot = await db.query(
                    'cotizaciones',
                    where: 'uuid = ?',
                    whereArgs: [uuid],
                  );
                  if (matchingCot.isNotEmpty) {
                    final cotId = matchingCot.first['id'];
                    final finalEstado = (currentComprobado == 1) ? 'aprobada' : 'pendiente';
                    await db.update(
                      'cotizaciones',
                      {
                        'saldo_cancelado': finalSaldoCancelado,
                        'comprobante_img': currentComprobanteImg,
                        'comprobado': currentComprobado,
                        'metodo_pago': currentMetodoPago,
                        'estado_pago': finalEstadoPago,
                        'estado': finalEstado,
                      },
                      where: 'id = ?',
                      whereArgs: [cotId],
                    );
                    debugPrint("PAGOS-proforma-sync: Sincronizados pagos a cotización con id $cotId");
                  }
                } catch (e) {
                  debugPrint("Error al sincronizar pagos de proforma a cotización: $e");
                }
              }

              // 3. Refresh list on screen
              _refreshProformas();

              // 4. Sync Drive & Hostinger MySQL
              final allProformas = await DatabaseHelper.instance.queryAllProformas();
              final matchProforma = allProformas.firstWhere((p) => p['id'] == id);
              _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(matchProforma)).then((newFolderId) async {
                if (newFolderId != null && newFolderId != matchProforma['folderId']) {
                  final updated = Map<String, dynamic>.from(matchProforma)..['folderId'] = newFolderId;
                  await DatabaseHelper.instance.updateProforma(updated);
                }
                SyncService.instance.syncEverything().catchError((e) {
                  debugPrint("Silent Hostinger sync error (proformas): $e");
                });
              });

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Pagos guardados con éxito"),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }

  void _editarProforma(Map<String, dynamic> proforma, int displayId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CrearCotizacionScreen(
          cotizacionExistente: proforma,
          displayId: displayId,
          tipoVenta: proforma['tipo_venta'] ?? 'venta_institucional',
          isDirectoPorCobrar: true,
        ),
      ),
    ).then((_) => _refreshProformas());
  }

  void _showOptionsBottomSheet(Map<String, dynamic> proforma, int displayId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final id = proforma['id'] as int;
    final cliente = proforma['clienteNombre'] ?? 'SIN CLIENTE';
    final estadoPago = proforma['estado_pago'] ?? 'por_cobrar';
    final String formattedId = displayId.toString().padLeft(5, '0');

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      "Proforma #$formattedId",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cliente,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (proforma['estado_pago'] == 'cobrado')
                            ? const Color(0xFF10B981).withOpacity(0.15)
                            : (proforma['comprobado'] == 1)
                                ? const Color(0xFFEF4444).withOpacity(0.15)
                                : const Color(0xFFEFA820).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        (proforma['estado_pago'] == 'cobrado')
                            ? "Cobrada"
                            : (proforma['comprobado'] == 1)
                                ? "Aprobada"
                                : "Pendiente",
                        style: TextStyle(
                          color: (proforma['estado_pago'] == 'cobrado')
                              ? const Color(0xFF10B981)
                              : (proforma['comprobado'] == 1)
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFFEFA820),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Color(0xFFEFA820)),
                title: const Text("Ver PDF / Compartir"),
                onTap: () {
                  Navigator.pop(context);
                  _verPDFProforma(proforma, displayId);
                },
              ),
              if (proforma['comprobado'] != 1)
                ListTile(
                  leading: const Icon(Icons.thumb_up_alt_outlined, color: Colors.red),
                  title: const Text("Aprobar Proforma", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  onTap: () async {
                    Navigator.pop(context);
                    await _aprobarProforma(proforma);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.payment, color: Colors.green),
                title: const Text("Gestionar Pagos"),
                onTap: () {
                  Navigator.pop(context);
                  _mostrarDialogoPagos(proforma);
                },
              ),
              if (estadoPago == 'por_cobrar')
                ListTile(
                  leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                  title: const Text("Marcar como Cobrada (Pagada)"),
                  onTap: () async {
                    Navigator.pop(context);
                    await DatabaseHelper.instance.updateProformaPago(id, 'cobrado');
                    _refreshProformas();
                    // Sync Drive & MySQL
                    final all = await DatabaseHelper.instance.queryAllProformas();
                    final match = all.firstWhere((p) => p['id'] == id);
                    _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(match)).then((newFolderId) async {
                      if (newFolderId != null && newFolderId != match['folderId']) {
                        final updated = Map<String, dynamic>.from(match)..['folderId'] = newFolderId;
                        await DatabaseHelper.instance.updateProforma(updated);
                      }
                      SyncService.instance.syncEverything().catchError((e) {
                        debugPrint("Silent Hostinger sync error (proformas): $e");
                      });
                    });
                  },
                ),
              if (estadoPago == 'cobrado')
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline_rounded, color: Colors.orange),
                  title: const Text("Desmarcar como Cobrada (Por cobrar)", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                  onTap: () async {
                    Navigator.pop(context);
                    await DatabaseHelper.instance.updateProformaPago(id, 'por_cobrar');
                    _refreshProformas();
                    // Sync Drive & MySQL
                    final all = await DatabaseHelper.instance.queryAllProformas();
                    final match = all.firstWhere((p) => p['id'] == id);
                    _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(match)).then((newFolderId) async {
                      if (newFolderId != null && newFolderId != match['folderId']) {
                        final updated = Map<String, dynamic>.from(match)..['folderId'] = newFolderId;
                        await DatabaseHelper.instance.updateProforma(updated);
                      }
                      SyncService.instance.syncEverything().catchError((e) {
                        debugPrint("Silent Hostinger sync error (proformas): $e");
                      });
                    });
                  },
                ),
              ListTile(
                leading: const Icon(Icons.payment, color: Colors.blue),
                title: const Text("Cambiar Método de Pago"),
                onTap: () {
                  Navigator.pop(context);
                  _seleccionarMetodoPagoDialog(proforma);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Eliminar Proforma"),
                onTap: () {
                  Navigator.pop(context);
                  _confirmarEliminacion(proforma);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryOrange = const Color(0xFFEFA820);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        title: Text(
          "Punto de Venta",
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CrearCotizacionScreen(
                    isDirectoPorCobrar: true,
                    tipoVenta: 'venta_institucional',
                  ),
                ),
              ).then((_) => _refreshProformas());
            },
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEFA820))),
                  )
                : const Icon(Icons.sync),
            onPressed: () => _syncEverything(silent: false),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Top tabs
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C323D) : Colors.grey[100],
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _activeTab = 'por_cobrar');
                      _filterProformas();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _activeTab == 'por_cobrar' ? const Color(0xFFEFA820) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "Por cobrar",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _activeTab == 'por_cobrar' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _activeTab = 'cobrado');
                      _filterProformas();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _activeTab == 'cobrado' ? const Color(0xFFEFA820) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "Pagadas",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _activeTab == 'cobrado' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Proformas List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _syncEverything(silent: false),
              color: primaryOrange,
              child: _filteredProformas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open_rounded, size: 64, color: isDark ? Colors.white24 : Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            "No se encontraron proformas",
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white38 : Colors.grey[500],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _filteredProformas.length,
                      itemBuilder: (context, index) {
                        final p = _filteredProformas[index];
                        final id = p['id'] as int;
                        final displayId = id;

                        return _SlidableProformaTile(
                          proforma: p,
                          displayId: displayId,
                          onTap: () => _editarProforma(p, displayId),
                          onLongPress: () => _showOptionsBottomSheet(p, displayId),
                          onRefresh: () => _refreshProformas(),
                          onVerPDF: () => _verPDFProforma(p, displayId),
                          onAprobarDesmarcar: () async {
                            final bool isComprobado = p['comprobado'] == 1;
                            if (isComprobado) {
                              await _desaprobarProforma(p);
                            } else {
                              await _aprobarProforma(p);
                            }
                            _refreshProformas();
                            // Sync Drive & MySQL
                            final all = await DatabaseHelper.instance.queryAllProformas();
                            final match = all.firstWhere((item) => item['id'] == id);
                            _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(match)).then((newFolderId) async {
                              if (newFolderId != null && newFolderId != match['folderId']) {
                                final updated = Map<String, dynamic>.from(match)..['folderId'] = newFolderId;
                                await DatabaseHelper.instance.updateProforma(updated);
                              }
                              SyncService.instance.syncEverything().catchError((e) {
                                debugPrint("Silent Hostinger sync error (proformas): $e");
                              });
                            });
                          },
                          onGestionarPagos: () => _mostrarDialogoPagos(p),
                          onMarcarDesmarcarCobrada: () async {
                            final isCobrado = p['estado_pago'] == 'cobrado';
                            final targetEstado = isCobrado ? 'por_cobrar' : 'cobrado';
                            await DatabaseHelper.instance.updateProformaPago(id, targetEstado);
                            _refreshProformas();
                            // Sync Drive & MySQL
                            final all = await DatabaseHelper.instance.queryAllProformas();
                            final match = all.firstWhere((item) => item['id'] == id);
                            _drive.syncItemToDrive('proformas', Map<String, dynamic>.from(match)).then((newFolderId) async {
                              if (newFolderId != null && newFolderId != match['folderId']) {
                                final updated = Map<String, dynamic>.from(match)..['folderId'] = newFolderId;
                                await DatabaseHelper.instance.updateProforma(updated);
                              }
                              SyncService.instance.syncEverything().catchError((e) {
                                debugPrint("Silent Hostinger sync error (proformas): $e");
                              });
                            });
                          },
                          onDelete: () => _confirmarEliminacion(p),
                        );
                      },
                    ),
            ),
          ),

          // 3. Bottom payment method filters
          _buildBottomFilters(isDark),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 64),
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CrearCotizacionScreen(
                  isDirectoPorCobrar: true,
                  tipoVenta: 'venta_institucional',
                ),
              ),
            ).then((_) => _refreshProformas());
          },
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFEFA820),
            ),
            child: const Icon(
              Icons.add,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomFilters(bool isDark) {
    final methods = ['Todos', 'QR', 'Transferencia', 'Efectivo', 'Tarjeta'];
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey[200]!,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: methods.map((method) {
            final isSelected = _selectedMetodoPago == method;
            return ChoiceChip(
              avatar: isSelected 
                  ? const Icon(Icons.check, size: 14, color: Colors.white) 
                  : null,
              label: Text(
                method,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              selected: isSelected,
              selectedColor: const Color(0xFFEFA820),
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected 
                      ? Colors.transparent 
                      : (isDark ? Colors.white10 : Colors.grey[300]!),
                ),
              ),
              onSelected: (val) {
                if (val) {
                  setState(() => _selectedMetodoPago = method);
                  _filterProformas();
                }
              },
            );
          }).toList(),
        ),
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

class _SlidableProformaTile extends StatefulWidget {
  final Map<String, dynamic> proforma;
  final int displayId;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRefresh;
  final VoidCallback onVerPDF;
  final VoidCallback onAprobarDesmarcar;
  final VoidCallback onGestionarPagos;
  final VoidCallback onMarcarDesmarcarCobrada;
  final VoidCallback onDelete;

  const _SlidableProformaTile({
    required this.proforma,
    required this.displayId,
    required this.onTap,
    required this.onLongPress,
    required this.onRefresh,
    required this.onVerPDF,
    required this.onAprobarDesmarcar,
    required this.onGestionarPagos,
    required this.onMarcarDesmarcarCobrada,
    required this.onDelete,
  });

  @override
  State<_SlidableProformaTile> createState() => _SlidableProformaTileState();
}

class _SlidableProformaTileState extends State<_SlidableProformaTile> {
  double _offset = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.proforma;
    final displayId = widget.displayId;
    final isComprobado = p['comprobado'] == 1;
    final isCobrado = p['estado_pago'] == 'cobrado';
    final double maxOffset = -325; // 5 buttons x 65 width

    // Map old payment methods to short display names
    String metodoPago = p['metodo_pago'] ?? 'Transferencia';
    if (metodoPago == 'Transferencia Bancaria') {
      metodoPago = 'Transferencia';
    } else if (metodoPago == 'Tarjeta de Crédito/Débito') {
      metodoPago = 'Tarjeta';
    }

    return Container(
      margin: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // BUTTON 1: PDF
                  InkWell(
                    onTap: () {
                      setState(() => _offset = 0);
                      widget.onVerPDF();
                    },
                    child: Container(
                      width: 65,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEFA820),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                          SizedBox(height: 2),
                          Text("PDF",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
                        ],
                      ),
                    ),
                  ),
                  // BUTTON 2: APROBAR / DESMARCAR
                  InkWell(
                    onTap: () {
                      setState(() => _offset = 0);
                      widget.onAprobarDesmarcar();
                    },
                    child: Container(
                      width: 65,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isComprobado ? Colors.deepOrangeAccent : Colors.orangeAccent,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(isComprobado ? Icons.remove_circle_outline_rounded : Icons.thumb_up_alt_outlined, color: Colors.white, size: 20),
                          const SizedBox(height: 2),
                          Text(isComprobado ? "DESMARCAR" : "APROBAR",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
                        ],
                      ),
                    ),
                  ),
                  // BUTTON 3: GESTIONAR PAGOS
                  InkWell(
                    onTap: () {
                      setState(() => _offset = 0);
                      widget.onGestionarPagos();
                    },
                    child: Container(
                      width: 65,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.payment, color: Colors.white, size: 20),
                          SizedBox(height: 2),
                          Text("PAGOS",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
                        ],
                      ),
                    ),
                  ),
                  // BUTTON 4: COBRAR / POR COBRAR
                  InkWell(
                    onTap: () {
                      setState(() => _offset = 0);
                      widget.onMarcarDesmarcarCobrada();
                    },
                    child: Container(
                      width: 65,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCobrado ? Colors.teal[700]! : Colors.teal,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(isCobrado ? Icons.undo : Icons.check_circle_outline, color: Colors.white, size: 20),
                          const SizedBox(height: 2),
                          Text(isCobrado ? "POR COBRAR" : "COBRAR",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
                        ],
                      ),
                    ),
                  ),
                  // BUTTON 5: ELIMINAR
                  InkWell(
                    onTap: () {
                      setState(() => _offset = 0);
                      widget.onDelete();
                    },
                    child: Container(
                      width: 65,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline, color: Colors.white, size: 20),
                          SizedBox(height: 2),
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
              child: InkWell(
                onTap: _offset == 0 ? widget.onTap : () => setState(() => _offset = 0),
                onLongPress: widget.onLongPress,
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isDark ? const Color(0xFF2C323D) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(
                      color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE2E8F0),
                      width: isDark ? 1.0 : 1.5,
                    ),
                  ),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "#${displayId.toString().padLeft(5, '0')}",
                                style: TextStyle(
                                  color: isDark ? Colors.white38 : Colors.grey[500],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p['clienteNombre']?.toString().toUpperCase() ?? 'SIN CLIENTE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p['fecha'] ?? '',
                                style: TextStyle(
                                  color: isDark ? Colors.white38 : Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Bs. ${(p['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  metodoPago,
                                  style: TextStyle(
                                    color: isDark ? Colors.white60 : Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                BlinkingDot(
                                  color: (p['estado_pago'] == 'cobrado')
                                      ? const Color(0xFF10B981)
                                      : (p['comprobado'] == 1)
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFFEFA820),
                                  shouldBlink: (() {
                                    if (p['estado_pago'] == 'cobrado') return false;
                                    if (p['comprobado'] == 1) return false;
                                    final String? comprobanteImg = p['comprobante_img']?.toString();
                                    final double saldoCancelado = (p['saldo_cancelado'] as num?)?.toDouble() ?? 0.0;
                                    return (comprobanteImg != null && comprobanteImg.isNotEmpty) || (saldoCancelado > 0.0);
                                  })(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
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
