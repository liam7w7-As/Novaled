import 'dart:async';
import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../../drive_service.dart';
import 'dart:convert';
import '../models/item_cotizacion.dart';
import '../services/sync_service.dart';
import 'cotizacion_vista_previa_screen.dart';
import '../../shared_widgets/shared_widgets.dart';

class NotasEntregaScreen extends StatefulWidget {
  final bool hideAppBar;
  final String tipoVenta;
  const NotasEntregaScreen({super.key, this.hideAppBar = false, this.tipoVenta = 'punto_venta'});

  @override
  State<NotasEntregaScreen> createState() => _NotasEntregaScreenState();
}

class _NotasEntregaScreenState extends State<NotasEntregaScreen> {
  List<Map<String, dynamic>> _notas = [];
  List<Map<String, dynamic>> _filteredNotas = [];
  List<Map<String, dynamic>> _quotes = [];
  final TextEditingController _searchController = TextEditingController();
  final DriveService _drive = DriveService();

  bool _isSyncing = false;

  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _refreshNotas().then((_) {
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

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshNotas() async {
    final data = await DatabaseHelper.instance.queryAllNotasEntrega(tipoVenta: widget.tipoVenta);
    final quotesData = await DatabaseHelper.instance.queryAllCotizaciones(tipoVenta: widget.tipoVenta);
    // Sort in descending order of date (and id as tie-breaker) so the latest note is shown first consistently across all devices
    final sortedData = List<Map<String, dynamic>>.from(data)..sort((a, b) {
      final dateA = a['fecha']?.toString() ?? '';
      final dateB = b['fecha']?.toString() ?? '';
      final dateComp = dateB.compareTo(dateA);
      if (dateComp != 0) return dateComp;
      
      final idA = a['id'] as int? ?? 0;
      final idB = b['id'] as int? ?? 0;
      return idB.compareTo(idA);
    });
    if (mounted) {
      setState(() {
        _notas = sortedData;
        _filteredNotas = sortedData;
        _quotes = quotesData;
      });
    }
  }

  int _getDisplayId(Map<String, dynamic> doc) {
    final uuid = doc['uuid']?.toString();
    if (uuid != null && uuid.isNotEmpty) {
      final sortedQuotes = List<Map<String, dynamic>>.from(_quotes)..sort((a, b) {
        final dateA = a['fecha']?.toString() ?? '';
        final dateB = b['fecha']?.toString() ?? '';
        final dateComp = dateB.compareTo(dateA);
        if (dateComp != 0) return dateComp;
        final idA = a['id'] as int? ?? 0;
        final idB = b['id'] as int? ?? 0;
        return idB.compareTo(idA);
      });
      final quoteIdx = sortedQuotes.indexWhere((c) => c['uuid']?.toString() == uuid);
      if (quoteIdx != -1) {
        return sortedQuotes.length - quoteIdx;
      }
    }
    final idx = _notas.indexWhere((n) => n['id'] == doc['id']);
    return idx != -1 ? (_notas.length - idx) : (doc['id'] as int? ?? 0);
  }  Future<void> _syncEverything({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _isSyncing = true);

    try {
      final success1 = await SyncService.instance.syncTable('cotizaciones').timeout(const Duration(seconds: 30));
      final success2 = await SyncService.instance.syncTable('notas_entrega').timeout(const Duration(seconds: 30));
      final success3 = await SyncService.instance.syncTable('proformas').timeout(const Duration(seconds: 30));
      await _refreshNotas();
      final success = success1 && success2 && success3;
      if (!silent && mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Documentos Sincronizados"), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Error de Sincronización"), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint("Error sync documentos: $e");
      if (!silent && mounted) {
        final cleanMsg = e.toString().replaceFirst('Exception: ', '');
        final isOffline = cleanMsg.contains("Modo Offline");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOffline ? cleanMsg : "Error de Sincronización: $cleanMsg"),
            backgroundColor: isOffline ? Colors.orange[800] : Colors.red,
            duration: Duration(seconds: isOffline ? 3 : 5),
          ),
        );
      }
    } finally {
      if (!silent && mounted) setState(() => _isSyncing = false);
    }
  }

  void _filterNotas(String query) {
    setState(() {
      _filteredNotas = _notas
          .where((nota) =>
              nota['clienteNombre'].toString().toLowerCase().contains(query.toLowerCase()) ||
              nota['id'].toString().contains(query))
          .toList();
    });
  }

  void _confirmarEliminacion(Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayId = _getDisplayId(item);
    final cliente = item['clienteNombre']?.toString().toUpperCase() ?? 'CLIENTE';

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
                "¿Eliminar Nota?",
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
              "¿Estás seguro de que deseas eliminar permanentemente esta nota de entrega?",
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
                    "Documento: Nota de Entrega #$displayId",
                    style: TextStyle(
                      color: const Color(0xFF00ADEF),
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
                  if (item['total'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      "Monto: ${item['total']?.toStringAsFixed(2)} Bs",
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
              // 1. Cerrar diálogo de confirmación
              Navigator.pop(confirmDialogContext);

              // 2. Mostrar diálogo de progreso "Espere..." no descartable
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
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00ADEF)),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Text(
                              "Procesando solicitud...",
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

              // 3. Borrado seguro en la nube (Drive)
              try {
                if (item['folderId'] != null && item['folderId'].toString().isNotEmpty) {
                  await _drive.deleteFile(item['folderId'].toString()).timeout(const Duration(seconds: 10));
                }
              } catch (e) {
                debugPrint("Error al borrar nota de entrega en Drive: $e");
              }

              // 4. Borrado en base de datos local
              try {
                await DatabaseHelper.instance.deleteNotaEntrega(item['id']);
              } catch (e) {
                debugPrint("Error al borrar nota de entrega localmente: $e");
              }

              // 5. Cerrar diálogo de progreso
              operationFinished = true;
              if (progressDialogContext != null && progressDialogContext!.mounted) {
                try {
                  Navigator.pop(progressDialogContext!);
                } catch (e) {
                  debugPrint("Error cerrando diálogo de progreso: $e");
                }
              }

              // 6. Refrescar interfaz y sincronizar en segundo plano
              if (mounted) {
                _refreshNotas();
                _syncEverything(silent: true);
              }
            },
            child: const Text("ELIMINAR", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _editarNota(Map<String, dynamic> nota, int displayId) {
    Navigator.pushNamed(
      context,
      '/notas_entrega/creacion',
      arguments: {
        'notaExistente': nota,
        'displayId': displayId,
        'tipoVenta': widget.tipoVenta,
      },
    ).then((_) => _refreshNotas());
  }

  Future<void> _verPDFNota(Map<String, dynamic> nota, int displayId) async {
    if (!mounted) return;

    // Decodificar itemsJson
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
          sucursal: nota['sucursal']?.toString(),
          vendedor: nota['vendedor']?.toString(),
          returnButtonText: "Volver a notas de entrega",
          onEdit: () {
            Navigator.pop(context);
            _editarNota(nota, docId);
          },
        ),
      ),
    );
  }

  void _mostrarOpciones(Map<String, dynamic> nota, int displayId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
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
              title: Text("Editar Nota de Entrega", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _editarNota(nota, displayId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.blueAccent),
              title: Text("Duplicar Nota de Entrega", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _duplicarNota(nota);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: Text("Eliminar permanentemente", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _confirmarEliminacion(nota);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _duplicarNota(Map<String, dynamic> nota) async {
    final Map<String, dynamic> nueva = Map.from(nota);
    nueva.remove('id');
    nueva.remove('uuid');
    nueva['fecha'] = DateTime.now().toString().split('.')[0];

    await DatabaseHelper.instance.insertNotaEntrega(nueva);
    _refreshNotas();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Nota duplicada con éxito"), backgroundColor: Colors.blueGrey),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: widget.hideAppBar ? null : AppBar(
        title: const Text("NOTAS DE ENTREGA"),
        centerTitle: true,
        backgroundColor: isDark ? Colors.transparent : const Color(0xFF00ADEF),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'Montserrat',
        ),
        actions: const [],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(
          context,
          '/notas_entrega/creacion',
          arguments: {'tipoVenta': widget.tipoVenta},
        ).then((_) => _refreshNotas()),
        label: const Text("Nueva Nota", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.black),
        backgroundColor: const Color(0xFF00ADEF),
      ),
      body: Column(
        children: [
          UniversalSearchBar(
            controller: _searchController,
            onChanged: _filterNotas,
            hintText: "Buscar por cliente o #...",
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (_notas.isEmpty) {
                  await _syncEverything();
                } else {
                  await _refreshNotas();
                }
              },
              color: const Color(0xFF00ADEF),
              backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.grey[200],
              child: _notas.isEmpty && _isSyncing
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00ADEF)))
                  : _filteredNotas.isEmpty
                      ? Stack(
                          children: [
                            ListView(),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.assignment_outlined, size: 80, color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
                                  const SizedBox(height: 16),
                                  Text("No hay notas de entrega. Desliza para sincronizar.", style: TextStyle(color: isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.4))),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _filteredNotas.length,
                          itemBuilder: (context, index) {
                            final nota = _filteredNotas[index];
                            final displayId = _getDisplayId(nota);
                            final totalNum = (nota['total'] as num?)?.toDouble() ?? 0.0;
                            final totalStr = totalNum.toStringAsFixed(2);
                            final fechaStr = nota['fecha']?.toString().split(' ')[0] ?? '';
                            final cliente = (nota['clienteNombre']?.toString().trim().isNotEmpty ?? false)
                                ? nota['clienteNombre'].toString().trim()
                                : "Sin Cliente";

                            return DocumentSlidableTile(
                              title: cliente,
                              displayId: displayId,
                              monto: "Bs. $totalStr",
                              fecha: fechaStr,
                              vendedor: nota['vendedor']?.toString(),
                              sucursal: nota['sucursal']?.toString(),
                              onTap: () => _editarNota(nota, displayId),
                              onLongPress: () => _mostrarOpciones(nota, displayId),
                              actions: [
                                SlidableActionItem(
                                  icon: Icons.picture_as_pdf_outlined,
                                  label: "PDF",
                                  onTap: () => _verPDFNota(nota, displayId),
                                ),
                                SlidableActionItem(
                                  icon: Icons.copy_outlined,
                                  label: "Copiar",
                                  onTap: () => _duplicarNota(nota),
                                ),
                                SlidableActionItem(
                                  icon: Icons.delete_outline_rounded,
                                  label: "Borrar",
                                  onTap: () => _confirmarEliminacion(nota),
                                ),
                              ],
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
