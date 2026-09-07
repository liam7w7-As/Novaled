import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database_helper.dart';
import '../models/cliente.dart';
import '../models/item_cotizacion.dart';
import '../models/articulo.dart';
import '../services/pdf_service.dart';
import '../services/docx_service.dart';
import 'package:docx_creator/src/utils/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../drive_service.dart';
import '../services/sync_service.dart';
import 'agregar_articulo_screen.dart';
import '../../login_screen.dart';
import '../tenant_helper.dart';
import '../widgets/zoomable_pdf_preview.dart';
import '../widgets/novaled_toast.dart';
import '../widgets/novaled_thick_icon.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'crear_cotizacion_escaneada_screen.dart';
import 'cotizacion_vista_previa_screen.dart';


class CrearCotizacionScreen extends StatefulWidget {
  final Map<String, dynamic>? cotizacionExistente;
  final int? displayId;
  final String tipoVenta;
  final bool isDirectoPorCobrar;
  const CrearCotizacionScreen({
    super.key,
    this.cotizacionExistente,
    this.displayId,
    this.tipoVenta = 'cotizacion',
    this.isDirectoPorCobrar = false,
  });

  @override
  State<CrearCotizacionScreen> createState() => _CrearCotizacionScreenState();
}

class _CrearCotizacionScreenState extends State<CrearCotizacionScreen> {
  final List<ItemCotizacion> _items = [];
  double _descuentoPorcentaje = 0.0;
  bool _incluyeFirmaEmpresa = false;
  bool _incluyeFirmaCliente = false;
  final TextEditingController _notasController = TextEditingController();
  final TextEditingController _terminosController = TextEditingController(
    text: "- Validez de la oferta: 5 días.\n- Garantía: Según especificaciones del fabricante.\n- Forma de pago: Contado/Transferencia."
  );
  bool _isSaved = false;
  int? _idCotizacionExistente;
  int? _displayId;
  String _estado = 'pendiente';
  bool _isColor = true;
  bool _mostrarAhorro = false;
  bool _mostrarTerminos = false;
  final DriveService _drive = DriveService();
  String? _fechaDocumento;
  String? _uuid;
  bool _mostrarNotas = false;
  String? _vendedorOriginal;

  List<String> _listaVendedores = [];
  List<String> _listaSucursales = [];
  String? _vendedorSeleccionado;
  String? _sucursalSeleccionada;

  Future<void> _loadVendedoresYSucursales() async {
    await TenantHelper.syncTenantSettings();
    final vendedores = await TenantHelper.getVendedores();
    final sucursales = await TenantHelper.getSucursales();
    final currentUname = Session().userName?.trim();
    final userDisplay = (currentUname != null && currentUname.isNotEmpty)
        ? (currentUname.contains('@') ? currentUname.split('@').first.toUpperCase() : currentUname.toUpperCase())
        : (vendedores.isNotEmpty ? vendedores.first : '');

    if (mounted) {
      setState(() {
        _listaVendedores = vendedores;
        _listaSucursales = sucursales;
        
        _vendedorSeleccionado ??= (widget.cotizacionExistente?['vendedor']?.toString().isNotEmpty ?? false)
            ? widget.cotizacionExistente!['vendedor'].toString()
            : userDisplay;
            
        _sucursalSeleccionada ??= (widget.cotizacionExistente?['sucursal']?.toString().isNotEmpty ?? false)
            ? widget.cotizacionExistente!['sucursal'].toString()
            : (_listaSucursales.isNotEmpty ? _listaSucursales.first : '');
      });
    }
  }

  Future<void> _mostrarSelectorVendedor() async {
    await _loadVendedoresYSucursales();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.70),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E222B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                "Seleccionar Vendedor",
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _listaVendedores.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final item = _listaVendedores[idx];
                    final isSel = item == _vendedorSeleccionado;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      title: Text(
                        item,
                        style: GoogleFonts.poppins(
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          color: isSel ? Theme.of(context).primaryColor : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      trailing: isSel ? Icon(Icons.check_circle_rounded, color: Theme.of(context).primaryColor) : null,
                      onTap: () {
                        setState(() {
                          _vendedorSeleccionado = item;
                        });
                        _onDataChangedAutoSave();
                        Navigator.pop(ctx);
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
  }

  Future<void> _mostrarSelectorSucursal() async {
    await _loadVendedoresYSucursales();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.70),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E222B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                "Seleccionar Sucursal",
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _listaSucursales.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final item = _listaSucursales[idx];
                    final isSel = item == _sucursalSeleccionada;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      title: Text(
                        item,
                        style: GoogleFonts.poppins(
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          color: isSel ? Theme.of(context).primaryColor : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      trailing: isSel ? Icon(Icons.check_circle_rounded, color: Theme.of(context).primaryColor) : null,
                      onTap: () {
                        setState(() {
                          _sucursalSeleccionada = item;
                        });
                        _onDataChangedAutoSave();
                        Navigator.pop(ctx);
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
  }

  Widget _buildVendedorSucursalCard(bool isDark, Color textColor, Color labelColor) {
    final cardBg = isDark ? const Color(0xFF1E222B) : Colors.white;
    final dividerColor = isDark ? Colors.white24 : const Color(0xFFF1F5F9);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Vendedor Section
            Expanded(
              child: InkWell(
                onTap: _mostrarSelectorVendedor,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Vendedor",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, size: 14, color: isDark ? Colors.white70 : Colors.black),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _vendedorSeleccionado ?? "seleccionar",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w400,
                                      color: _vendedorSeleccionado != null
                                          ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                          : (isDark ? Colors.white54 : Colors.black.withOpacity(0.45)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_down, size: 16, color: isDark ? Colors.white54 : Colors.black.withOpacity(0.45)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Vertical Divider
            VerticalDivider(
              color: dividerColor,
              thickness: 1,
              width: 24,
              indent: 4,
              endIndent: 4,
            ),

            // Sucursal Section
            Expanded(
              child: InkWell(
                onTap: _mostrarSelectorSucursal,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Sucursal",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(Icons.storefront_outlined, size: 14, color: isDark ? Colors.white70 : Colors.black),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _sucursalSeleccionada ?? "Seleccionar",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w400,
                                      color: _sucursalSeleccionada != null
                                          ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                          : (isDark ? Colors.white54 : Colors.black.withOpacity(0.45)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_down, size: 16, color: isDark ? Colors.white54 : Colors.black.withOpacity(0.45)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Nuevas variables para clientes flexibles e inline stepper
  final TextEditingController _clienteNombreCtrl = TextEditingController();
  final TextEditingController _clienteTelefonoCtrl = TextEditingController();
  final TextEditingController _clienteCorreoCtrl = TextEditingController();
  List<Cliente> _todosClientes = [];
  final List<int> _newArticlesCreatedIds = [];

  int _currentStep = 1;
  int _comprobado = 0;
  List<Cliente> _sugeridosClientes = [];
  bool _showClientSuggestions = false;

  // Inline product adding state
  bool _isEditingClientScreen = false;
  int? _selectedArticleIndexForActions;
  bool _isAddingArticleInline = false;
  bool _isSearchingProduct = false;
  bool _isShowingSuccessAnimation = false;
  bool _isPorPagar = true;
  String _metodoPagoSeleccionado = "QR";
  String _tipoDocumentoSeleccionado = "proforma";
  final TextEditingController _numComprobanteController = TextEditingController();
  String? _comprobanteImgPath;
  int _selectedEstadoPagoTab = 0;
  final TextEditingController _prodNombreCtrl = TextEditingController();
  final TextEditingController _prodPrecioCtrl = TextEditingController();
  final TextEditingController _prodCantCtrl = TextEditingController();
  final FocusNode _prodNombreFocusNode = FocusNode();
  Articulo? _selectedCatalogArticulo;
  List<Articulo> _filtradosProd = [];
  bool _showProdSuggestions = false;
  int? _editingItemIndex;

  List<Articulo> _catalogArticulos = [];
  List<String> _unidadesMedida = [];
  String _seleccionUnidadMedida = "Unidad";
  String _metodoPago = "Transferencia";
  Timer? _autoSaveTimer;
  bool _isAutoSaving = false;

  void _onDataChangedAutoSave({bool immediate = false}) {
    _autoSaveTimer?.cancel();
    if (immediate) {
      _autoSaveSilently();
    } else {
      _autoSaveTimer = Timer(const Duration(milliseconds: 150), () {
        _autoSaveSilently();
      });
    }
  }

  Future<bool> _autoSaveSilently({bool showDialogOnLimit = false}) async {
    if (!mounted) return false;
    if (_isAutoSaving) return _isSaved;
    final clienteNombreText = _clienteNombreCtrl.text.trim();

    // No auto-guardar si aún no existe en BD y no hay productos ni nombre de cliente ingresados
    if (_idCotizacionExistente == null && _items.isEmpty && clienteNombreText.isEmpty) {
      return false;
    }

    _isAutoSaving = true;

    try {
      // 1. Auto-crear o actualizar cliente en SQLite si se ingresó un nombre
      if (clienteNombreText.isNotEmpty &&
          clienteNombreText.toLowerCase() != 'sin cliente' &&
          clienteNombreText.toLowerCase() != 'sin cliente asignado' &&
          clienteNombreText.toLowerCase() != 'cliente / empresa') {
        Cliente? matchedCliente;
        try {
          matchedCliente = _todosClientes.firstWhere(
            (c) => c.nombreCompania.toLowerCase() == clienteNombreText.toLowerCase(),
          );
        } catch (_) {}

        if (matchedCliente != null) {
          if (matchedCliente.telefono != _clienteTelefonoCtrl.text.trim() ||
              matchedCliente.correo != _clienteCorreoCtrl.text.trim()) {
            final updatedCliente = Cliente(
              id: matchedCliente.id,
              nombreCompania: matchedCliente.nombreCompania,
              telefono: _clienteTelefonoCtrl.text.trim(),
              correo: _clienteCorreoCtrl.text.trim(),
              folderId: matchedCliente.folderId,
            );
            await DatabaseHelper.instance.updateCliente(updatedCliente.toMap());
            _drive.syncItemToDrive('clientes', updatedCliente.toMap()).then((newFolderId) async {
              if (newFolderId != null && newFolderId != updatedCliente.folderId) {
                final updatedMap = updatedCliente.toMap()..['folderId'] = newFolderId;
                await DatabaseHelper.instance.updateCliente(updatedMap);
              }
            });
          }
        } else {
          final nuevoCliente = Cliente(
            nombreCompania: clienteNombreText,
            telefono: _clienteTelefonoCtrl.text.trim(),
            correo: _clienteCorreoCtrl.text.trim(),
          );
          final newId = await DatabaseHelper.instance.insertCliente(nuevoCliente.toMap());
          final createdCliente = Cliente(
            id: newId,
            nombreCompania: nuevoCliente.nombreCompania,
            telefono: nuevoCliente.telefono,
            correo: nuevoCliente.correo,
          );
          _drive.syncItemToDrive('clientes', createdCliente.toMap()).then((newFolderId) async {
            if (newFolderId != null) {
              final updatedMap = createdCliente.toMap()..['folderId'] = newFolderId;
              await DatabaseHelper.instance.updateCliente(updatedMap);
            }
          });
          _todosClientes.add(createdCliente);
        }
      }

      // Auto-guardar productos agregados en inventario si aún no existen
      for (var itm in _items) {
        final artName = itm.articulo.nombre.trim();
        if (artName.isNotEmpty) {
          try {
            final db = await DatabaseHelper.instance.database;
            final existing = await db.query('articulos', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [artName.toLowerCase()], limit: 1);
            if (existing.isEmpty) {
              final uuid = "ART_${DateTime.now().millisecondsSinceEpoch}_${artName.hashCode.abs()}";
              await DatabaseHelper.instance.insertArticulo({
                'nombre': artName,
                'precio': itm.articulo.precio,
                'descripcion': itm.articulo.descripcion ?? '',
                'unidad': itm.articulo.unidad.isNotEmpty ? itm.articulo.unidad : 'Unidad',
                'folderId': uuid,
              });
            }
          } catch (e) {
            debugPrint("Error guardando artículo en inventario: $e");
          }
        }
      }
      SyncService.instance.syncTable('articulos').catchError((_) {});

      // 2. Preparar campos de Cotización / Proforma
      _fechaDocumento = _formatSoloFecha(_fechaDocumento);
      final bool isPuntoDeVenta = widget.isDirectoPorCobrar ||
          widget.tipoVenta == 'punto_venta' ||
          widget.cotizacionExistente?['tipo_venta'] == 'punto_venta';

      final String uuidToUse = _uuid ?? "COT_${DateTime.now().millisecondsSinceEpoch}";
      _uuid = uuidToUse;

      int computedDisplayId;
      if (_displayId != null) {
        computedDisplayId = _displayId!;
      } else {
        final all = isPuntoDeVenta
            ? await DatabaseHelper.instance.queryAllProformas()
            : await DatabaseHelper.instance.queryAllCotizaciones();
        computedDisplayId = all.length + 1;
      }

      final String finalTipoVenta = isPuntoDeVenta
          ? 'punto_venta'
          : (widget.tipoVenta ?? 'cotizacion');

      final Map<String, dynamic> docData = {
        if (_idCotizacionExistente != null) 'id': _idCotizacionExistente,
        'uuid': uuidToUse,
        'displayId': computedDisplayId,
        'clienteNombre': clienteNombreText.isEmpty ? 'Sin Cliente' : clienteNombreText,
        'clienteTelefono': _clienteTelefonoCtrl.text.trim(),
        'clienteCorreo': _clienteCorreoCtrl.text.trim(),
        'fecha': _fechaDocumento,
        'subtotal': _subtotal,
        'impuesto': 0.0,
        'descuento': _montoDescuento,
        'descuentoPorcentaje': _descuentoPorcentaje,
        'total': _total,
        'notas': _notasController.text,
        'terminos': _terminosController.text,
        'incluyeFirmaEmpresa': _incluyeFirmaEmpresa ? 1 : 0,
        'incluyeFirmaCliente': _incluyeFirmaCliente ? 1 : 0,
        'mostrarTerminos': _mostrarTerminos ? 1 : 0,
        'mostrarAhorro': _mostrarAhorro ? 1 : 0,
        'itemsJson': jsonEncode(_items.map((i) => i.toMap()).toList()),
        'tipo_venta': finalTipoVenta,
        'tipo_documento': _tipoDocumentoSeleccionado ?? (widget.isDirectoPorCobrar ? 'proforma' : 'cotizacion'),
        'estado_pago': _isPorPagar ? 'por_cobrar' : 'pagado',
        'vendedor': _vendedorSeleccionado ?? _vendedorOriginal ?? (Session().userName ?? ''),
        'sucursal': _sucursalSeleccionada ?? (_listaSucursales.isNotEmpty ? _listaSucursales.first : ''),
        'metodo_pago': _metodoPagoSeleccionado,
        'comprobante_img': (_comprobanteImgPath != null && _comprobanteImgPath!.isNotEmpty)
            ? _comprobanteImgPath!
            : (_selectedEstadoPagoTab == 2 ? _numComprobanteController.text.trim() : ''),
        'comprobado': _comprobado,
        'estado': _estado,
      };

      // 3. Guardar/Actualizar en SQLite
      if (isPuntoDeVenta) {
        final isNota = _tipoDocumentoSeleccionado == 'nota_entrega' || 
                       (widget.cotizacionExistente?['tipo'] == 'nota_entrega') ||
                       (widget.cotizacionExistente?['tipo_documento'] == 'nota_entrega');
        if (_idCotizacionExistente != null) {
          if (isNota) {
            await DatabaseHelper.instance.updateNotaEntrega(docData);
          } else {
            await DatabaseHelper.instance.updateProforma(docData);
          }
          if (uuidToUse.isNotEmpty) {
            final db = await DatabaseHelper.instance.database;
            for (var t in ['proformas', 'notas_entrega', 'cotizaciones']) {
              try {
                await DatabaseHelper.instance.setTableDirty(t);
                await db.update(
                  t,
                  {
                    'clienteNombre': docData['clienteNombre'],
                    'clienteTelefono': docData['clienteTelefono'],
                    'clienteCorreo': docData['clienteCorreo'],
                    'fecha': docData['fecha'],
                    'subtotal': docData['subtotal'],
                    'descuento': docData['descuento'],
                    'descuentoPorcentaje': docData['descuentoPorcentaje'],
                    'total': docData['total'],
                    'notas': docData['notas'],
                    'terminos': docData['terminos'],
                    'itemsJson': docData['itemsJson'],
                    'sucursal': docData['sucursal'],
                    'vendedor': docData['vendedor'],
                    'comprobante_img': docData['comprobante_img'],
                    'estado_pago': docData['estado_pago'],
                    'metodo_pago': docData['metodo_pago'],
                    'comprobado': docData['comprobado'],
                  },
                  where: 'uuid = ?',
                  whereArgs: [uuidToUse],
                );
              } catch (_) {}
            }
          }
        } else {
          if (isNota) {
            final canCreate = await PlanLimitHelper.canCreateNotaEntrega();
            if (!canCreate) {
              _isAutoSaving = false;
              if (showDialogOnLimit && mounted) {
                PlanLimitHelper.showUpgradeDialog(context, feature: "notas de entrega", currentLimit: PlanLimitHelper.freeNotasEntrega);
              }
              return false;
            }
            final savedId = await DatabaseHelper.instance.insertNotaEntrega(docData);
            _idCotizacionExistente = savedId;
          } else {
            final canCreate = await PlanLimitHelper.canCreateNotaVenta();
            if (!canCreate) {
              _isAutoSaving = false;
              if (showDialogOnLimit && mounted) {
                PlanLimitHelper.showUpgradeDialog(context, feature: "notas de venta", currentLimit: PlanLimitHelper.freeNotasVenta);
              }
              return false;
            }
            final savedId = await DatabaseHelper.instance.insertProforma(docData);
            _idCotizacionExistente = savedId;
          }
          _displayId = computedDisplayId;
        }
        await DatabaseHelper.instance.setTableDirty('notas_entrega');
        await DatabaseHelper.instance.setTableDirty('proformas');
        SyncService.instance.syncTable('notas_entrega').catchError((e) {});
        SyncService.instance.syncTable('proformas').catchError((e) {});
      } else {
        if (_idCotizacionExistente != null) {
          await DatabaseHelper.instance.updateCotizacion(docData);
          if (uuidToUse.isNotEmpty) {
            final db = await DatabaseHelper.instance.database;
            for (var t in ['proformas', 'notas_entrega', 'cotizaciones']) {
              try {
                await DatabaseHelper.instance.setTableDirty(t);
                await db.update(
                  t,
                  {
                    'clienteNombre': docData['clienteNombre'],
                    'clienteTelefono': docData['clienteTelefono'],
                    'clienteCorreo': docData['clienteCorreo'],
                    'fecha': docData['fecha'],
                    'subtotal': docData['subtotal'],
                    'descuento': docData['descuento'],
                    'descuentoPorcentaje': docData['descuentoPorcentaje'],
                    'total': docData['total'],
                    'notas': docData['notas'],
                    'terminos': docData['terminos'],
                    'itemsJson': docData['itemsJson'],
                    'sucursal': docData['sucursal'],
                    'vendedor': docData['vendedor'],
                    'comprobante_img': docData['comprobante_img'],
                    'estado_pago': docData['estado_pago'],
                    'metodo_pago': docData['metodo_pago'],
                    'comprobado': docData['comprobado'],
                  },
                  where: 'uuid = ?',
                  whereArgs: [uuidToUse],
                );
              } catch (_) {}
            }
          }
        } else {
          final canCreate = await PlanLimitHelper.canCreateCotizacion();
          if (!canCreate) {
            _isAutoSaving = false;
            if (showDialogOnLimit && mounted) {
              PlanLimitHelper.showUpgradeDialog(context, feature: "cotizaciones", currentLimit: PlanLimitHelper.freeCotizaciones);
            }
            return false;
          }
          final savedId = await DatabaseHelper.instance.insertCotizacion(docData);
          _idCotizacionExistente = savedId;
          _displayId = computedDisplayId;
        }
        await DatabaseHelper.instance.setTableDirty('cotizaciones');
        await DatabaseHelper.instance.setTableDirty('proformas');
        await DatabaseHelper.instance.setTableDirty('notas_entrega');
        SyncService.instance.syncTable('cotizaciones').catchError((e) {});
        SyncService.instance.syncTable('proformas').catchError((e) {});
        SyncService.instance.syncTable('notas_entrega').catchError((e) {});
      }

      _isSaved = true;
      debugPrint("Auto-saved quotation ID: $_idCotizacionExistente with client: ${clienteNombreText.isEmpty ? 'Sin Cliente' : clienteNombreText}");
      return true;
    } catch (e, st) {
      debugPrint("Auto-save error: $e\n$st");
      return false;
    } finally {
      _isAutoSaving = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _prodNombreFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _clienteNombreCtrl.addListener(_onDataChangedAutoSave);
    _clienteTelefonoCtrl.addListener(_onDataChangedAutoSave);
    _clienteCorreoCtrl.addListener(_onDataChangedAutoSave);
    _prodNombreCtrl.addListener(_onDataChangedAutoSave);
    _prodPrecioCtrl.addListener(_onDataChangedAutoSave);
    _prodCantCtrl.addListener(_onDataChangedAutoSave);
    _notasController.addListener(_onDataChangedAutoSave);
    _terminosController.addListener(_onDataChangedAutoSave);

    _loadClientes();
    _loadCatalogData();
    _cargarUnidadesMedida();
    _loadVendedoresYSucursales();
    if (widget.displayId != null) {
      _displayId = widget.displayId;
    }
    if (widget.cotizacionExistente != null) {
      _cargarCotizacion(widget.cotizacionExistente!);
      _currentStep = 3;
    } else {
      _tipoDocumentoSeleccionado = widget.tipoVenta == 'cotizacion' ? 'cotizacion' : 'proforma';
    }

    _startLiveSyncPolling();
  }

  Timer? _liveSyncPollingTimer;

  void _startLiveSyncPolling() {
    _liveSyncPollingTimer?.cancel();
    _liveSyncPollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted || _isAutoSaving) return;

      // 1. Sincronizar catálogo de artículos y unidades de medida en tiempo real
      try {
        await SyncService.instance.syncTable('articulos').catchError((_) {});
        await SyncService.instance.syncTable('unidades_medida').catchError((_) {});
        final dbHelper = DatabaseHelper.instance;
        final articulosRaw = await dbHelper.queryAllArticulos();
        final List<Articulo> allArt = articulosRaw.map((a) => Articulo.fromMap(a)).toList();
        if (mounted && (allArt.length != _catalogArticulos.length || _catalogArticulos.isEmpty)) {
          setState(() {
            _catalogArticulos = allArt;
            _filterProdSuggestions(_prodNombreCtrl.text);
          });
        }
        final umRaw = await dbHelper.queryAllUnidadesMedida();
        final umNames = umRaw.map((u) => u['nombre']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
        if (mounted && umNames.isNotEmpty && (umNames.length != _listaUnidadesMedida.length || umNames.first != _listaUnidadesMedida.first)) {
          setState(() {
            _listaUnidadesMedida = umNames;
            if (!_listaUnidadesMedida.contains(_seleccionUnidadMedida)) {
              _seleccionUnidadMedida = _listaUnidadesMedida.first;
            }
          });
        }
      } catch (_) {}

      final docUuid = widget.cotizacionExistente?['uuid'] ?? _uuid;

      try {
        final tablesToTry = isPuntoDeVenta 
            ? (_tipoDocumentoSeleccionado == 'nota_entrega' ? ['notas_entrega', 'proformas'] : ['proformas', 'notas_entrega']) 
            : ['cotizaciones'];

        final db = await DatabaseHelper.instance.database;
        List<Map<String, dynamic>> res = [];

        for (var t in tablesToTry) {
          await SyncService.instance.syncTable(t).catchError((_) {});
          if (docUuid != null && docUuid.toString().isNotEmpty) {
            res = await db.query(t, where: 'uuid = ?', whereArgs: [docUuid.toString()], limit: 1);
          }
          if (res.isEmpty && _displayId != null && _displayId! > 0) {
            res = await db.query(t, where: 'displayId = ?', whereArgs: [_displayId], limit: 1);
          }
          if (res.isNotEmpty) {
            _uuid = res.first['uuid']?.toString() ?? _uuid;
            _idCotizacionExistente = res.first['id'] as int?;
            break;
          }
        }

        if (res.isNotEmpty && mounted) {
          final row = res.first;
          final remoteImg = (row['comprobante_img'] ?? '').toString().trim();
          final remoteEstadoPago = row['estado_pago']?.toString();
          final remoteMetodoPago = row['metodo_pago']?.toString();
          final remoteVendedor = row['vendedor']?.toString();

          final remoteItemsJson = row['itemsJson']?.toString();
          final remoteCliente = row['clienteNombre']?.toString();

          bool needsUpdate = false;

          // Sincronizar items en tiempo real únicamente si la lista local está vacía o se está iniciando
          if (_items.isEmpty && remoteItemsJson != null && remoteItemsJson.isNotEmpty) {
            try {
              final List<dynamic> itemsList = jsonDecode(remoteItemsJson);
              for (var itemMap in itemsList) {
                _items.add(ItemCotizacion.fromMap(itemMap));
              }
              needsUpdate = true;
            } catch (_) {}
          }



          final currentImg = _comprobanteImgPath ?? '';
          if (remoteImg != currentImg) {
            _comprobanteImgPath = remoteImg.isEmpty ? null : remoteImg;
            if (_comprobanteImgPath == null) {
              _numComprobanteController.clear();
            }
            needsUpdate = true;
          }
          if (remoteVendedor != null && remoteVendedor.isNotEmpty && remoteVendedor != _vendedorSeleccionado) {
            _vendedorSeleccionado = remoteVendedor;
            needsUpdate = true;
          }
          if (remoteEstadoPago != null && (_isPorPagar != (remoteEstadoPago == 'por_cobrar'))) {
            _isPorPagar = (remoteEstadoPago == 'por_cobrar');
            needsUpdate = true;
          }
          if (remoteMetodoPago != null && remoteMetodoPago.isNotEmpty && remoteMetodoPago != _metodoPagoSeleccionado) {
            _metodoPagoSeleccionado = remoteMetodoPago;
            needsUpdate = true;
          }

          if (needsUpdate && mounted) {
            setState(() {
              final mpLower = (_metodoPagoSeleccionado ?? '').toLowerCase();
              if (_isPorPagar) {
                _selectedEstadoPagoTab = 3;
              } else if (mpLower.contains('qr') || (_comprobanteImgPath != null && _comprobanteImgPath!.isNotEmpty)) {
                _selectedEstadoPagoTab = 1;
                _metodoPagoSeleccionado = "QR";
              } else if (mpLower.contains('transf') || mpLower.contains('banco')) {
                _selectedEstadoPagoTab = 2;
                _metodoPagoSeleccionado = "Transferencia";
              } else {
                _selectedEstadoPagoTab = 0;
                _metodoPagoSeleccionado = "Efectivo";
              }
            });
          }
        }
      } catch (e) {
        debugPrint("Error in liveSync polling: $e");
      }
    });
  }

  @override
  void dispose() {
    _liveSyncPollingTimer?.cancel();
    _autoSaveTimer?.cancel();
    _clienteNombreCtrl.removeListener(_onDataChangedAutoSave);
    _clienteTelefonoCtrl.removeListener(_onDataChangedAutoSave);
    _clienteCorreoCtrl.removeListener(_onDataChangedAutoSave);
    _prodNombreCtrl.removeListener(_onDataChangedAutoSave);
    _prodPrecioCtrl.removeListener(_onDataChangedAutoSave);
    _prodCantCtrl.removeListener(_onDataChangedAutoSave);
    _notasController.removeListener(_onDataChangedAutoSave);
    _terminosController.removeListener(_onDataChangedAutoSave);
    _clienteNombreCtrl.dispose();
    _clienteTelefonoCtrl.dispose();
    _clienteCorreoCtrl.dispose();
    _notasController.dispose();
    _terminosController.dispose();
    super.dispose();
  }

  void _sanitizeControllerValues() {
    final t = _clienteTelefonoCtrl.text.trim().toLowerCase();
    if (t == "celular" || t == "teléfono" || t == "telefono") {
      _clienteTelefonoCtrl.clear();
    }
    final c = _clienteCorreoCtrl.text.trim().toLowerCase();
    if (c == "email" || c == "correo" || c == "email...") {
      _clienteCorreoCtrl.clear();
    }
    final n = _clienteNombreCtrl.text.trim().toLowerCase();
    if (n == "cliente / empresa" || n == "nombre / empresa" || n == "sin cliente" || n == "sin cliente asignado" || n == "sin nombre") {
      _clienteNombreCtrl.clear();
    }
  }

  Future<void> _loadClientes() async {
    try {
      final list = await DatabaseHelper.instance.queryAllClientes();
      setState(() {
        _todosClientes = list.map((c) => Cliente.fromMap(c)).toList();
      });
      if (widget.cotizacionExistente != null) {
        final name = widget.cotizacionExistente!['clienteNombre'] as String?;
        if (name != null && name.isNotEmpty && name.trim().toLowerCase() != 'sin cliente' && name.trim().toLowerCase() != 'sin cliente asignado') {
          final match = _todosClientes.firstWhere(
            (c) => c.nombreCompania.toLowerCase() == name.toLowerCase(),
            orElse: () => Cliente(nombreCompania: name, telefono: "", correo: ""),
          );
          _clienteTelefonoCtrl.text = match.telefono;
          _clienteCorreoCtrl.text = match.correo;
        }
      }
      _sanitizeControllerValues();
    } catch (e) {
      debugPrint("Error loading clientes: $e");
    }
  }

  Future<void> _loadCatalogData() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final articulosRaw = await dbHelper.queryAllArticulos();
      final List<Articulo> allArt = articulosRaw.map((a) => Articulo.fromMap(a)).toList();
      final rawUnits = await dbHelper.queryAllUnidadesMedida();
      final List<String> unitNames = rawUnits.map((u) => u['nombre']?.toString() ?? '').where((name) => name.isNotEmpty).toList();

      setState(() {
        _catalogArticulos = allArt;
        _unidadesMedida = unitNames;
        if (_unidadesMedida.isNotEmpty && !_unidadesMedida.contains(_seleccionUnidadMedida)) {
          _seleccionUnidadMedida = _unidadesMedida.first;
        } else if (_unidadesMedida.isEmpty) {
          _unidadesMedida = ["Unidad", "Caja", "Paquete", "Metro", "Litro"];
          _seleccionUnidadMedida = "Unidad";
        }
      });
    } catch (e) {
      debugPrint("Error loading catalog data: $e");
    }
  }

  void _filtrarSugeridosClientes(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _sugeridosClientes = [];
      });
      return;
    }
    final lowercaseQuery = query.toLowerCase();
    setState(() {
      _sugeridosClientes = _todosClientes.where((c) {
        return c.nombreCompania.toLowerCase().contains(lowercaseQuery);
      }).toList();
    });
  }

  void _filterProdSuggestions(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _filtradosProd = [];
      });
      return;
    }
    final lowercaseQuery = query.toLowerCase();
    setState(() {
      _filtradosProd = _catalogArticulos.where((a) {
        return a.nombre.toLowerCase().contains(lowercaseQuery);
      }).toList();
    });
  }

  void _startEditingItem(int index) {
    final item = _items[index];
    setState(() {
      _editingItemIndex = index;
      _selectedCatalogArticulo = item.articulo;
      _prodNombreCtrl.text = item.articulo.nombre;
      _prodPrecioCtrl.text = item.articulo.precio.toString();
      _prodCantCtrl.text = item.cantidad.toString();
      _seleccionUnidadMedida = item.articulo.unidad.isNotEmpty ? item.articulo.unidad : "Unidad";
      _isAddingArticleInline = true;
    });

  }

  void _saveItemInline() {
    final nombre = _prodNombreCtrl.text.trim();
    if (nombre.isEmpty) return;

    final precio = double.tryParse(_prodPrecioCtrl.text) ?? 0.0;
    final cantidad = int.tryParse(_prodCantCtrl.text) ?? 1;

    // Construir stockJson Map
    Map<String, dynamic> stockJsonMap = {};
    if (_selectedCatalogArticulo?.stockJson != null && _selectedCatalogArticulo!.stockJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(_selectedCatalogArticulo!.stockJson!);
        if (decoded is Map) {
          stockJsonMap = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    final art = Articulo(
      id: _selectedCatalogArticulo?.id,
      nombre: nombre,
      precio: precio,
      descripcion: _selectedCatalogArticulo?.descripcion ?? '',
      unidad: _seleccionUnidadMedida,
      unidadDetalle: _selectedCatalogArticulo?.unidadDetalle ?? '',
      imagen: _selectedCatalogArticulo?.imagen,
      stockJson: jsonEncode(stockJsonMap),
      folderId: _selectedCatalogArticulo?.folderId,
      finalArtId: _selectedCatalogArticulo?.finalArtId,
      proveedor: _selectedCatalogArticulo?.proveedor ?? 'Novaled',
      familia: _selectedCatalogArticulo?.familia ?? '',
      subcategoria: _selectedCatalogArticulo?.subcategoria ?? '',
      fecha: _selectedCatalogArticulo?.fecha ?? DateTime.now().toIso8601String().substring(0, 10),
    );

    final item = ItemCotizacion(
      articulo: art,
      precioOriginal: _selectedCatalogArticulo?.precio ?? precio,
      cantidad: cantidad,
    );

    setState(() {
      if (_editingItemIndex != null) {
        _items[_editingItemIndex!] = item;
        _editingItemIndex = null;
      } else {
        _items.add(item);
      }
      _isSaved = false;

      // Reset form
      _prodNombreFocusNode.unfocus();
      _prodNombreCtrl.clear();
      _prodPrecioCtrl.clear();
      _prodCantCtrl.clear();
      _selectedCatalogArticulo = null;
      _isAddingArticleInline = false;
    });
    _onDataChangedAutoSave(immediate: true);
  }

  String _getTipoDocumentoNombre() {
    final tipoRaw = (widget.cotizacionExistente?['tipo_documento'] ?? widget.cotizacionExistente?['tipo_venta'] ?? widget.cotizacionExistente?['tipo'] ?? '').toString().toLowerCase();
    if (tipoRaw.contains('cotizac')) {
      return "Cotización";
    } else if (tipoRaw.contains('nota')) {
      return "Nota de Entrega";
    }
    return "Nota de Venta";
  }

  Widget _buildStepper(int activeStep) {
    if (_idCotizacionExistente != null || widget.cotizacionExistente != null) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = Theme.of(context).primaryColor;
    final inactiveBg = isDark ? const Color(0xFF262822) : const Color(0xFFE2E8F0);
    final activeLine = Theme.of(context).primaryColor;
    final inactiveLine = isDark ? Colors.white10 : const Color(0xFFE2E8F0);

    final bool hasClientText = _clienteNombreCtrl.text.trim().isNotEmpty;
    final bool hasItemsAdded = _items.isNotEmpty;

    final bool line1To2Filled = (activeStep >= 2) || hasClientText;
    final bool line2To3Filled = (activeStep >= 3) || hasItemsAdded;

    Widget buildStepItem(int stepNum) {
      final bool isCompletedOrActive = activeStep >= stepNum;
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isCompletedOrActive ? activeColor : inactiveBg,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          stepNum.toString(),
          style: TextStyle(
            color: isCompletedOrActive ? Colors.white : (isDark ? Colors.white38 : const Color(0xFF64748B)),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      );
    }

    Widget buildLine(bool isFilled) {
      return Expanded(
        child: Container(
          height: 3,
          color: isFilled ? activeLine : inactiveLine,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          buildStepItem(1),
          buildLine(line1To2Filled),
          buildStepItem(2),
          buildLine(line2To3Filled),
          buildStepItem(3),
        ],
      ),
    );
  }

  Widget _buildBottomButton(String text, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(27),
            ),
          ),
          onPressed: onPressed,
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_currentStep) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      default:
        return _buildStep1();
    }
  }

  Widget _buildStep1() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final labelColor = isDark ? Colors.white60 : Colors.black.withOpacity(0.45);

    Widget buildCleanField({
      required String label,
      required TextEditingController controller,
      String? hintText,
      TextInputType keyboardType = TextInputType.text,
      ValueChanged<String>? onChanged,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: labelColor,
            ),
          ),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              hintText: hintText,
              hintStyle: GoogleFonts.poppins(fontSize: 16, color: labelColor),
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5842F4), width: 2),
              ),
            ),
            onChanged: onChanged,
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
            children: [
              buildCleanField(
                label: "Cliente / Empresa",
                controller: _clienteNombreCtrl,
                hintText: "",
                onChanged: (val) {
                  _filtrarSugeridosClientes(val);
                  setState(() {
                    _showClientSuggestions = true;
                  });
                },
              ),
              if (_showClientSuggestions && _sugeridosClientes.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _sugeridosClientes.length,
                    itemBuilder: (context, i) {
                      final cli = _sugeridosClientes[i];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ActionChip(
                          backgroundColor: isDark ? const Color(0xFF222834) : const Color(0xFFE8EEFC),
                          side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          label: Text(
                            cli.nombreCompania,
                            style: GoogleFonts.poppins(color: textColor, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          onPressed: () {
                            setState(() {
                              _clienteNombreCtrl.text = cli.nombreCompania;
                              _clienteTelefonoCtrl.text = cli.telefono;
                              _clienteCorreoCtrl.text = cli.correo;
                              _showClientSuggestions = false;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 24),
              buildCleanField(
                label: "Celular",
                controller: _clienteTelefonoCtrl,
                hintText: "",
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 24),
              buildCleanField(
                label: "Email",
                controller: _clienteCorreoCtrl,
                hintText: "",
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        _buildBottomButton("Siguiente", () {
          if (_clienteNombreCtrl.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Por favor ingrese el nombre del cliente"), backgroundColor: Colors.red),
            );
            return;
          }
          setState(() {
            _currentStep = 2;
          });
        }),
      ],
    );
  }

  Future<void> _loadUnidadesMedida() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final rawUnits = await dbHelper.queryAllUnidadesMedida();
      final List<String> unitNames = rawUnits
          .map((u) => u['nombre']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();

      setState(() {
        _unidadesMedida = unitNames;
        if (_unidadesMedida.isNotEmpty && !_unidadesMedida.contains(_seleccionUnidadMedida)) {
          _seleccionUnidadMedida = _unidadesMedida.first;
        } else if (_unidadesMedida.isEmpty) {
          _unidadesMedida = ["Unidad", "Caja", "Paquete", "Metro", "Litro"];
          _seleccionUnidadMedida = "Unidad";
        }
      });
    } catch (e) {
      debugPrint("Error loading units data: $e");
    }
  }

  void _gestionarUnidadesMedida() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCtrl = TextEditingController();
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secTextColor = isDark ? Colors.white54 : const Color(0xFF8C98B6);
    final cardBg = isDark ? const Color(0xFF1E222B) : Colors.white;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    // Fila superior: Input + Botón Añadir
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: textCtrl,
                            style: GoogleFonts.poppins(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                            decoration: InputDecoration(
                              hintText: "Crear nueva medida",
                              hintStyle: GoogleFonts.poppins(
                                color: isDark ? Colors.white38 : const Color(0xFF8C98B6),
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5842F4),
                            foregroundColor: Colors.white,
                            elevation: 4,
                            shadowColor: const Color(0xFF5842F4).withOpacity(0.4),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: () async {
                            final name = textCtrl.text.trim();
                            if (name.isNotEmpty) {
                              if (!_unidadesMedida.contains(name)) {
                                final uuid = "UM_${DateTime.now().millisecondsSinceEpoch}";
                                await DatabaseHelper.instance.insertUnidadMedida({
                                  'nombre': name,
                                  'folderId': uuid,
                                });
                                final allDb = await DatabaseHelper.instance.queryAllUnidadesMedida();
                                final inserted = allDb.firstWhere((element) => element['nombre'] == name);
                                _drive.syncItemToDrive('unidades_medida', Map<String, dynamic>.from(inserted)).then((folderId) async {
                                  if (folderId != null) {
                                    final updated = Map<String, dynamic>.from(inserted)..['folderId'] = folderId;
                                    await DatabaseHelper.instance.updateUnidadMedida(updated);
                                  }
                                  SyncService.instance.syncTable('unidades_medida').catchError((e) {
                                    debugPrint("Sync error: $e");
                                  });
                                });
                                
                                textCtrl.clear();
                                await _loadUnidadesMedida();
                                setState(() {
                                  _seleccionUnidadMedida = name;
                                });
                                Navigator.pop(dialogCtx);
                              } else {
                                setState(() {
                                  _seleccionUnidadMedida = name;
                                });
                                Navigator.pop(dialogCtx);
                              }
                            }
                          },
                          child: Text(
                            "+ Añadir",
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(color: isDark ? Colors.white12 : const Color(0xFFEDF2F7), height: 1),
                    const SizedBox(height: 8),

                    // Lista de unidades
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _unidadesMedida.length,
                        separatorBuilder: (c, i) => Divider(color: isDark ? Colors.white12 : const Color(0xFFEDF2F7), height: 1),
                        itemBuilder: (c, idx) {
                          final unit = _unidadesMedida[idx];
                          final bool isSelected = unit == _seleccionUnidadMedida;
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _seleccionUnidadMedida = unit;
                              });
                              Navigator.pop(dialogCtx);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      unit,
                                      style: GoogleFonts.poppins(
                                        color: isSelected ? const Color(0xFF5842F4) : textColor,
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  // Botón lápiz (editar)
                                  InkWell(
                                    onTap: () {
                                      _editarUnidadMedidaDialog(unit, () async {
                                        await _loadUnidadesMedida();
                                        setDialogState(() {});
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(6.0),
                                      child: Image.asset(
                                        'Iconos/pantalla 4/lapiz.png',
                                        width: 16,
                                        height: 16,
                                        color: secTextColor,
                                        errorBuilder: (_, __, ___) => Icon(Icons.edit_outlined, size: 16, color: secTextColor),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Botón basurero (eliminar)
                                  InkWell(
                                    onTap: () async {
                                      final allDb = await DatabaseHelper.instance.queryAllUnidadesMedida();
                                      final match = allDb.firstWhere((element) => element['nombre'] == unit);
                                      final id = match['id'] as int;
                                      
                                      await DatabaseHelper.instance.deleteUnidadMedida(id);
                                      
                                      SyncService.instance.syncTable('unidades_medida').catchError((e) {
                                        debugPrint("Sync error: $e");
                                      });

                                      await _loadUnidadesMedida();
                                      setDialogState(() {});
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(6.0),
                                      child: Image.asset(
                                        'Iconos/pantalla 4/Recurso 7-1.png',
                                        width: 16,
                                        height: 16,
                                        color: secTextColor,
                                        errorBuilder: (_, __, ___) => Icon(Icons.delete_outline_rounded, size: 18, color: secTextColor),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Botón inferior derecho "Cerrar"
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF2A313D) : const Color(0xFFE8EEFC),
                          foregroundColor: isDark ? Colors.white70 : const Color(0xFF5842F4),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: Text(
                          "Cerrar",
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : const Color(0xFF5842F4),
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
        );
      },
    );
  }

  void _editarUnidadMedidaDialog(String currentName, VoidCallback onUpdated) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCtrl = TextEditingController(text: currentName);
    
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            "Editar Unidad",
            style: GoogleFonts.poppins(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: textCtrl,
            style: GoogleFonts.poppins(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 14),
            decoration: InputDecoration(
              hintText: "Nombre de la Unidad",
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFF5842F4)),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancelar", style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5842F4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                final newName = textCtrl.text.trim();
                if (newName.isNotEmpty && newName != currentName) {
                  final allDb = await DatabaseHelper.instance.queryAllUnidadesMedida();
                  final match = allDb.firstWhere((element) => element['nombre'] == currentName);
                  
                  final updatedRow = Map<String, dynamic>.from(match)..['nombre'] = newName;
                  await DatabaseHelper.instance.updateUnidadMedida(updatedRow);

                  SyncService.instance.syncTable('unidades_medida').catchError((e) {
                    debugPrint("Sync error: $e");
                  });

                  Navigator.pop(ctx);
                  onUpdated();
                }
              },
              child: Text("Guardar", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  List<String> _listaUnidadesMedida = [
    "Unidad",
    "Metros",
    "Caja",
    "Paquete",
    "Litro",
    "Pieza",
    "Juego",
  ];

  Future<void> _cargarUnidadesMedida() async {
    try {
      await SyncService.instance.syncTable('unidades_medida').catchError((_) {});
      final dbHelper = DatabaseHelper.instance;
      final raw = await dbHelper.queryAllUnidadesMedida();
      final names = raw.map((u) => u['nombre']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
      if (names.isNotEmpty && mounted) {
        setState(() {
          _listaUnidadesMedida = names;
          if (!_listaUnidadesMedida.contains(_seleccionUnidadMedida)) {
            _seleccionUnidadMedida = _listaUnidadesMedida.first;
          }
        });
      }
    } catch (e) {
      debugPrint("Error al cargar unidades de medida: $e");
    }
  }

  Future<void> _guardarUnidadesMedida() async {
    // No-op ya que se guarda directamente en base de datos SQLite y sincroniza a la nube
  }

  void _dialogAgregarUnidadMedida(BuildContext ctx, StateSetter setModalState) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final ctrl = TextEditingController();

    showDialog(
      context: ctx,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Nueva Unidad de Medida",
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.poppins(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: "Ej: Rollo, Kg, Docena...",
              hintStyle: GoogleFonts.poppins(color: isDark ? Colors.white30 : Colors.black38),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5842F4), width: 2)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text("CANCELAR", style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5842F4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isNotEmpty) {
                  Navigator.pop(dialogCtx);
                  try {
                    if (!_listaUnidadesMedida.any((u) => u.toLowerCase() == nombre.toLowerCase())) {
                      _listaUnidadesMedida.add(nombre);
                    }
                    _seleccionUnidadMedida = nombre;
                    setModalState(() {});
                    if (mounted) setState(() {});

                    final uuid = "UM_${DateTime.now().millisecondsSinceEpoch}";
                    await DatabaseHelper.instance.insertUnidadMedida({
                      'nombre': nombre,
                      'folderId': uuid,
                    }).catchError((_) => 0);

                    SyncService.instance.syncTable('unidades_medida').catchError((_) {});
                    await _cargarUnidadesMedida();
                    setModalState(() {});
                    if (mounted) setState(() {});
                  } catch (e) {
                    debugPrint("Error guardando unidad: $e");
                  }
                }
              },
              child: Text("GUARDAR", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  void _dialogEditarUnidadMedida(BuildContext ctx, StateSetter setModalState, int index) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final prev = _listaUnidadesMedida[index];
    final ctrl = TextEditingController(text: prev);

    showDialog(
      context: ctx,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Editar Unidad de Medida",
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.poppins(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5842F4), width: 2)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text("CANCELAR", style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5842F4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isNotEmpty) {
                  Navigator.pop(dialogCtx);
                  try {
                    _listaUnidadesMedida[index] = nombre;
                    if (_seleccionUnidadMedida.toLowerCase() == prev.toLowerCase()) {
                      _seleccionUnidadMedida = nombre;
                    }
                    setModalState(() {});
                    if (mounted) setState(() {});

                    final db = await DatabaseHelper.instance.database;
                    final raw = await db.query('unidades_medida', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [prev.toLowerCase()], limit: 1);
                    if (raw.isNotEmpty) {
                      final id = raw.first['id'] as int;
                      await DatabaseHelper.instance.updateUnidadMedida({
                        'id': id,
                        'nombre': nombre,
                        'folderId': raw.first['folderId'] ?? "UM_${DateTime.now().millisecondsSinceEpoch}",
                      }).catchError((_) => 0);
                    } else {
                      await DatabaseHelper.instance.insertUnidadMedida({
                        'nombre': nombre,
                        'folderId': "UM_${DateTime.now().millisecondsSinceEpoch}",
                      }).catchError((_) => 0);
                    }
                    SyncService.instance.syncTable('unidades_medida').catchError((_) {});
                    await _cargarUnidadesMedida();
                    setModalState(() {});
                    if (mounted) setState(() {});
                  } catch (e) {
                    debugPrint("Error editando unidad: $e");
                  }
                }
              },
              child: Text("ACTUALIZAR", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  void _eliminarUnidadMedida(int index, StateSetter setModalState) async {
    if (_listaUnidadesMedida.length <= 1) return;
    final item = _listaUnidadesMedida[index];
    try {
      _listaUnidadesMedida.removeAt(index);
      if (_seleccionUnidadMedida.toLowerCase() == item.toLowerCase()) {
        _seleccionUnidadMedida = _listaUnidadesMedida.first;
      }
      setModalState(() {});
      if (mounted) setState(() {});

      final db = await DatabaseHelper.instance.database;
      final raw = await db.query('unidades_medida', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [item.toLowerCase()], limit: 1);
      if (raw.isNotEmpty) {
        final id = raw.first['id'] as int;
        await DatabaseHelper.instance.deleteUnidadMedida(id).catchError((_) => 0);
      }
      SyncService.instance.syncTable('unidades_medida').catchError((_) {});
      await _cargarUnidadesMedida();
      setModalState(() {});
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error eliminando unidad: $e");
    }
  }

  void _mostrarSelectorUnidadMedida() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _SelectorUnidadMedidaSheet(
          seleccionInicial: _seleccionUnidadMedida,
          onSeleccionar: (val) {
            setState(() {
              _seleccionUnidadMedida = val;
            });
          },
        );
      },
    );
  }

  Widget _buildBuscarProductoScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final labelColor = isDark ? Colors.white.withOpacity(0.55) : Colors.black.withOpacity(0.45);

    final String currentTypedName = _prodNombreCtrl.text.trim();
    Articulo? articuloEnInventario = _selectedCatalogArticulo;
    if (articuloEnInventario == null && currentTypedName.isNotEmpty) {
      try {
        articuloEnInventario = _catalogArticulos.firstWhere(
          (a) => a.nombre.trim().toLowerCase() == currentTypedName.toLowerCase(),
        );
      } catch (_) {
        articuloEnInventario = null;
      }
    }

    final brandColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 56,
        leading: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: NovaledThickIcon(
                assetPath: 'Iconos/Nuevo/nuevo/2/atras.png',
                size: 24,
                color: textColor,
                fallbackIcon: Icons.arrow_back,
              ),
              onPressed: () {
                setState(() {
                  _isSearchingProduct = false;
                  _editingItemIndex = null;
                });
              },
            ),
          ),
        ),
        title: Text(
          _editingItemIndex != null ? "Editar producto" : "Añadir producto",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: textColor,
            fontSize: 19,
          ),
        ),
        actions: [
          if (articuloEnInventario != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                icon: NovaledThickIcon(
                  assetPath: 'Iconos/Nuevo/nuevo/2/borrar4.png',
                  size: 22,
                  color: const Color(0xFFEF4444),
                  fallbackIcon: Icons.delete_outline_rounded,
                ),
                onPressed: () => _mostrarDialogoEliminarArticuloInventario(articuloEnInventario!),
              ),
            ),
          _buildPurpleCheckCircle(
            onTap: () {
              final nombre = _prodNombreCtrl.text.trim();
              final double precio = double.tryParse(_prodPrecioCtrl.text.trim()) ?? 0.0;
              final double cant = double.tryParse(_prodCantCtrl.text.trim()) ?? 1.0;
              if (nombre.isNotEmpty) {
                final existingArt = (_editingItemIndex != null && _editingItemIndex! < _items.length)
                    ? _items[_editingItemIndex!].articulo
                    : _selectedCatalogArticulo;
                final art = Articulo(
                  id: existingArt?.id,
                  nombre: nombre,
                  precio: precio,
                  descripcion: existingArt?.descripcion ?? "",
                  unidad: _seleccionUnidadMedida.isNotEmpty ? _seleccionUnidadMedida : (existingArt?.unidad.isNotEmpty == true ? existingArt!.unidad : "Unidad"),
                  unidadDetalle: existingArt?.unidadDetalle ?? "",
                  imagen: existingArt?.imagen,
                  stockJson: existingArt?.stockJson,
                  folderId: existingArt?.folderId,
                  finalArtId: existingArt?.finalArtId,
                  proveedor: existingArt?.proveedor ?? 'Novaled',
                  familia: existingArt?.familia ?? '',
                  subcategoria: existingArt?.subcategoria ?? '',
                  fecha: existingArt?.fecha ?? DateTime.now().toIso8601String().substring(0, 10),
                );
                final item = ItemCotizacion(
                  articulo: art,
                  precioOriginal: (_editingItemIndex != null && _editingItemIndex! < _items.length)
                      ? _items[_editingItemIndex!].precioOriginal
                      : (existingArt?.precio ?? precio),
                  cantidad: cant.toInt(),
                );
                setState(() {
                  if (_editingItemIndex != null && _editingItemIndex! < _items.length) {
                    _items[_editingItemIndex!] = item;
                    _editingItemIndex = null;
                  } else {
                    _items.add(item);
                  }
                  _prodNombreCtrl.clear();
                  _prodPrecioCtrl.clear();
                  _prodCantCtrl.clear();
                  _selectedCatalogArticulo = null;
                  _isSearchingProduct = false;
                  _isSaved = false;
                });
                _onDataChangedAutoSave(immediate: true);

                // Registrar en catálogo / inventario de la empresa si no existe y sincronizar
                () async {
                  try {
                    final db = await DatabaseHelper.instance.database;
                    final existing = await db.query('articulos', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [nombre.toLowerCase()], limit: 1);
                    if (existing.isEmpty) {
                      final uuid = "ART_${DateTime.now().millisecondsSinceEpoch}_${nombre.hashCode.abs()}";
                      await DatabaseHelper.instance.insertArticulo({
                        'nombre': nombre,
                        'precio': precio,
                        'descripcion': '',
                        'unidad': _seleccionUnidadMedida.isNotEmpty ? _seleccionUnidadMedida : 'Unidad',
                        'folderId': uuid,
                      });
                      await SyncService.instance.syncTable('articulos').catchError((_) {});
                    }
                  } catch (e) {
                    debugPrint("Error guardando artículo en inventario: $e");
                  }
                }();
              } else {
                setState(() {
                  _isSearchingProduct = false;
                  _editingItemIndex = null;
                });
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Nombre del artículo",
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  TextField(
                    controller: _prodNombreCtrl,
                    cursorColor: brandColor,
                    onChanged: (val) {
                      _filterProdSuggestions(val);
                    },
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.only(top: 2, bottom: 4),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: brandColor, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Bs.",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: labelColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            TextField(
                              controller: _prodPrecioCtrl,
                              cursorColor: brandColor,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.only(top: 2, bottom: 4),
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: brandColor, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Cantidad",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: labelColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            TextField(
                              controller: _prodCantCtrl,
                              cursorColor: brandColor,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: "1",
                                hintStyle: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                                ),
                                contentPadding: const EdgeInsets.only(top: 2, bottom: 4),
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: brandColor, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "U. Medida",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: labelColor,
                              ),
                            ),
                            InkWell(
                              onTap: _mostrarSelectorUnidadMedida,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _seleccionUnidadMedida.isNotEmpty ? _seleccionUnidadMedida : "Metros",
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: textColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: textColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), height: 1),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: (_filtradosProd.isEmpty ? _catalogArticulos : _filtradosProd).length,
                itemBuilder: (context, i) {
                  final list = _filtradosProd.isEmpty ? _catalogArticulos : _filtradosProd;
                  final a = list[i];
                  return InkWell(
                    onTap: () {
                      final double cant = double.tryParse(_prodCantCtrl.text.trim()) ?? 1.0;
                      final int cantidadToAdd = cant <= 0 ? 1 : cant.toInt();

                      setState(() {
                        if (_editingItemIndex != null && _editingItemIndex! < _items.length) {
                          _items[_editingItemIndex!] = ItemCotizacion(
                            articulo: a,
                            precioOriginal: a.precio,
                            cantidad: cantidadToAdd,
                          );
                          _editingItemIndex = null;
                        } else {
                          final existingIndex = _items.indexWhere(
                            (it) => it.articulo.nombre.trim().toLowerCase() == a.nombre.trim().toLowerCase(),
                          );
                          if (existingIndex != -1) {
                            _items[existingIndex] = _items[existingIndex].copyWith(
                              cantidad: _items[existingIndex].cantidad + cantidadToAdd,
                            );
                          } else {
                            _items.add(ItemCotizacion(
                              articulo: a,
                              precioOriginal: a.precio,
                              cantidad: cantidadToAdd,
                            ));
                          }
                        }
                        _isSaved = false;
                        _prodNombreCtrl.clear();
                        _prodPrecioCtrl.clear();
                        _prodCantCtrl.clear();
                        _selectedCatalogArticulo = null;
                        _isSearchingProduct = false;
                        _isAddingArticleInline = false;
                      });
                      _onDataChangedAutoSave();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              a.nombre,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "Bs. ${a.precio.toStringAsFixed(0)}   ${a.unidad.isNotEmpty ? a.unidad : "Unidad"}",
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF909CB5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: NovaledThickIcon(
                              assetPath: 'Iconos/Nuevo/nuevo/2/borrar4.png',
                              size: 18,
                              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                              fallbackIcon: Icons.delete_outline_rounded,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onPressed: () => _mostrarDialogoEliminarArticuloInventario(a),
                          ),
                        ],
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

  void _mostrarDialogoEliminarArticuloInventario(Articulo articulo) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E222B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secTextColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Eliminar del inventario",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: secTextColor,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(text: "¿Estás seguro de que deseas eliminar "),
                      TextSpan(
                        text: '"${articulo.nombre}"',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      const TextSpan(
                        text: '?\n\nEste producto se borrará de forma permanente del catálogo e inventario.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          "Cancelar",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            color: textColor,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          if (articulo.id != null) {
                            await DatabaseHelper.instance.deleteArticulo(articulo.id!);
                          } else if (articulo.folderId != null) {
                            final dbId = await DatabaseHelper.instance.getArticuloIdByFolderId(articulo.folderId!);
                            if (dbId != null) {
                              await DatabaseHelper.instance.deleteArticulo(dbId);
                            }
                          }
                          await _loadCatalogData();
                          if (mounted) {
                            setState(() {
                              _selectedCatalogArticulo = null;
                              _prodNombreCtrl.clear();
                              _prodPrecioCtrl.clear();
                              _prodCantCtrl.clear();
                              _filterProdSuggestions('');
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        "\"${articulo.nombre}\" eliminado del inventario",
                                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: const Color(0xFFEF4444),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          "Eliminar",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStep2() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secTextColor = isDark ? Colors.white54 : const Color(0xFF8C98B6);
    final containerFill = isDark ? const Color(0xFF222834) : const Color(0xFFE8EEFC);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            children: [
              // Case A: Formulario de edición/configuración de artículo (Paso 2b)
              if (_isAddingArticleInline || _editingItemIndex != null) ...[
                // Campo 1: Nombre del artículo
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Nombre del artículo",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: secTextColor,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isSearchingProduct = true;
                        });
                      },
                      child: AbsorbPointer(
                        child: TextField(
                          controller: _prodNombreCtrl,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF5842F4), width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Fila de 3 columnas: Bs. | Cantidad | U. Medida
                Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Col 1: Bs.
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Bs.",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: secTextColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _prodPrecioCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Col 2: Cantidad (- X +)
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Cantidad",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: secTextColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      final current = int.tryParse(_prodCantCtrl.text) ?? 1;
                                      if (current > 1) {
                                        setState(() {
                                          _prodCantCtrl.text = (current - 1).toString();
                                        });
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                      child: Image.asset(
                                        'Iconos/pantalla 4/menos.png',
                                        width: 15,
                                        height: 15,
                                        color: secTextColor,
                                        errorBuilder: (_, __, ___) => Icon(Icons.remove, size: 16, color: secTextColor),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    child: TextField(
                                      controller: _prodCantCtrl,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                      ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                      ),
                                      onChanged: (val) {
                                        if (val.isEmpty) {
                                          // _prodCantCtrl.text = "1";
                                          _prodCantCtrl.selection = TextSelection.fromPosition(
                                            TextPosition(offset: _prodCantCtrl.text.length),
                                          );
                                        }
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      final current = int.tryParse(_prodCantCtrl.text) ?? 1;
                                      setState(() {
                                        _prodCantCtrl.text = (current + 1).toString();
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                      child: Image.asset(
                                        'Iconos/pantalla 4/mas.png',
                                        width: 15,
                                        height: 15,
                                        color: secTextColor,
                                        errorBuilder: (_, __, ___) => Icon(Icons.add, size: 16, color: secTextColor),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Col 3: U. Medida
                        Expanded(
                          flex: 4,
                          child: InkWell(
                            onTap: _gestionarUnidadesMedida,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "U. Medida",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: secTextColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _seleccionUnidadMedida,
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: textColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Image.asset(
                                      'Iconos/pantalla 4/el derecha.png',
                                      width: 10,
                                      height: 10,
                                      color: textColor,
                                      errorBuilder: (_, __, ___) => Icon(Icons.chevron_right, size: 16, color: textColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.only(top: 8),
                      color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                    ),
                  ],
                ),
                const SizedBox(height: 32),              ],

              // Listado de Tarjetas de artículos añadidos (Paso 2c)
              if (_items.isNotEmpty)
                Column(
                  children: List.generate(_items.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildArticleCard(
                        item: _items[i],
                        index: i,
                        isDark: isDark,
                        textColor: textColor,
                        labelColor: secTextColor,
                      ),
                    );
                  }),
                ),
            ],
          ),
        ),

        // Barra de Botones Inferior Fija (Paso 2)
        Builder(
          builder: (context) {
            // Caso 1: Formulario de adición/edición activo -> Botón de guardar en la parte inferior
            if (_isAddingArticleInline || _editingItemIndex != null) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _saveItemInline,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'Iconos/pantalla 4/mas.png',
                          width: 14,
                          height: 14,
                          color: Colors.white,
                          errorBuilder: (_, __, ___) => const Icon(Icons.add, size: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _editingItemIndex != null ? "Guardar cambios" : "Guardar y añadir nuevo",
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Caso 2: Sin items aún -> Botón + Añadir artículo a todo el ancho
            if (_items.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _isAddingArticleInline = true;
                        _isSearchingProduct = true;
                      });
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'Iconos/pantalla 4/mas.png',
                          width: 14,
                          height: 14,
                          color: Colors.white,
                          errorBuilder: (_, __, ___) => const Icon(Icons.add, size: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Añadir artículo",
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Caso 3: Con items agregados -> Fila con (+ Añadir artículo) y (Siguiente)
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            _isAddingArticleInline = true;
                            _isSearchingProduct = true;
                          });
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'Iconos/pantalla 4/mas.png',
                              width: 14,
                              height: 14,
                              color: Colors.white,
                              errorBuilder: (_, __, ___) => const Icon(Icons.add, size: 16, color: Colors.white),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "Añadir",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5842F4),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            _currentStep = 3;
                          });
                        },
                        child: Text(
                          "Siguiente",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  bool get isPuntoDeVenta {
    if (widget.tipoVenta == 'cotizacion') return false;
    return widget.isDirectoPorCobrar ||
        widget.tipoVenta == 'punto_venta' ||
        widget.cotizacionExistente?['tipo_venta'] == 'punto_venta';
  }

  String get _computedTituloDocumento {
    if (isPuntoDeVenta) {
      return _tipoDocumentoSeleccionado == 'nota_entrega' ? "NOTA DE ENTREGA" : "NOTA DE VENTA";
    }
    return "COTIZACIÓN";
  }

  String get _computedTituloPantalla {
    if (isPuntoDeVenta) {
      return _tipoDocumentoSeleccionado == 'nota_entrega' ? "Nota de entrega" : "Nota de Venta";
    }
    return "Cotización lista";
  }

  String _computedFilenamePdf(String formattedId) {
    if (isPuntoDeVenta) {
      return _tipoDocumentoSeleccionado == 'nota_entrega' 
          ? "Nota_de_entrega_NE-$formattedId.pdf" 
          : "Nota_de_venta_NV-$formattedId.pdf";
    }
    return "Cotizacion_COT-$formattedId.pdf";
  }

  String _computedFilenameWord(String formattedId) {
    if (isPuntoDeVenta) {
      return _tipoDocumentoSeleccionado == 'nota_entrega' 
          ? "Nota_de_entrega_NE-$formattedId.docx" 
          : "Nota_de_venta_NV-$formattedId.docx";
    }
    return "Cotizacion_COT-$formattedId.docx";
  }

  String get _computedReturnButtonText {
    final bool isPuntoDeVenta = widget.tipoVenta == 'punto_venta' || widget.cotizacionExistente?['tipo_venta'] == 'punto_venta' || widget.isDirectoPorCobrar;
    if (isPuntoDeVenta) {
      return "Volver a Punto de Venta";
    }
    return "Volver a cotizaciones";
  }

  Future<Uint8List> _obtenerPdfBytes() async {
    int? previewId = _displayId;
    if (previewId == null) {
      final all = await DatabaseHelper.instance.queryAllCotizaciones();
      previewId = all.length + 1;
    }
    return await PdfService.generateCotizacionBytes(
      clienteNombre: _clienteNombreCtrl.text.trim(),
      items: _items,
      subtotalOriginal: _subtotalOriginal,
      ahorroItems: _ahorroTotalItems,
      descuentoGlobal: _montoDescuento,
      total: _total,
      notas: _notasController.text,
      terminos: _terminosController.text,
      docId: previewId,
      incluyeFirmaEmpresa: _incluyeFirmaEmpresa,
      incluyeFirmaCliente: _incluyeFirmaCliente,
      mostrarAhorro: _mostrarAhorro,
      mostrarTerminos: _mostrarTerminos,
      isColor: _isColor,
      fecha: _fechaDocumento,
      tituloDocumento: _computedTituloDocumento,
      sucursal: _sucursalSeleccionada ?? (_listaSucursales.isNotEmpty ? _listaSucursales.first : ''),
      vendedor: _vendedorSeleccionado ?? _vendedorOriginal ?? (Session().userName ?? ''),
    );
  }

  Future<void> _handleGenerarCotizacion() async {
    final success = await _guardarCotizacion();
    if (success && mounted) {
      NovaledToast.show(
        context,
        _tipoDocumentoSeleccionado == 'nota_entrega'
            ? "Se generó la nota de entrega"
            : (widget.isDirectoPorCobrar ? "Se generó la nota de venta" : "Se generó la cotización"),
      );
      setState(() {
        _isShowingSuccessAnimation = true;
      });
    }
  }

  Widget _buildSuccessAnimationScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 56,
        leading: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Image.asset(
                'Iconos/Nuevo/nuevo/3/atras.png',
                width: 20,
                height: 20,
                color: textColor,
                errorBuilder: (_, __, ___) => Icon(Icons.arrow_back, color: textColor),
              ),
              onPressed: () {
                setState(() {
                  _isShowingSuccessAnimation = false;
                });
              },
            ),
          ),
        ),
        title: Text(
          "Vista previa",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: textColor,
            fontSize: 19,
          ),
        ),
        actions: [
          IconButton(
            icon: Image.asset(
              'Iconos/Nuevo/nuevo/3/impresiones.png',
              width: 22,
              height: 22,
              color: textColor,
              errorBuilder: (_, __, ___) => Icon(Icons.print_outlined, color: textColor),
            ),
            onPressed: () async {
              final bytes = await _obtenerPdfBytes();
              await Printing.layoutPdf(onLayout: (format) async => bytes);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Instant zoomable Edge-to-Edge PDF Preview
            Expanded(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: PdfPreview(
                  build: (format) => _obtenerPdfBytes(),
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

            // Compact 44px action buttons: Descargar & Compartir (higher up)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCircleActionButton(
                    iconAsset: 'Iconos/Nuevo/nuevo/3/descargar.png',
                    label: "Descargar",
                    onTap: () => _descargarComoPDF(),
                    isDark: isDark,
                  ),
                  _buildCircleActionButton(
                    iconAsset: 'Iconos/Nuevo/nuevo/3/compartir.png',
                    label: "Compartir",
                    onTap: () async {
                      final bytes = await _obtenerPdfBytes();
                      final int formattedId = _displayId ?? 1;
                      await Printing.sharePdf(
                        bytes: bytes,
                        filename: _computedFilenamePdf(formattedId.toString().padLeft(5, '0')),
                      );
                    },
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleActionButton({
    required String iconAsset,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF22251F) : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Image.asset(
                iconAsset,
                width: 20,
                height: 20,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                errorBuilder: (_, __, ___) => Icon(
                  iconAsset.contains('descargar') ? Icons.file_download_outlined : Icons.share_outlined,
                  size: 20,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white70 : const Color(0xFF909CB5),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSoloFecha(String? fechaStr) {
    if (fechaStr == null || fechaStr.trim().isEmpty) {
      final now = DateTime.now();
      return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    }
    return fechaStr.split(' ')[0].split('T')[0].trim();
  }

  Future<void> _seleccionarFechaResumen() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(primary: Theme.of(context).primaryColor)
                : ColorScheme.light(primary: Theme.of(context).primaryColor),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _fechaDocumento = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
        _onDataChangedAutoSave();
      });
    }
  }

  Widget _buildStep3() {
    _sanitizeControllerValues();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secTextColor = isDark ? Colors.white54 : const Color(0xFF8C98B6);
    final containerFill = isDark ? const Color(0xFF1E222B) : Theme.of(context).scaffoldBackgroundColor;

    final String fechaActual = _formatSoloFecha(_fechaDocumento);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 16.0),
            children: [
              // 0. Toggle Pill Switch [ Proforma ] | [ Nota de entrega ] (solo en Punto de Venta)
              if (isPuntoDeVenta && (_clienteNombreCtrl.text.trim().isNotEmpty || _items.isNotEmpty)) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E222B) : Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _tipoDocumentoSeleccionado = 'proforma';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _tipoDocumentoSeleccionado == 'proforma'
                                  ? Theme.of(context).primaryColor
                                  : (isDark ? Colors.transparent : Colors.white),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: _tipoDocumentoSeleccionado != 'proforma' && !isDark
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Nota de Venta",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _tipoDocumentoSeleccionado == 'proforma'
                                    ? Colors.white
                                    : (isDark ? secTextColor : Theme.of(context).primaryColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _tipoDocumentoSeleccionado = 'nota_entrega';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _tipoDocumentoSeleccionado == 'nota_entrega'
                                  ? Theme.of(context).primaryColor
                                  : (isDark ? Colors.transparent : Colors.white),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: _tipoDocumentoSeleccionado != 'nota_entrega' && !isDark
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Nota de entrega",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _tipoDocumentoSeleccionado == 'nota_entrega'
                                    ? Colors.white
                                    : (isDark ? secTextColor : Theme.of(context).primaryColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 1. Cliente / Empresa (Editable)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Cliente / Empresa",
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400, color: secTextColor),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _clienteNombreCtrl,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: textColor),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      hintText: "",
                      hintStyle: GoogleFonts.poppins(fontSize: 16, color: secTextColor),
                      border: InputBorder.none,
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5842F4), width: 2)),
                    ),
                    onChanged: (v) => setState(() {}),
                  ),
                  const SizedBox(height: 18),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Celular",
                              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400, color: secTextColor),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _clienteTelefonoCtrl,
                              keyboardType: TextInputType.phone,
                              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: textColor),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                hintText: "",
                                hintStyle: GoogleFonts.poppins(fontSize: 16, color: secTextColor),
                                border: InputBorder.none,
                                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5842F4), width: 2)),
                              ),
                              onChanged: (v) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "Fecha",
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400, color: secTextColor),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: _seleccionarFechaResumen,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  fechaActual,
                                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: textColor),
                                ),
                                const SizedBox(width: 6),
                                Image.asset(
                                  'Iconos/pantalla 4/lapiz.png',
                                  width: 14,
                                  height: 14,
                                  color: secTextColor,
                                  errorBuilder: (_, __, ___) => Icon(Icons.edit, size: 14, color: secTextColor),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  Text(
                    "Email",
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400, color: secTextColor),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _clienteCorreoCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: textColor),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      hintText: "",
                      hintStyle: GoogleFonts.poppins(fontSize: 16, color: secTextColor),
                      border: InputBorder.none,
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5842F4), width: 2)),
                    ),
                    onChanged: (v) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Container(height: 1, color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                ],
              ),
              const SizedBox(height: 20),

              // 2. Formulario de edición inline (si está activo)
              if (_isAddingArticleInline || _editingItemIndex != null) ...[
                // Campo 1: Nombre del artículo
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Nombre del artículo",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: secTextColor,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isSearchingProduct = true;
                        });
                      },
                      child: AbsorbPointer(
                        child: TextField(
                          controller: _prodNombreCtrl,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF5842F4), width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Fila de 3 columnas: Bs. | Cantidad | U. Medida
                Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Col 1: Bs.
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Bs.",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: secTextColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _prodPrecioCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Col 2: Cantidad (- X +)
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Cantidad",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: secTextColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      final current = int.tryParse(_prodCantCtrl.text) ?? 1;
                                      if (current > 1) {
                                        setState(() {
                                          _prodCantCtrl.text = (current - 1).toString();
                                        });
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                      child: Image.asset(
                                        'Iconos/pantalla 4/menos.png',
                                        width: 15,
                                        height: 15,
                                        color: secTextColor,
                                        errorBuilder: (_, __, ___) => Icon(Icons.remove, size: 16, color: secTextColor),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    child: TextField(
                                      controller: _prodCantCtrl,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                      ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                      ),
                                      onChanged: (val) {
                                        if (val.isEmpty) {
                                          // _prodCantCtrl.text = "1";
                                          _prodCantCtrl.selection = TextSelection.fromPosition(
                                            TextPosition(offset: _prodCantCtrl.text.length),
                                          );
                                        }
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      final current = int.tryParse(_prodCantCtrl.text) ?? 1;
                                      setState(() {
                                        _prodCantCtrl.text = (current + 1).toString();
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                      child: Image.asset(
                                        'Iconos/pantalla 4/mas.png',
                                        width: 15,
                                        height: 15,
                                        color: secTextColor,
                                        errorBuilder: (_, __, ___) => Icon(Icons.add, size: 16, color: secTextColor),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Col 3: U. Medida
                        Expanded(
                          flex: 4,
                          child: InkWell(
                            onTap: _gestionarUnidadesMedida,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "U. Medida",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: secTextColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _seleccionUnidadMedida,
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: textColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Image.asset(
                                      'Iconos/pantalla 4/el derecha.png',
                                      width: 10,
                                      height: 10,
                                      color: textColor,
                                      errorBuilder: (_, __, ___) => Icon(Icons.chevron_right, size: 16, color: textColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.only(top: 8),
                      color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Botón Guardar
                GestureDetector(
                  onTap: _saveItemInline,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'Iconos/pantalla 4/mas.png',
                          width: 14,
                          height: 14,
                          color: Colors.white,
                          errorBuilder: (_, __, ___) => const Icon(Icons.add, size: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _editingItemIndex != null ? "Guardar cambios" : "Guardar y añadir nuevo",
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // 3. Artículos List
              Column(
                children: List.generate(_items.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: _buildArticleCard(
                      item: _items[i],
                      index: i,
                      isDark: isDark,
                      textColor: textColor,
                      labelColor: secTextColor,
                    ),
                  );
                }),
              ),

              // Botón "+ Añadir artículo" en Resumen (si no hay formulario activo)
              if (!_isAddingArticleInline && _editingItemIndex == null)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _editingItemIndex = null;
                      _isAddingArticleInline = true;
                      _isSearchingProduct = true;
                    });
                  },
                  child: Container(
                    height: 60,
                    margin: const EdgeInsets.only(top: 8, bottom: 20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'Iconos/pantalla 4/mas.png',
                          width: 14,
                          height: 14,
                          color: Colors.white,
                          errorBuilder: (_, __, ___) => const Icon(Icons.add, size: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Añadir artículo",
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    "Total Bs. ${_total.toStringAsFixed(2)}",
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
              const SizedBox(height: 20),

              // 3. Options Section (Firma y sello, Notas adicionales)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _incluyeFirmaEmpresa = !_incluyeFirmaEmpresa;
                      });
                      _onDataChangedAutoSave();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Incluir sello",
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                          Icon(
                            _incluyeFirmaEmpresa ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                            color: _incluyeFirmaEmpresa ? Theme.of(context).primaryColor : (isDark ? Colors.white30 : const Color(0xFFCBD5E1)),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _mostrarNotas = !_mostrarNotas;
                        _mostrarTerminos = _mostrarNotas;
                        if (_mostrarNotas && _notasController.text.trim().isEmpty) {
                          _notasController.text = "- Garantía: Según especificaciones del fabricante.\n- Textos";
                        }
                      });
                      _onDataChangedAutoSave();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Notas adicionales",
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                          Icon(
                            _mostrarNotas ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                            color: _mostrarNotas ? Theme.of(context).primaryColor : (isDark ? Colors.white30 : const Color(0xFFCBD5E1)),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_mostrarNotas) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF262822) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _notasController,
                        maxLines: null,
                        minLines: 3,
                        keyboardType: TextInputType.multiline,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                          height: 1.6,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          hintText: "- Garantía: Según especificaciones del fabricante.\n- Textos",
                          hintStyle: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // 4. Estado de pago Section (solo en Punto de Venta)
              if (isPuntoDeVenta) ...[
                const SizedBox(height: 12),
                Container(height: 1, color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                const SizedBox(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Estado de pago",
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Row 1: Por pagar / Pagado
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isPorPagar = true;
                              });
                            },
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: _isPorPagar ? Theme.of(context).primaryColor : (isDark ? const Color(0xFF222834) : const Color(0xFFE8EEFC)),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "\$ Por pagar",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _isPorPagar ? Colors.white : secTextColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isPorPagar = false;
                              });
                            },
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: !_isPorPagar ? Theme.of(context).primaryColor : (isDark ? const Color(0xFF222834) : Colors.white),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check, size: 16, color: !_isPorPagar ? Colors.white : secTextColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Pagado",
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: !_isPorPagar ? Colors.white : secTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Row 2: QR / Transferencia / Efectivo
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _metodoPagoSeleccionado = "QR"),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: _metodoPagoSeleccionado == "QR"
                                    ? const Color(0xFF5842F4).withOpacity(0.7)
                                    : (isDark ? const Color(0xFF222834) : const Color(0xFFE8EEFC)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "QR",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _metodoPagoSeleccionado == "QR" ? Colors.white : secTextColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _metodoPagoSeleccionado = "Transferencia"),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: _metodoPagoSeleccionado == "Transferencia"
                                    ? const Color(0xFF5842F4).withOpacity(0.7)
                                    : (isDark ? const Color(0xFF222834) : const Color(0xFFE8EEFC)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "Transferencia",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _metodoPagoSeleccionado == "Transferencia" ? Colors.white : secTextColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _metodoPagoSeleccionado = "Efectivo"),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: _metodoPagoSeleccionado == "Efectivo"
                                    ? const Color(0xFF5842F4).withOpacity(0.7)
                                    : (isDark ? const Color(0xFF222834) : const Color(0xFFE8EEFC)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "Efectivo",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _metodoPagoSeleccionado == "Efectivo" ? Colors.white : secTextColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
        _buildBottomButton(
          (_idCotizacionExistente != null || widget.cotizacionExistente != null)
              ? "Actualizar y guardar"
              : "Generar cotización",
          _handleGenerarCotizacion,
        ),
      ],
    );
  }

  void _cargarCotizacion(Map<String, dynamic> data) {
    _idCotizacionExistente = data['id'];
    _uuid = data['uuid']?.toString();
    final rawClient = (data['clienteNombre'] ?? "").toString().trim();
    if (rawClient.toLowerCase() == 'sin cliente' ||
        rawClient.toLowerCase() == 'sin cliente asignado' ||
        rawClient.toLowerCase() == 'cliente / empresa' ||
        rawClient.toLowerCase() == 'nombre / empresa') {
      _clienteNombreCtrl.text = "";
    } else {
      _clienteNombreCtrl.text = rawClient;
    }
    _descuentoPorcentaje = (data['descuentoPorcentaje'] as num?)?.toDouble() ?? 0.0;
    _notasController.text = data['notas'] ?? "";
    _terminosController.text = data['terminos'] ?? "";
    _incluyeFirmaEmpresa = (data['incluyeFirmaEmpresa'] ?? 0) == 1;
    _incluyeFirmaCliente = (data['incluyeFirmaCliente'] ?? 0) == 1;
    _mostrarTerminos = (data['mostrarTerminos'] ?? 1) == 1;
    _mostrarAhorro = (data['mostrarAhorro'] ?? 0) == 1;
    _fechaDocumento = data['fecha'];
    _estado = data['estado']?.toString() ?? 'pendiente';
    _comprobado = data['comprobado'] as int? ?? 0;
    _mostrarNotas = _notasController.text.trim().isNotEmpty;
    _vendedorOriginal = data['vendedor']?.toString();
    if (data['sucursal'] != null && data['sucursal'].toString().trim().isNotEmpty && data['sucursal'].toString() != 'null') {
      _sucursalSeleccionada = data['sucursal'].toString().trim();
    }
    if (data['vendedor'] != null && data['vendedor'].toString().trim().isNotEmpty && data['vendedor'].toString() != 'null') {
      _vendedorSeleccionado = data['vendedor'].toString().trim();
    }

    if (isPuntoDeVenta) {
      final rawTipoDoc = (data['tipo_documento'] ?? data['tipo'] ?? '').toString().toLowerCase();
      if (rawTipoDoc.contains('nota')) {
        _tipoDocumentoSeleccionado = 'nota_entrega';
      } else {
        _tipoDocumentoSeleccionado = 'proforma';
      }
    } else {
      _tipoDocumentoSeleccionado = 'cotizacion';
    }
    if (data['estado_pago'] != null) {
      _isPorPagar = data['estado_pago'] == 'por_cobrar';
    }
    if (data['metodo_pago'] != null && data['metodo_pago'].toString().isNotEmpty) {
      _metodoPagoSeleccionado = data['metodo_pago'].toString();
    }
    if (data['comprobante_img'] != null && data['comprobante_img'].toString().isNotEmpty) {
      final val = data['comprobante_img'].toString().trim();
      final isImg = val.startsWith('/') || 
                    val.startsWith('http') || 
                    val.contains('COMP_') || 
                    val.contains('ART_') || 
                    val.contains('comprobante') || 
                    val.contains('picker') || 
                    val.contains('image') || 
                    val.toLowerCase().endsWith('.jpg') || 
                    val.toLowerCase().endsWith('.jpeg') || 
                    val.toLowerCase().endsWith('.png') || 
                    val.toLowerCase().endsWith('.webp');
      if (isImg) {
        _comprobanteImgPath = val;
      } else {
        _numComprobanteController.text = val;
      }
    }
    final mpLower = (_metodoPagoSeleccionado ?? '').toLowerCase();
    if (_isPorPagar) {
      _selectedEstadoPagoTab = 3;
    } else if (mpLower.contains('qr') || (_comprobanteImgPath != null && _comprobanteImgPath!.isNotEmpty)) {
      _selectedEstadoPagoTab = 1;
      _metodoPagoSeleccionado = "QR";
    } else if (mpLower.contains('transf') || mpLower.contains('banco')) {
      _selectedEstadoPagoTab = 2;
      _metodoPagoSeleccionado = "Transferencia";
    } else {
      _selectedEstadoPagoTab = 0;
      _metodoPagoSeleccionado = "Efectivo";
    }

    _sanitizeControllerValues();

    final List<dynamic> itemsList = jsonDecode(data['itemsJson']);
    _items.clear();
    for (var itemMap in itemsList) {
      _items.add(ItemCotizacion.fromMap(itemMap));
    }
    _isSaved = true; // Ya existe en la BD
  }

  double get _subtotal => _items.fold(0, (sum, item) => sum + item.total);
  double get _ahorroTotalItems => _items.fold(0, (sum, item) => sum + item.ahorro);
  double get _subtotalOriginal => _items.fold(0, (sum, item) => sum + item.totalOriginal);
  double get _montoDescuento => _subtotal * (_descuentoPorcentaje / 100);
  double get _total => _subtotal - _montoDescuento;

  Future<void> _seleccionarImagenCotizacionFlash(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      List<XFile> initialImages = [];

      if (source == ImageSource.gallery) {
        final List<XFile> images = await picker.pickMultiImage(imageQuality: 85);
        if (images.isNotEmpty) {
          initialImages = images;
        }
      } else {
        final XFile? image = await picker.pickImage(
          source: source,
          imageQuality: 85,
        );
        if (image != null) {
          initialImages = [image];
        }
      }

      if (initialImages.isNotEmpty && mounted) {
        _abrirModalCotizacionFlashDirecto(context, initialImages);
      }
    } catch (e) {
      debugPrint("Error al seleccionar imagen para cotización flash: $e");
    }
  }

  void _abrirModalCotizacionFlashDirecto(BuildContext context, List<XFile> initialImages) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final cardBg = isDark ? const Color(0xFF1E222B) : Colors.white;
    List<XFile> selectedImages = List.from(initialImages);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Cotización Flash",
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Text(
                    "Fotos cargadas para extraer productos con IA:",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (selectedImages.isNotEmpty)
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedImages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, idx) {
                          final file = selectedImages[idx];
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: kIsWeb
                                    ? Image.network(file.path, fit: BoxFit.cover)
                                    : Image.file(File(file.path), fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      selectedImages.removeAt(idx);
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(20),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF282C37) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        "Sin fotos seleccionadas",
                        style: GoogleFonts.poppins(fontSize: 13, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                            label: Text(
                              "+ Agregar",
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            onPressed: () async {
                              final ImagePicker picker = ImagePicker();
                              final List<XFile> images = await picker.pickMultiImage(imageQuality: 85);
                              if (images.isNotEmpty) {
                                setModalState(() {
                                  selectedImages.addAll(images);
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5842F4),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: Text(
                              "Procesar (${selectedImages.length})",
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                            onPressed: selectedImages.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                    _procesarImagenesFlashConIA(selectedImages);
                                  },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _procesarImagenesFlashConIA(List<XFile> images) async {
    if (images.isEmpty) return;

    final canScan = await PlanLimitHelper.canScan();
    if (!canScan) {
      if (mounted) {
        final plan = await PlanLimitHelper.getPlanId();
        final limit = plan == 'free' ? PlanLimitHelper.freeEscaneos : PlanLimitHelper.proEscaneos;
        PlanLimitHelper.showUpgradeDialog(context, feature: "escaneos mágicos", currentLimit: limit);
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final openaiKey = prefs.getString('openai_api_key') ?? prefs.getString('gemini_api_key') ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                const CircularProgressIndicator(color: Color(0xFF5842F4)),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    "Escaneando con IA (ChatGPT)...\nBuscando y creando artículos...",
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://novaledbolivia.com/sistema/api/scan_quote.php'),
      );
      
      final token = prefs.getString('novaled_jwt_token') ?? '';
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['X-Authorization'] = 'Bearer $token';
      if (openaiKey.isNotEmpty) {
        request.headers['X-OpenAI-Key'] = openaiKey;
      }

      for (int i = 0; i < images.length; i++) {
        final file = await http.MultipartFile.fromPath('images[]', images[i].path);
        request.files.add(file);
      }

      final responseStream = await request.send();
      final response = await http.Response.fromStream(responseStream);

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        if (resJson['success'] == true && resJson['items'] is List) {
          final itemsList = resJson['items'] as List;

          if (resJson['cliente'] != null && resJson['cliente'] is Map) {
            final clientMap = Map<String, dynamic>.from(resJson['cliente']);
            final String? detectedClientName = clientMap['nombre']?.toString().trim();
            final String detectedClientPhone = clientMap['telefono']?.toString().trim() ?? '';
            final String detectedClientEmail = clientMap['correo']?.toString().trim() ?? '';

            if (detectedClientName != null && detectedClientName.isNotEmpty) {
              Cliente? matchedClient;
              try {
                matchedClient = _todosClientes.firstWhere(
                  (c) => c.nombreCompania.toLowerCase().trim() == detectedClientName.toLowerCase(),
                );
              } catch (_) {
                if (detectedClientName.trim().length >= 5) {
                  try {
                    matchedClient = _todosClientes.firstWhere(
                      (c) => c.nombreCompania.trim().length >= 5 && (
                             c.nombreCompania.toLowerCase().contains(detectedClientName.toLowerCase()) ||
                             detectedClientName.toLowerCase().contains(c.nombreCompania.toLowerCase())),
                    );
                  } catch (_) {}
                }
              }

              if (matchedClient != null) {
                setState(() {
                  _clienteNombreCtrl.text = matchedClient!.nombreCompania;
                  if (_clienteTelefonoCtrl.text.isEmpty) {
                    _clienteTelefonoCtrl.text = matchedClient.telefono.isNotEmpty ? matchedClient.telefono : detectedClientPhone;
                  }
                  if (_clienteCorreoCtrl.text.isEmpty) {
                    _clienteCorreoCtrl.text = matchedClient.correo.isNotEmpty ? matchedClient.correo : detectedClientEmail;
                  }
                });
              } else {
                final newClient = Cliente(
                  nombreCompania: detectedClientName,
                  telefono: detectedClientPhone,
                  correo: detectedClientEmail,
                );
                await DatabaseHelper.instance.insertCliente(newClient.toMap());
                await _loadClientes();
                
                setState(() {
                  _clienteNombreCtrl.text = detectedClientName;
                  _clienteTelefonoCtrl.text = detectedClientPhone;
                  _clienteCorreoCtrl.text = detectedClientEmail;
                });

                SyncService.instance.syncTable('clientes').catchError((e) {
                  debugPrint("Error al sincronizar nuevo cliente escaneado: $e");
                });
              }
            }
          }

          int itemsAgregados = 0;
          for (var item in itemsList) {
            String parsedCode = (item['codigo'] ?? '').toString().trim();
            String parsedName = (item['nombre'] ?? '').toString().trim();
            double parsedPrice = (item['precio'] as num?)?.toDouble() ?? 0.0;
            int parsedQty = int.tryParse(item['cantidad'].toString()) ?? 1;

            final newArt = Articulo(
              id: null,
              nombre: parsedName.isNotEmpty ? parsedName : 'Artículo Escaneado',
              precio: parsedPrice,
              precioCaja: 0.0,
              descripcion: (item['caracteristicas'] != null && item['caracteristicas'].toString().trim().isNotEmpty)
                  ? item['caracteristicas'].toString().trim()
                  : "Creado vía Cotización Flash",
              codCaja: parsedCode.isNotEmpty ? parsedCode : null,
              fecha: DateTime.now().toIso8601String(),
              unidad: item['unidad']?.toString() ?? 'Unidad',
              familia: (item['categoria'] ?? '').toString().trim(),
              subcategoria: (item['subcategoria'] ?? '').toString().trim(),
            );

            setState(() {
              _items.add(ItemCotizacion(
                articulo: newArt,
                precioOriginal: newArt.precio,
                cantidad: parsedQty,
              ));
            });
            itemsAgregados++;
          }

          _autoSaveSilently();
          PlanLimitHelper.incrementScanCount();

          if (mounted) {
            NovaledToast.show(context, "Cotización cargada: $itemsAgregados artículo(s) extraído(s)");
          }
        } else {
          throw Exception("Respuesta inválida de IA");
        }
      } else {
        final errJson = jsonDecode(response.body);
        throw Exception(errJson['error'] ?? "Error ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        NovaledToast.show(context, "Error: ${e.toString().replaceFirst("Exception: ", "")}");
      }
    }
  }

  void _mostrarOpcionesCotizacionFlash(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final cardBg = isDark ? const Color(0xFF1E222B) : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "Cotización Flash",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Escanea o selecciona una imagen para cargar la cotización automáticamente",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _seleccionarImagenCotizacionFlash(ImageSource.gallery);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF282C37) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Image.asset(
                        'Iconos/pantalla 4/galeria.png',
                        width: 26,
                        height: 26,
                        errorBuilder: (_, __, ___) => Icon(Icons.photo_library_outlined, color: const Color(0xFF5842F4), size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          "Cargar foto",
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _seleccionarImagenCotizacionFlash(ImageSource.camera);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF282C37) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Image.asset(
                        'Iconos/pantalla 4/camara.png',
                        width: 26,
                        height: 26,
                        errorBuilder: (_, __, ___) => Icon(Icons.camera_alt_outlined, color: const Color(0xFF5842F4), size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          "Sacar foto",
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _confirmarLlevarAPorCobrar(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
          title: Text(
            "Marcar como Por Cobrar",
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            "¿Desea aprobar este documento y marcarlo directamente en 'Por Cobrar'?",
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEFA820),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(context);
                setState(() {
                  _comprobado = 1;
                  _estado = 'aprobada';
                });
                final success = await _guardarCotizacion();
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Documento guardado y marcado 'Por Cobrar'"),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                  if (!widget.isDirectoPorCobrar) {
                    Navigator.pushNamed(
                      context,
                      '/venta_institucional',
                      arguments: {'tipoVenta': 'venta_institucional'},
                    );
                  }
                }
              },
              child: const Text("ACEPTAR", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPurpleCheckCircle({required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Center(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  String _formatSoloFechaDisplay(String? fechaStr) {
    if (fechaStr == null || fechaStr.trim().isEmpty) {
      final now = DateTime.now();
      return "${now.day}.${now.month.toString().padLeft(2, '0')}.${now.year.toString().substring(2)}";
    }
    final raw = fechaStr.split(' ')[0].split('T')[0].trim();
    final parts = raw.split('-');
    if (parts.length == 3) {
      final y = parts[0].length >= 4 ? parts[0].substring(2) : parts[0];
      final d = int.tryParse(parts[2])?.toString() ?? parts[2];
      return "$d.${parts[1]}.$y";
    }
    return raw;
  }

  String _formatMontoWithCommas(double amount) {
    if (amount == amount.toInt()) {
      final s = amount.toInt().toString();
      final buffer = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) {
          buffer.write('.');
        }
        buffer.write(s[i]);
      }
      return buffer.toString();
    }
    return amount.toStringAsFixed(2);
  }

  Widget _buildAnadirClienteScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final labelColor = isDark ? Colors.white.withOpacity(0.55) : Colors.black.withOpacity(0.45);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
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
                color: textColor,
              ),
              onPressed: () {
                setState(() {
                  _isEditingClientScreen = false;
                });
              },
            ),
          ),
        ),
        title: Text(
          "Añadir cliente",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: textColor,
            fontSize: 19,
          ),
        ),
        actions: [
          _buildPurpleCheckCircle(
            onTap: () {
              _autoSaveSilently();
              setState(() {
                _isEditingClientScreen = false;
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            const SizedBox(height: 8),
            Text(
              "Cliente / Empresa",
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: labelColor,
              ),
            ),
            const SizedBox(height: 2),
            TextField(
              controller: _clienteNombreCtrl,
              onChanged: (val) {
                _filtrarSugeridosClientes(val);
              },
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 2, bottom: 4),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF5842F4), width: 2),
                ),
              ),
            ),
            if (_showClientSuggestions && _sugeridosClientes.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 180,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _sugeridosClientes.length,
                    itemBuilder: (context, idx) {
                      final c = _sugeridosClientes[idx];
                      return ListTile(
                        dense: true,
                        title: Text(c.nombreCompania, style: GoogleFonts.poppins(fontSize: 14)),
                        onTap: () {
                          setState(() {
                            _clienteNombreCtrl.text = c.nombreCompania;
                            _clienteTelefonoCtrl.text = c.telefono;
                            _clienteCorreoCtrl.text = c.correo;
                            _showClientSuggestions = false;
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              "Celular",
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: labelColor,
              ),
            ),
            const SizedBox(height: 2),
            TextField(
              controller: _clienteTelefonoCtrl,
              keyboardType: TextInputType.phone,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 2, bottom: 4),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF5842F4), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Email",
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: labelColor,
              ),
            ),
            const SizedBox(height: 2),
            TextField(
              controller: _clienteCorreoCtrl,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 2, bottom: 4),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF5842F4), width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarOpcionesEdicionItem(ItemCotizacion item, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cantCtrl = TextEditingController(text: item.cantidad.toString());
    final precioCtrl = TextEditingController(text: item.articulo.precio.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF161A22) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            item.articulo.nombre,
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cantCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Cantidad"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: precioCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "Precio Unitario (Bs.)"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _items.removeAt(index);
                });
                _onDataChangedAutoSave(immediate: true);
              },
              child: const Text("Eliminar", style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final double? newCant = double.tryParse(cantCtrl.text.trim());
                final double? newPrecio = double.tryParse(precioCtrl.text.trim());
                if (newCant != null && newCant > 0 && newPrecio != null && newPrecio >= 0) {
                  setState(() {
                    _items[index] = ItemCotizacion(
                      articulo: item.articulo.copyWith(precio: newPrecio),
                      precioOriginal: item.precioOriginal,
                      cantidad: newCant.toInt(),
                      uniqueId: item.uniqueId,
                    );
                  });
                  _onDataChangedAutoSave(immediate: true);
                }
                Navigator.pop(ctx);
              },
              child: const Text("Guardar", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArticleCard({
    required ItemCotizacion item,
    required int index,
    required bool isDark,
    required Color textColor,
    required Color labelColor,
  }) {
    return SlidableArticleCard(
      key: ValueKey("art_${item.uniqueId}_$index"),
      item: item,
      index: index,
      isDark: isDark,
      textColor: textColor,
      labelColor: labelColor,
      isSelected: _selectedArticleIndexForActions == index,
      onSelect: () {
        setState(() {
          _selectedArticleIndexForActions = index;
        });
      },
      onClose: () {
        setState(() {
          if (_selectedArticleIndexForActions == index) {
            _selectedArticleIndexForActions = null;
          }
        });
      },
      onEdit: () {
        setState(() {
          _selectedArticleIndexForActions = null;
          _editingItemIndex = index;
          _selectedCatalogArticulo = item.articulo;
          _prodNombreCtrl.text = item.articulo.nombre;
          _prodPrecioCtrl.text = item.articulo.precio.toStringAsFixed(0);
          _prodCantCtrl.text = item.cantidad.toString();
          if (item.articulo.unidad.isNotEmpty) {
            _seleccionUnidadMedida = item.articulo.unidad;
          }
          _isSearchingProduct = true;
        });
      },
      onDelete: () {
        setState(() {
          _items.removeAt(index);
          _selectedArticleIndexForActions = null;
        });
        _onDataChangedAutoSave();
      },
      onDuplicate: () {
        setState(() {
          final clonedItem = ItemCotizacion(
            articulo: item.articulo.copyWith(),
            precioOriginal: item.precioOriginal,
            cantidad: item.cantidad,
          );
          _items.insert(index + 1, clonedItem);
          _selectedArticleIndexForActions = null;
        });
        _onDataChangedAutoSave();
      },
      onMove: () {
        _selectedArticleIndexForActions = null;
        _mostrarDialogoMoverItem(index);
      },
    );
  }

  Widget _buildUnifiedCotizacionBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final labelColor = isDark ? Colors.white.withOpacity(0.55) : Colors.black.withOpacity(0.45);
    final hasClient = _clienteNombreCtrl.text.trim().isNotEmpty;
    final hasArticles = _items.isNotEmpty;

    final int numDisplay = _displayId ?? (_idCotizacionExistente ?? (widget.displayId ?? 20));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: InkWell(
                  onTap: _seleccionarFechaResumen,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          "Fecha ${_formatSoloFechaDisplay(_fechaDocumento)}",
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: labelColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit_outlined,
                        size: 15,
                        color: labelColor,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    "$_computedTituloDocumento Nº $numDisplay",
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            children: [
              _buildVendedorSucursalCard(isDark, textColor, labelColor),
              // Toggle Pill Switch [ Proforma ] | [ Nota de entrega ] (solo en Punto de Venta cuando hay cliente o artículos)
              if (isPuntoDeVenta && (hasClient || hasArticles)) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E222B) : Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _tipoDocumentoSeleccionado = 'proforma';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _tipoDocumentoSeleccionado == 'proforma'
                                  ? Theme.of(context).primaryColor
                                  : (isDark ? Colors.transparent : Colors.white),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: _tipoDocumentoSeleccionado != 'proforma' && !isDark
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Nota de Venta",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _tipoDocumentoSeleccionado == 'proforma'
                                    ? Colors.white
                                    : (isDark ? labelColor : Theme.of(context).primaryColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _tipoDocumentoSeleccionado = 'nota_entrega';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _tipoDocumentoSeleccionado == 'nota_entrega'
                                  ? Theme.of(context).primaryColor
                                  : (isDark ? Colors.transparent : Colors.white),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: _tipoDocumentoSeleccionado != 'nota_entrega' && !isDark
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Nota de entrega",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _tipoDocumentoSeleccionado == 'nota_entrega'
                                    ? Colors.white
                                    : (isDark ? labelColor : Theme.of(context).primaryColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (!hasClient) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 78,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _isEditingClientScreen = true;
                      });
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add, color: Colors.white, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          "Añadir cliente",
                          style: GoogleFonts.poppins(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  "Cliente / Empresa",
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: labelColor,
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _isEditingClientScreen = true;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _clienteNombreCtrl.text.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: labelColor,
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), height: 1),
                const SizedBox(height: 16),
              ],

              if (!hasArticles) ...[
                SizedBox(
                  height: 78,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      foregroundColor: Theme.of(context).primaryColor,
                      elevation: isDark ? 0 : 2,
                      shadowColor: Colors.black.withOpacity(0.06),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _isSearchingProduct = true;
                      });
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Theme.of(context).primaryColor, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          "Añadir artículo",
                          style: GoogleFonts.poppins(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                for (int i = 0; i < _items.length; i++) ...[
                  _buildArticleCard(item: _items[i], index: i, isDark: isDark, textColor: textColor, labelColor: labelColor),
                  const SizedBox(height: 12),
                ],

                const SizedBox(height: 4),
                SizedBox(
                  height: 78,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Theme.of(context).primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _isSearchingProduct = true;
                      });
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Theme.of(context).primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          "Añadir producto",
                          style: GoogleFonts.poppins(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), height: 1),
                const SizedBox(height: 16),

                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "Total Bs. ${_formatMontoWithCommas(_total)}",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                if (!isPuntoDeVenta || _tipoDocumentoSeleccionado == 'nota_entrega') ...[
                  InkWell(
                    onTap: () {
                      setState(() {
                        _incluyeFirmaEmpresa = !_incluyeFirmaEmpresa;
                      });
                      _onDataChangedAutoSave();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Incluir sello",
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                          Icon(
                            _incluyeFirmaEmpresa ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: _incluyeFirmaEmpresa ? Theme.of(context).primaryColor : labelColor,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                if (!isPuntoDeVenta) ...[
                  InkWell(
                    onTap: () {
                      setState(() {
                        _mostrarNotas = !_mostrarNotas;
                      });
                      _onDataChangedAutoSave();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Notas adicionales",
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                          Icon(
                            _mostrarNotas ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: _mostrarNotas ? Theme.of(context).primaryColor : labelColor,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_mostrarNotas) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notasController,
                      maxLines: 3,
                      style: GoogleFonts.poppins(fontSize: 14, color: textColor),
                      decoration: InputDecoration(
                        hintText: "Escribe tus notas adicionales aquí...",
                        hintStyle: GoogleFonts.poppins(fontSize: 14, color: labelColor),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                  ],
                ],

                if (isPuntoDeVenta) ...[
                  _buildEstadoDePagoSection(),
                ],

                const SizedBox(height: 28),

                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Theme.of(context).primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                      elevation: 0,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () => _handleGenerarCotizacion(),
                    child: Text(
                      isPuntoDeVenta
                          ? "Realizar venta"
                          : "Generar vista previa",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEstadoDePagoSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final labelColor = isDark ? Colors.white.withOpacity(0.55) : Colors.black.withOpacity(0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          "Estado de pago",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 14),

        // 4 Tabs: [ Efectivo ] [ QR ] [ Transferencia ] [ Por pagar ]
        Row(
          children: [
            _buildPagoTabPill(0, "Efectivo", flex: 10),
            const SizedBox(width: 6),
            _buildPagoTabPill(1, "QR", flex: 7),
            const SizedBox(width: 6),
            _buildPagoTabPill(2, "Transferencia", flex: 14),
            const SizedBox(width: 6),
            _buildPagoTabPill(3, "Por pagar", flex: 11),
          ],
        ),

        const SizedBox(height: 14),

        // Dynamic White/Dark Content Card
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 130),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E222B) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _buildPagoTabContent(isDark, textColor, labelColor),
        ),
      ],
    );
  }

  Widget _buildPagoTabPill(int index, String label, {required int flex}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedEstadoPagoTab == index;

    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedEstadoPagoTab = index;
            if (index == 0) {
              _isPorPagar = false;
              _metodoPagoSeleccionado = "Efectivo";
            } else if (index == 1) {
              _isPorPagar = false;
              _metodoPagoSeleccionado = "QR";
            } else if (index == 2) {
              _isPorPagar = false;
              _metodoPagoSeleccionado = "Transferencia";
            } else if (index == 3) {
              _isPorPagar = true;
              _metodoPagoSeleccionado = "Por pagar";
            }
          });
          _onDataChangedAutoSave();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).primaryColor
                : (isDark ? const Color(0xFF1E222B) : Colors.white),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? Theme.of(context).primaryColor.withOpacity(0.35)
                    : Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                blurRadius: isSelected ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white70 : const Color(0xFF909CB5)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPagoTabContent(bool isDark, Color textColor, Color labelColor) {
    if (_selectedEstadoPagoTab == 0) {
      // Tab 0: Efectivo -> TextField "Nota..."
      return TextField(
        controller: _notasController,
        maxLines: 4,
        style: GoogleFonts.poppins(fontSize: 14, color: textColor),
        onChanged: (_) => _onDataChangedAutoSave(),
        decoration: InputDecoration(
          hintText: "Nota...",
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: labelColor),
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
        ),
      );
    } else if (_selectedEstadoPagoTab == 1) {
      // Tab 1: QR -> "Adjuntar comprobante" / "Comprobante adjuntado", Galeria icon button
      final hasImage = _comprobanteImgPath != null && _comprobanteImgPath!.isNotEmpty;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasImage ? "Comprobante adjuntado" : "Adjuntar comprobante",
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: hasImage
                ? Stack(
                    alignment: Alignment.topRight,
                    children: [
                      GestureDetector(
                        onTap: () => _mostrarPrevisualizacionComprobante(context, _comprobanteImgPath!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 130,
                            height: 130,
                            child: TenantHelper.buildReceiptImage(_comprobanteImgPath!, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          _autoSaveTimer?.cancel();
                          setState(() {
                            _comprobanteImgPath = null;
                            _numComprobanteController.clear();
                          });
                          _isAutoSaving = false;
                          await _guardarCotizacion();
                          await DatabaseHelper.instance.setTableDirty('notas_entrega');
                          await DatabaseHelper.instance.setTableDirty('proformas');
                          await DatabaseHelper.instance.setTableDirty('cotizaciones');
                          await SyncService.instance.syncTable('notas_entrega');
                          await SyncService.instance.syncTable('proformas');
                          await SyncService.instance.syncTable('cotizaciones');
                        },
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => _seleccionarFotoComprobante(ImageSource.gallery),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'Iconos/pagos/galeria.png',
                                width: 40,
                                height: 40,
                                color: labelColor,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.photo_library_outlined,
                                  size: 38,
                                  color: labelColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Galeria",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: labelColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 28),
                      InkWell(
                        onTap: () => _seleccionarFotoComprobante(ImageSource.camera),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.camera_alt_outlined,
                                size: 38,
                                color: labelColor,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Cámara",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: labelColor,
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
      );
    } else {
      // Tab 2: Transferencia o Tab 3: Por pagar -> TextField "Número de comprobante..."
      return TextField(
        controller: _numComprobanteController,
        style: GoogleFonts.poppins(fontSize: 14, color: textColor),
        onChanged: (_) => _onDataChangedAutoSave(),
        decoration: InputDecoration(
          hintText: "Número de comprobante...",
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: labelColor),
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
        ),
      );
    }
  }

  void _mostrarPrevisualizacionComprobante(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Center(
                  child: TenantHelper.buildReceiptImage(
                    imagePath,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _seleccionarFotoComprobante(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (image != null) {
        _autoSaveTimer?.cancel();
        setState(() {
          _comprobanteImgPath = image.path;
          _selectedEstadoPagoTab = 1;
          _metodoPagoSeleccionado = "QR";
          _isPorPagar = false;
        });

        // Comprimir inteligentemente y subir a la nube Hostinger
        final cloudPath = await TenantHelper.processAndUploadReceipt(image);
        if (cloudPath != null && mounted) {
          setState(() {
            _comprobanteImgPath = cloudPath;
          });
        }
        _isAutoSaving = false;
        await _guardarCotizacion();
        await DatabaseHelper.instance.setTableDirty('notas_entrega');
        await DatabaseHelper.instance.setTableDirty('proformas');
        await DatabaseHelper.instance.setTableDirty('cotizaciones');
        await SyncService.instance.syncTable('notas_entrega');
        await SyncService.instance.syncTable('proformas');
        await SyncService.instance.syncTable('cotizaciones');
      }
    } catch (e) {
      debugPrint("Error al seleccionar comprobante: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isShowingSuccessAnimation) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          setState(() {
            _isShowingSuccessAnimation = false;
          });
        },
        child: _buildSuccessAnimationScreen(),
      );
    }
    if (_isSearchingProduct) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          setState(() {
            _isSearchingProduct = false;
          });
        },
        child: _buildBuscarProductoScreen(),
      );
    }
    if (_isEditingClientScreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          setState(() {
            _isEditingClientScreen = false;
          });
        },
        child: _buildAnadirClienteScreen(),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    final String titleText = isPuntoDeVenta
        ? (_tipoDocumentoSeleccionado == 'nota_entrega'
            ? "Nota de entrega"
            : "Nota de Venta")
        : ((_clienteNombreCtrl.text.trim().isNotEmpty || _items.isNotEmpty)
            ? "Cotización"
            : "Nueva cotización");

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isEditingClientScreen) {
          setState(() {
            _isEditingClientScreen = false;
          });
        } else if (_isSearchingProduct) {
          setState(() {
            _isSearchingProduct = false;
            _editingItemIndex = null;
          });
        } else {
          await _autoSaveSilently();
          if (mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leadingWidth: 56,
          titleSpacing: 0,
          centerTitle: false,
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
                onPressed: () async {
                  await _autoSaveSilently();
                  if (mounted) Navigator.pop(context);
                },
              ),
            ),
          ),
          title: Text(
            titleText,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: textColor,
              fontSize: 19,
            ),
          ),
          actions: [
            if (_idCotizacionExistente == null) ...[
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => _mostrarOpcionesCotizacionFlash(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      size: 19,
                    ),
                  ),
                ),
              ),
            ],
            _AnimatedSaveCheckButton(
              onSave: () async {
                final success = await _guardarCotizacion();
                if (success && context.mounted) {
                  NovaledToast.show(
                    context,
                    _tipoDocumentoSeleccionado == 'nota_entrega'
                        ? "Nota de entrega guardada"
                        : (widget.isDirectoPorCobrar ? "Nota de venta guardada" : "Guardado"),
                  );
                }
              },
            ),
          ],
        ),
        body: SafeArea(
          child: _buildUnifiedCotizacionBody(),
        ),
      ),
    );
  }

  Widget _buildClientSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hasClient = _clienteNombreCtrl.text.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.3) : const Color(0xFF00ADEF).withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: isDark ? const Color(0xFF161A22) : Colors.white,
          child: InkWell(
            onTap: _mostrarEditorClienteFullScreen,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 5,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: hasClient
                            ? [const Color(0xFF00ADEF), const Color(0xFF6366F1)]
                            : [Colors.grey[400]!, Colors.grey[300]!],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: hasClient
                                ? [
                                    const Color(0xFF00ADEF).withOpacity(0.2),
                                    const Color(0xFF6366F1).withOpacity(0.1),
                                  ]
                                : [
                                    Colors.grey.withOpacity(0.1),
                                    Colors.grey.withOpacity(0.05),
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: hasClient
                                ? const Color(0xFF00ADEF).withOpacity(0.4)
                                : Colors.grey.withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          hasClient ? Icons.person_rounded : Icons.person_add_alt_1_rounded,
                          color: hasClient ? const Color(0xFF00ADEF) : Colors.grey,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  "DATOS DEL CLIENTE",
                                  style: TextStyle(
                                    color: hasClient ? const Color(0xFF00ADEF) : Colors.grey[500],
                                    fontWeight: FontWeight.w900,
                                    fontSize: 10,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                if (hasClient) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFF10B981).withOpacity(0.3),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: const Text(
                                      "ACTIVO",
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 8,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (hasClient) ...[
                              Text(
                                _clienteNombreCtrl.text.trim(),
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              if (_clienteTelefonoCtrl.text.trim().isNotEmpty || _clienteCorreoCtrl.text.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    if (_clienteTelefonoCtrl.text.trim().isNotEmpty)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.phone_android_rounded, size: 12, color: isDark ? Colors.grey[400] : Colors.black45),
                                          const SizedBox(width: 4),
                                          Text(
                                            _clienteTelefonoCtrl.text.trim(),
                                            style: TextStyle(
                                              color: isDark ? Colors.grey[400] : Colors.black54,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (_clienteCorreoCtrl.text.trim().isNotEmpty)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.email_outlined, size: 12, color: isDark ? Colors.grey[400] : Colors.black45),
                                          const SizedBox(width: 4),
                                          Text(
                                            _clienteCorreoCtrl.text.trim(),
                                            style: TextStyle(
                                              color: isDark ? Colors.grey[400] : Colors.black54,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ] else ...[
                              Text(
                                "Sin cliente asignado",
                                style: TextStyle(
                                  color: isDark ? Colors.grey[400] : Colors.black54,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                "Presione aquí para registrar al cliente",
                                style: TextStyle(
                                  color: isDark ? Colors.grey[600] : Colors.grey[500],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: hasClient ? const Color(0xFF00ADEF) : Colors.grey,
                        size: 26,
                      ),
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

  void _mostrarEditorClienteFullScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    final tempNombreCtrl = TextEditingController(text: _clienteNombreCtrl.text);
    final tempTelefonoCtrl = TextEditingController(text: _clienteTelefonoCtrl.text);
    final tempCorreoCtrl = TextEditingController(text: _clienteCorreoCtrl.text);
    final tempNombreFocusNode = FocusNode();

    List<Cliente> tempSugeridos = [];
    bool showSuggestions = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void filtrarSugeridos(String query) {
              if (query.trim().isEmpty) {
                setDialogState(() {
                  tempSugeridos = [];
                });
                return;
              }
              final lowercaseQuery = query.toLowerCase();
              setDialogState(() {
                tempSugeridos = _todosClientes.where((c) {
                  return c.nombreCompania.toLowerCase().contains(lowercaseQuery);
                }).toList();
              });
            }

            return Dialog.fullscreen(
              backgroundColor: isDark ? const Color(0xFF0B0C10) : Colors.grey[50],
              child: Scaffold(
                backgroundColor: isDark ? const Color(0xFF0B0C10) : Colors.grey[50],
                appBar: AppBar(
                  backgroundColor: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                  elevation: 0,
                  title: const Text(
                    "Información del Cliente",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                  actions: [
                    if (tempNombreCtrl.text.trim().isNotEmpty ||
                        tempTelefonoCtrl.text.trim().isNotEmpty ||
                        tempCorreoCtrl.text.trim().isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                        tooltip: "Limpiar campos",
                        onPressed: () {
                          setDialogState(() {
                            tempNombreCtrl.clear();
                            tempTelefonoCtrl.clear();
                            tempCorreoCtrl.clear();
                            tempSugeridos = [];
                          });
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.check_rounded, color: Color(0xFF00ADEF), size: 28),
                      tooltip: "Confirmar",
                      onPressed: () {
                        setState(() {
                          _clienteNombreCtrl.text = tempNombreCtrl.text.trim();
                          _clienteTelefonoCtrl.text = tempTelefonoCtrl.text.trim();
                          _clienteCorreoCtrl.text = tempCorreoCtrl.text.trim();
                          _isSaved = false;
                        });
                        Navigator.pop(dialogCtx);
                      },
                    ),
                  ],
                ),
                body: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: ListView(
                        padding: const EdgeInsets.all(24.0),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF161A22) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.black12,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.person_pin_rounded, color: Color(0xFF00ADEF), size: 24),
                                    const SizedBox(width: 8),
                                    Text(
                                      "DATOS GENERALES",
                                      style: TextStyle(
                                        color: const Color(0xFF00ADEF),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Focus(
                                  onFocusChange: (hasFocus) {
                                    if (!hasFocus) {
                                      Future.delayed(const Duration(milliseconds: 250), () {
                                        if (context.mounted) {
                                          setDialogState(() {
                                            showSuggestions = false;
                                          });
                                        }
                                      });
                                    } else {
                                      setDialogState(() {
                                        showSuggestions = true;
                                      });
                                    }
                                  },
                                  child: TextField(
                                    controller: tempNombreCtrl,
                                    focusNode: tempNombreFocusNode,
                                    autofocus: tempNombreCtrl.text.isEmpty,
                                    style: TextStyle(color: textColor, fontSize: 14),
                                    decoration: InputDecoration(
                                      labelText: "Nombre / Compañía",
                                      labelStyle: TextStyle(
                                        color: const Color(0xFF00ADEF),
                                        fontSize: isDark ? 11 : 12,
                                      ),
                                      prefixIcon: const Icon(Icons.business_rounded, color: Colors.grey),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderSide: const BorderSide(color: Color(0xFF00ADEF), width: 1.5),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: isDark ? Colors.black38 : Colors.grey[100],
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    ),
                                    onChanged: (val) {
                                      filtrarSugeridos(val);
                                    },
                                  ),
                                ),
                                if (showSuggestions && tempSugeridos.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  const Text(
                                    "Sugerencias de clientes:",
                                    style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 40,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: tempSugeridos.length,
                                      itemBuilder: (context, i) {
                                        final cli = tempSugeridos[i];
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 8.0),
                                          child: ActionChip(
                                            backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.grey[200],
                                            side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            label: Text(
                                              cli.nombreCompania,
                                              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                            onPressed: () {
                                              setDialogState(() {
                                                tempNombreCtrl.text = cli.nombreCompania;
                                                tempTelefonoCtrl.text = cli.telefono;
                                                tempCorreoCtrl.text = cli.correo;
                                                showSuggestions = false;
                                                tempNombreFocusNode.unfocus();
                                              });
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                TextField(
                                  controller: tempTelefonoCtrl,
                                  style: TextStyle(color: textColor, fontSize: 14),
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    labelText: "Teléfono",
                                    labelStyle: TextStyle(
                                      color: const Color(0xFF00ADEF),
                                      fontSize: isDark ? 11 : 12,
                                    ),
                                    prefixIcon: const Icon(Icons.phone_rounded, color: Colors.grey),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(color: Color(0xFF00ADEF), width: 1.5),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: isDark ? Colors.black38 : Colors.grey[100],
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: tempCorreoCtrl,
                                  style: TextStyle(color: textColor, fontSize: 14),
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: "Correo",
                                    labelStyle: TextStyle(
                                      color: const Color(0xFF00ADEF),
                                      fontSize: isDark ? 11 : 12,
                                    ),
                                    prefixIcon: const Icon(Icons.email_rounded, color: Colors.grey),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(color: Color(0xFF00ADEF), width: 1.5),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: isDark ? Colors.black38 : Colors.grey[100],
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00ADEF),
                                foregroundColor: Colors.black,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  _clienteNombreCtrl.text = tempNombreCtrl.text.trim();
                                  _clienteTelefonoCtrl.text = tempTelefonoCtrl.text.trim();
                                  _clienteCorreoCtrl.text = tempCorreoCtrl.text.trim();
                                  _isSaved = false;
                                });
                                Navigator.pop(dialogCtx);
                              },
                              icon: const Icon(Icons.save_rounded, size: 24),
                              label: const Text(
                                "CONFIRMAR Y GUARDAR",
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      tempNombreFocusNode.dispose();
      tempNombreCtrl.dispose();
      tempTelefonoCtrl.dispose();
      tempCorreoCtrl.dispose();
    });
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00ADEF).withOpacity(isDark ? 0.15 : 0.08),
                      const Color(0xFF00ADEF).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            const Color(0xFF1E293B),
                            const Color(0xFF0F172A),
                          ]
                        : [
                            Colors.white,
                            Colors.grey[100]!,
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00ADEF).withOpacity(0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00ADEF).withOpacity(isDark ? 0.15 : 0.06),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  size: 56,
                  color: Color(0xFF00ADEF),
                ),
              ),
              Positioned(
                right: 32,
                top: 32,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00ADEF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            "Tu lista de artículos está vacía",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Añada productos a este documento para calcular subtotales y generar el PDF.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: 250,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF00ADEF),
                  Color(0xFF6366F1),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00ADEF).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: _agregarArticulo,
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 6),
                      Text(
                        "AGREGAR ARTÍCULO",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Paso 2: Añada productos a la lista",
            style: TextStyle(
              color: isDark ? Colors.grey[600] : Colors.grey[500],
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        ..._items.asMap().entries.map((entry) {
          int index = entry.key;
          ItemCotizacion item = entry.value;
          return _SlidableItemTile(
            key: ValueKey(item.uniqueId),
            item: item,
            index: index,
            onTap: () async {
              final List<ItemCotizacion>? result = await Navigator.push<List<ItemCotizacion>>(
                context,
                MaterialPageRoute(
                  builder: (context) => AgregarArticuloScreen(itemAEditar: item),
                ),
              );
              if (result != null && result.isNotEmpty) {
                setState(() {
                  _items[index] = result.first;
                  _isSaved = false;
                });
                _onDataChangedAutoSave(immediate: true);
              }
            },
            onDelete: () {
              setState(() {
                _items.removeAt(index);
                _isSaved = false;
              });
              _onDataChangedAutoSave(immediate: true);
            },
            onMove: () => _mostrarDialogoMoverItem(index),
          );
        }).toList(),
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 20),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFF00ADEF).withOpacity(0.04),
                side: const BorderSide(color: Color(0xFF00ADEF), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _agregarArticulo,
              icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF00ADEF), size: 20),
              label: const Text(
                "AÑADIR OTRO ARTÍCULO",
                style: TextStyle(
                  color: Color(0xFF00ADEF),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _mostrarDialogoMoverItem(int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secTextColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final n = _items.length;
    final currentPos = index + 1;
    int selectedPos = currentPos;
    final textController = TextEditingController(text: currentPos.toString());

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final brandColor = Theme.of(context).primaryColor;
          return Dialog(
            backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: brandColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.swap_vert_rounded,
                          color: brandColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Mover artículo",
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            Text(
                              "Selecciona la nueva posición",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: secTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Badge Posición Actual
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2B313E) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Posición actual",
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: secTextColor,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: brandColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "#$currentPos",
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Quick Position selector chips
                  if (n > 1) ...[
                    Text(
                      "Mover a la posición:",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 42,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: n,
                        itemBuilder: (context, posIdx) {
                          final posNum = posIdx + 1;
                          final isSelected = selectedPos == posNum;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedPos = posNum;
                                textController.text = posNum.toString();
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? brandColor
                                    : (isDark ? const Color(0xFF2B313E) : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(14),
                                border: isSelected
                                    ? null
                                    : Border.all(
                                        color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                                      ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "#$posNum",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : secTextColor,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Manual Text Input
                  TextField(
                    controller: textController,
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      final p = int.tryParse(val);
                      if (p != null && p >= 1 && p <= n) {
                        setDialogState(() {
                          selectedPos = p;
                        });
                      }
                    },
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                    decoration: InputDecoration(
                      labelText: "Ingresar número manual (1 - $n)",
                      labelStyle: GoogleFonts.poppins(fontSize: 13, color: secTextColor),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2B313E) : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: brandColor, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Actions Row
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(
                            "Cancelar",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: secTextColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            final val = int.tryParse(textController.text);
                            if (val != null && val >= 1 && val <= n) {
                              Navigator.pop(dialogContext);
                              final targetIndex = val - 1;
                              if (targetIndex != index) {
                                setState(() {
                                  final item = _items.removeAt(index);
                                  _items.insert(targetIndex, item);
                                  _isSaved = false;
                                });
                                _onDataChangedAutoSave();
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Ingresa un número válido entre 1 y $n"),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          },
                          child: Text(
                            "Mover",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummary() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161A22) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "TOTAL PARCIAL",
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.black54,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                "${_subtotalOriginal.toStringAsFixed(2)} Bs",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (_ahorroTotalItems > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "AHORRO TOTAL",
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  "-${_ahorroTotalItems.toStringAsFixed(2)} Bs",
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          if (_descuentoPorcentaje > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "DESCUENTO GLOBAL (${_descuentoPorcentaje.toStringAsFixed(0)}%)",
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  "-${_montoDescuento.toStringAsFixed(2)} Bs",
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(
              color: isDark ? const Color(0xFF1E293B) : Colors.grey[200]!,
              height: 1,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "TOTAL GENERAL",
                style: TextStyle(
                  color: Color(0xFF00ADEF),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                "${_total.toStringAsFixed(2)} Bs",
                style: const TextStyle(
                  color: Color(0xFF00ADEF),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showConfigMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(height: 25),
              Text("CONFIGURACIÓN EXTRA", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const SizedBox(height: 25),
              StatefulBuilder(
                builder: (context, setMenuState) => Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.savings_outlined, color: Color(0xFF00ADEF)),
                      title: Text("Mostrar Ahorro Aplicado", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
                      value: _mostrarAhorro,
                      activeColor: const Color(0xFF00ADEF),
                      onChanged: (val) {
                        setState(() {
                          _mostrarAhorro = val;
                          _isSaved = false;
                        });
                        setMenuState(() {});
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.note_alt_outlined, color: Color(0xFF00ADEF)),
                      title: Text("Notas Adicionales", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
                      subtitle: Text(_mostrarNotas ? "Habilitadas" : "Deshabilitadas", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      value: _mostrarNotas,
                      activeColor: const Color(0xFF00ADEF),
                      onChanged: (val) {
                        setState(() {
                          _mostrarNotas = val;
                          _isSaved = false;
                        });
                        setMenuState(() {});
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF00ADEF)),
      title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Widget _buildNotesField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: _notasController,
      maxLines: 2,
      onChanged: (val) {
        setState(() => _isSaved = false);
      },
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
      decoration: InputDecoration(
        hintText: "Notas adicionales para el PDF...",
        hintStyle: TextStyle(color: isDark ? Colors.white.withOpacity(0.2) : Colors.black38),
        filled: true,
        fillColor: isDark ? Colors.black : Colors.grey[200],
        contentPadding: const EdgeInsets.all(15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  // ignore: unused_element
  void _configurarDescuento() {
    final controller = TextEditingController(text: _descuentoPorcentaje.toStringAsFixed(0));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        title: Text("CONFIGURAR DESCUENTO", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: const InputDecoration(
            suffixText: "%",
            labelText: "Porcentaje",
            labelStyle: TextStyle(color: Color(0xFF00ADEF)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          TextButton(
            onPressed: () {
              setState(() {
                _descuentoPorcentaje = double.tryParse(controller.text) ?? 0.0;
                _isSaved = false;
              });
              Navigator.pop(context);
            },
            child: const Text("APLICAR", style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  void _configurarFirmas() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
          title: Text("SELLO VISIBLE", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text("Incluir sello", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                value: _incluyeFirmaEmpresa,
                activeColor: const Color(0xFF00ADEF),
                onChanged: (val) {
                  setState(() {
                    _incluyeFirmaEmpresa = val;
                    _isSaved = false;
                  });
                  setDialogState(() {});
                },
              ),
              SwitchListTile(
                title: Text("Cliente", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                value: _incluyeFirmaCliente,
                activeColor: const Color(0xFF00ADEF),
                onChanged: (val) {
                  setState(() {
                    _incluyeFirmaCliente = val;
                    _isSaved = false;
                  });
                  setDialogState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("LISTO")),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  void _configurarTerminos() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        title: Text("TÉRMINOS Y CONDICIONES", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _terminosController,
          maxLines: 6,
          onChanged: (val) {
            setState(() => _isSaved = false);
          },
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
          decoration: InputDecoration(
            hintText: "Escriba aquí la validez, garantía, etc...",
            hintStyle: TextStyle(color: isDark ? Colors.white.withOpacity(0.2) : Colors.black38),
            filled: true,
            fillColor: isDark ? Colors.black : Colors.grey[200],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CERRAR")),
        ],
      ),
    );
  }


  void _agregarArticulo() async {
    FocusScope.of(context).unfocus();
    final List<ItemCotizacion>? result = await Navigator.push<List<ItemCotizacion>>(
      context,
      MaterialPageRoute(
        builder: (context) => const AgregarArticuloScreen(),
      ),
    );
    FocusScope.of(context).unfocus();

    if (result != null && result.isNotEmpty) {
      setState(() {
        for (var newItem in result) {
          final existingIndex = _items.indexWhere(
            (it) => it.articulo.nombre.trim().toLowerCase() == newItem.articulo.nombre.trim().toLowerCase(),
          );
          if (existingIndex != -1) {
            _items[existingIndex] = _items[existingIndex].copyWith(
              cantidad: _items[existingIndex].cantidad + newItem.cantidad,
            );
          } else {
            _items.add(newItem);
          }
        }
        _isSaved = false;
      });
      _onDataChangedAutoSave();
    }
  }

  Future<bool> _guardarCotizacion() async {
    _autoSaveTimer?.cancel();
    _isAutoSaving = false;
    final success = await _autoSaveSilently(showDialogOnLimit: true);
    if (!success && mounted) {
      final clienteNombreText = _clienteNombreCtrl.text.trim();
      if (_items.isEmpty && clienteNombreText.isEmpty) {
        NovaledToast.show(context, "Ingrese al menos un producto o el nombre del cliente para guardar.");
      }
    }
    return success;
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

  void _mostrarOpcionesDescarga() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.download_for_offline, color: Color(0xFFEFA820), size: 28),
                  const SizedBox(width: 12),
                  Text(
                    "Descargar Documento",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Seleccione el formato en el que desea descargar el archivo a su dispositivo:",
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 20),
              // Option 1: PDF
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _descargarComoPDF();
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFEFA820).withOpacity(0.3),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFFEFA820).withOpacity(0.05),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFA820).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.picture_as_pdf, color: Color(0xFFEFA820), size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Documento PDF (.pdf)",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Formato oficial listo para enviar o imprimir directamente.",
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Option 2: Word (.docx)
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _descargarComoWord();
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFEFA820).withOpacity(0.3),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFFEFA820).withOpacity(0.05),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFA820).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.description, color: Color(0xFFEFA820), size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Documento Word (.docx)",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Formato editable de Microsoft Word para realizar cambios.",
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _descargarComoPDF() async {
    try {
      int? previewId = _displayId;
      if (previewId == null) {
        final all = await DatabaseHelper.instance.queryAllCotizaciones();
        previewId = all.length + 1;
      }
      final formattedId = previewId.toString().padLeft(5, '0');

      final currentBytes = await PdfService.generateCotizacionBytes(
        clienteNombre: _clienteNombreCtrl.text.trim(),
        items: _items,
        subtotalOriginal: _subtotalOriginal,
        ahorroItems: _ahorroTotalItems,
        descuentoGlobal: _montoDescuento,
        total: _total,
        notas: _notasController.text,
        terminos: _terminosController.text,
        docId: previewId,
        incluyeFirmaEmpresa: _incluyeFirmaEmpresa,
        incluyeFirmaCliente: _incluyeFirmaCliente,
        mostrarAhorro: _mostrarAhorro,
        mostrarTerminos: _mostrarTerminos,
        isColor: _isColor,
        fecha: _fechaDocumento,
        tituloDocumento: _computedTituloDocumento,
        sucursal: _sucursalSeleccionada ?? (_listaSucursales.isNotEmpty ? _listaSucursales.first : ''),
        vendedor: _vendedorSeleccionado ?? _vendedorOriginal ?? (Session().userName ?? ''),
      );

      final filename = _computedFilenamePdf(formattedId);

      if (kIsWeb) {
        await FileSaver.save(filename, currentBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("PDF descargado: $filename"),
              backgroundColor: const Color(0xFFEFA820),
            ),
          );
        }
      } else {
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

        final file = File('${directory.path}/$filename');
        await file.writeAsBytes(currentBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("PDF guardado en descargas: $filename"),
              backgroundColor: const Color(0xFFEFA820),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error al descargar PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al guardar PDF: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _descargarComoWord() async {
    try {
      int? previewId = _displayId;
      if (previewId == null) {
        final all = await DatabaseHelper.instance.queryAllCotizaciones();
        previewId = all.length + 1;
      }
      final formattedId = previewId.toString().padLeft(5, '0');

      final currentBytes = await DocxService.generateCotizacionDocx(
        clienteNombre: _clienteNombreCtrl.text.trim(),
        items: _items,
        subtotalOriginal: _subtotalOriginal,
        ahorroItems: _ahorroTotalItems,
        descuentoGlobal: _montoDescuento,
        total: _total,
        notas: _notasController.text,
        terminos: _terminosController.text,
        docId: previewId,
        incluyeFirmaEmpresa: _incluyeFirmaEmpresa,
        incluyeFirmaCliente: _incluyeFirmaCliente,
        mostrarAhorro: _mostrarAhorro,
        mostrarTerminos: _mostrarTerminos,
        fecha: _fechaDocumento,
        tituloDocumento: _computedTituloDocumento,
      );

      final filename = _computedFilenameWord(formattedId);

      if (kIsWeb) {
        await FileSaver.save(filename, currentBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Documento Word descargado: $filename"),
              backgroundColor: const Color(0xFFEFA820),
            ),
          );
        }
      } else {
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

        final file = File('${directory.path}/$filename');
        await file.writeAsBytes(currentBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Documento Word guardado en descargas: $filename"),
              backgroundColor: const Color(0xFFEFA820),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error al descargar Word: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al guardar Word: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generarPDF() async {
    if (!mounted) return;

    int? previewId = _displayId;
    if (previewId == null) {
      final all = await DatabaseHelper.instance.queryAllCotizaciones();
      previewId = all.length + 1;
    }

    final tituloDoc = _computedTituloDocumento;
    final tituloPantalla = _computedTituloPantalla;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CotizacionVistaPreviaScreen(
          titulo: tituloPantalla,
          clienteNombre: _clienteNombreCtrl.text.trim(),
          items: _items,
          subtotalOriginal: _subtotalOriginal,
          ahorroItems: _ahorroTotalItems,
          descuentoGlobal: _montoDescuento,
          total: _total,
          notas: _notasController.text,
          terminos: _terminosController.text,
          docId: previewId,
          incluyeFirmaEmpresa: _incluyeFirmaEmpresa,
          incluyeFirmaCliente: _incluyeFirmaCliente,
          tituloDocumento: tituloDoc,
          fecha: _fechaDocumento,
          sucursal: _sucursalSeleccionada ?? (_listaSucursales.isNotEmpty ? _listaSucursales.first : ''),
          vendedor: _vendedorSeleccionado ?? _vendedorOriginal ?? (Session().userName ?? ''),
          returnButtonText: _computedReturnButtonText,
          onEdit: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _showSaveToCatalogDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161A22) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00ADEF).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.archive_outlined, color: Color(0xFF00ADEF), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        "¿Guardar en Inventario?",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 19,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  "Se detectaron nuevos artículos. ¿Desea guardarlos en el catálogo de Inventario principal?\n\nSi elige NO, permanecerán en el Pre-inventario.",
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _newArticlesCreatedIds.clear();
                      },
                      child: const Text(
                        "NO, DEJAR ASÍ",
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00ADEF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _moveCreatedArticlesToCatalog();
                      },
                      child: const Text(
                        "SÍ, GUARDAR",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _moveCreatedArticlesToCatalog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Color(0xFF00ADEF))),
    );

    try {
      final db = await DatabaseHelper.instance.database;
      for (int id in _newArticlesCreatedIds) {
        final res = await db.query('articulos', where: 'id = ?', whereArgs: [id]);
        if (res.isNotEmpty) {
          final artMap = res.first;
          final stockJsonStr = artMap['stockJson']?.toString() ?? '';
          Map<String, dynamic> extra = {};
          if (stockJsonStr.isNotEmpty) {
            try {
              extra = jsonDecode(stockJsonStr);
            } catch (_) {}
          }
          extra['isCatalog'] = true;
          
          final updatedRow = Map<String, dynamic>.from(artMap)..['stockJson'] = jsonEncode(extra);
          await db.update('articulos', updatedRow, where: 'id = ?', whereArgs: [id]);
        }
      }

      // Actualizar en memoria también
      for (int i = 0; i < _items.length; i++) {
        final item = _items[i];
        if (item.articulo.id != null && _newArticlesCreatedIds.contains(item.articulo.id)) {
          final stockJsonStr = item.articulo.stockJson ?? '';
          Map<String, dynamic> extra = {};
          if (stockJsonStr.isNotEmpty) {
            try {
              extra = jsonDecode(stockJsonStr);
            } catch (_) {}
          }
          extra['isCatalog'] = true;
          final updatedArt = item.articulo.copyWith(stockJson: jsonEncode(extra));
          _items[i] = ItemCotizacion(
            articulo: updatedArt,
            precioOriginal: item.precioOriginal,
            cantidad: item.cantidad,
            uniqueId: item.uniqueId,
          );
        }
      }

      await SyncService.instance.syncTable('articulos');
      _newArticlesCreatedIds.clear();

      if (mounted) {
        Navigator.pop(context); // Cerrar loader
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Artículos guardados en el inventario principal con éxito."),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loader
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al guardar en el catálogo: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _AnimatedSaveCheckButton extends StatefulWidget {
  final Future<void> Function() onSave;
  const _AnimatedSaveCheckButton({required this.onSave});

  @override
  State<_AnimatedSaveCheckButton> createState() => _AnimatedSaveCheckButtonState();
}

class _AnimatedSaveCheckButtonState extends State<_AnimatedSaveCheckButton> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  bool _isSavedEffect = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.80), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.80, end: 1.18), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    _animController.forward(from: 0.0);

    await widget.onSave();

    if (mounted) {
      setState(() {
        _isSavedEffect = true;
        _isSaving = false;
      });
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) {
          setState(() {
            _isSavedEffect = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnim,
          child: InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _isSavedEffect ? const Color(0xFF10B981) : Theme.of(context).primaryColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isSavedEffect ? const Color(0xFF10B981) : Theme.of(context).primaryColor).withOpacity(0.45),
                    blurRadius: _isSavedEffect ? 14 : 6,
                    spreadRadius: _isSavedEffect ? 2 : 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  _isSavedEffect ? Icons.done_all_rounded : Icons.check_rounded,
                  key: ValueKey(_isSavedEffect),
                  color: _isSavedEffect ? Colors.white : (Theme.of(context).primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white),
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowingCheckButton extends StatefulWidget {
  final bool glow;
  final VoidCallback? onPressed;

  const _GlowingCheckButton({
    required this.glow,
    required this.onPressed,
  });

  @override
  State<_GlowingCheckButton> createState() => _GlowingCheckButtonState();
}

class _GlowingCheckButtonState extends State<_GlowingCheckButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _glowAnimation = Tween<double>(begin: 3.0, end: 15.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.glow) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _GlowingCheckButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.glow && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.glow && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.glow) {
      return IconButton(
        icon: const Icon(Icons.check_rounded, size: 28),
        color: const Color(0xFF94A3B8), // Plomo (Grey)
        onPressed: widget.onPressed,
        tooltip: "Guardar y Finalizar",
      );
    }

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withOpacity(0.5), // Green glow
                blurRadius: _glowAnimation.value,
                spreadRadius: _glowAnimation.value / 3,
              ),
            ],
          ),
          child: CircleAvatar(
            backgroundColor: const Color(0xFF10B981), // Saved Green
            radius: 20,
            child: IconButton(
              icon: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
              onPressed: widget.onPressed,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: "Volver atrás (Guardado)",
            ),
          ),
        );
      },
    );
  }
}

class _SlidableItemTile extends StatefulWidget {
  final ItemCotizacion item;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onMove;

  const _SlidableItemTile({
    super.key,
    required this.item,
    required this.index,
    required this.onTap,
    required this.onDelete,
    required this.onMove,
  });

  @override
  State<_SlidableItemTile> createState() => _SlidableItemTileState();
}

class _SlidableItemTileState extends State<_SlidableItemTile> {
  double _offset = 0;
  final double maxOffset = -140;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.item;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161A22) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey[200]!,
            width: 1,
          ),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: () {
                    setState(() => _offset = 0);
                    widget.onMove();
                  },
                  child: Container(
                    width: 70,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.orangeAccent,
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.swap_vert_rounded, color: Colors.white, size: 20),
                        SizedBox(height: 4),
                        Text(
                          "MOVER",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
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
                      color: Colors.redAccent,
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
                        SizedBox(height: 4),
                        Text(
                          "BORRAR",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
              child: Material(
                color: isDark ? const Color(0xFF161A22) : Colors.white,
                child: InkWell(
                  onTap: _offset == 0 ? widget.onTap : () => setState(() => _offset = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: const BoxDecoration(),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          child: Text(
                            "#${widget.index + 1}",
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF00ADEF),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.articulo.nombre,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    "${item.articulo.precio} Bs x ${item.cantidad} (${item.articulo.unidad})",
                                    style: TextStyle(
                                      color: isDark ? Colors.grey[400] : Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (item.ahorro > 0) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                      ),
                                      child: Text(
                                        "-${((item.precioOriginal - item.articulo.precio) / item.precioOriginal * 100).toStringAsFixed(0)}%",
                                        style: const TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (item.articulo.unidadDetalle.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                  Text(
                                    item.articulo.unidadDetalle,
                                    style: TextStyle(
                                      color: isDark ? Colors.grey[500] : Colors.black45,
                                      fontSize: 10,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "${item.total.toStringAsFixed(2)} Bs",
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF00ADEF),
                              fontSize: 15,
                            ),
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

class SlidableArticleCard extends StatefulWidget {
  final ItemCotizacion item;
  final int index;
  final bool isDark;
  final Color textColor;
  final Color labelColor;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onMove;

  const SlidableArticleCard({
    Key? key,
    required this.item,
    required this.index,
    required this.isDark,
    required this.textColor,
    required this.labelColor,
    required this.isSelected,
    required this.onSelect,
    required this.onClose,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onMove,
  }) : super(key: key);

  @override
  State<SlidableArticleCard> createState() => _SlidableArticleCardState();
}

class _SlidableArticleCardState extends State<SlidableArticleCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragExtent = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    if (widget.isSelected) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SlidableArticleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _controller.forward();
      } else {
        _controller.reverse();
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
    final cantStr = widget.item.cantidad.toString();
    final precioStr = widget.item.articulo.precio.toStringAsFixed(2);
    final subtotalStr = widget.item.total.toStringAsFixed(2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final actionWidth = (totalWidth * 0.65).clamp(170.0, 230.0);

        void handleDragUpdate(DragUpdateDetails details) {
          setState(() {
            _dragExtent -= details.primaryDelta!;
            if (_dragExtent < 0) _dragExtent = 0;
            if (_dragExtent > actionWidth) _dragExtent = actionWidth;
            _controller.value = _dragExtent / actionWidth;
          });
        }

        void handleDragEnd(DragEndDetails details) {
          if (_dragExtent > actionWidth / 2 || (details.primaryVelocity ?? 0) < -150) {
            _controller.forward();
            _dragExtent = actionWidth;
            widget.onSelect();
          } else {
            _controller.reverse();
            _dragExtent = 0.0;
            widget.onClose();
          }
        }

        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final progress = _animation.value;
            final currentOffset = progress * actionWidth;

            return ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Action Bar Background
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.isDark ? const Color(0xFF161A22) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left Section: Subtotal Text
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 14, right: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "Bs. $subtotalStr",
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: widget.labelColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          // Right Section: Gradient Action Buttons
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                            child: Container(
                              width: actionWidth,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).primaryColor.withOpacity(0.4),
                                    Theme.of(context).primaryColor,
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // 1. Editar
                                  Expanded(
                                    child: InkWell(
                                      onTap: widget.onEdit,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'Iconos/Nuevo/nuevo/2/editar.png',
                                            width: 16,
                                            height: 16,
                                            color: Colors.white,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.edit_outlined, color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(height: 2),
                                          Text("Editar", style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // 2. Eliminar
                                  Expanded(
                                    child: InkWell(
                                      onTap: widget.onDelete,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'Iconos/Nuevo/nuevo/2/borrar4.png',
                                            width: 16,
                                            height: 16,
                                            color: Colors.white,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.delete_outline, color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(height: 2),
                                          Text("Eliminar", style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // 3. Duplicar
                                  Expanded(
                                    child: InkWell(
                                      onTap: widget.onDuplicate,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'Iconos/Nuevo/nuevo/2/copia.png',
                                            width: 16,
                                            height: 16,
                                            color: Colors.white,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.copy_rounded, color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(height: 2),
                                          Text("Duplicar", style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // 4. Mover
                                  Expanded(
                                    child: InkWell(
                                      onTap: widget.onMove,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'Iconos/Nuevo/nuevo/2/mover.png',
                                            width: 16,
                                            height: 16,
                                            color: Colors.white,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.open_with_rounded, color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(height: 2),
                                          Text("Mover", style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Foreground Sliding Card
                  Transform.translate(
                    offset: Offset(-currentOffset, 0),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: handleDragUpdate,
                      onHorizontalDragEnd: handleDragEnd,
                      onTap: () {
                        if (progress > 0.5) {
                          _controller.reverse();
                          _dragExtent = 0.0;
                          widget.onClose();
                        } else {
                          _controller.forward();
                          _dragExtent = actionWidth;
                          widget.onSelect();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: widget.isDark ? const Color(0xFF161A22) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(widget.isDark ? 0.2 : 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "${widget.index + 1}",
                                style: GoogleFonts.poppins(
                                  color: Theme.of(context).primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.item.articulo.nombre,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: widget.textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "$cantStr x Bs. $precioStr",
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w400,
                                      color: widget.labelColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Bs. $subtotalStr",
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: widget.labelColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              progress > 0.5 ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                              color: widget.labelColor,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
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
}

class _SelectorUnidadMedidaSheet extends StatefulWidget {
  final String seleccionInicial;
  final ValueChanged<String> onSeleccionar;

  const _SelectorUnidadMedidaSheet({
    required this.seleccionInicial,
    required this.onSeleccionar,
  });

  @override
  State<_SelectorUnidadMedidaSheet> createState() => _SelectorUnidadMedidaSheetState();
}

class _SelectorUnidadMedidaSheetState extends State<_SelectorUnidadMedidaSheet> {
  List<String> _lista = [];
  late String _seleccionada;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _seleccionada = widget.seleccionInicial;
    _recargarLista();
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recargarLista();
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _recargarLista() async {
    try {
      await SyncService.instance.syncTable('unidades_medida').catchError((_) {});
      final raw = await DatabaseHelper.instance.queryAllUnidadesMedida();
      final names = raw.map((u) => u['nombre']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
      if (names.isNotEmpty && mounted) {
        setState(() {
          _lista = names;
        });
      }
    } catch (_) {}
  }

  void _dialogAgregar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Nueva Unidad de Medida",
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.poppins(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: "Ej: Rollo, Kg, Docena...",
              hintStyle: GoogleFonts.poppins(color: isDark ? Colors.white30 : Colors.black38),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5842F4), width: 2)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text("CANCELAR", style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5842F4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isNotEmpty) {
                  Navigator.pop(dialogCtx);
                  if (!_lista.any((u) => u.toLowerCase() == nombre.toLowerCase())) {
                    setState(() {
                      _lista.add(nombre);
                      _seleccionada = nombre;
                    });
                    widget.onSeleccionar(nombre);
                  }
                  final uuid = "UM_${DateTime.now().millisecondsSinceEpoch}";
                  await DatabaseHelper.instance.insertUnidadMedida({
                    'nombre': nombre,
                    'folderId': uuid,
                  }).catchError((_) => 0);
                  await DatabaseHelper.instance.setTableDirty('unidades_medida');
                  await SyncService.instance.syncTable('unidades_medida').catchError((_) {});
                  _recargarLista();
                }
              },
              child: Text("GUARDAR", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  void _dialogEditar(int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prev = _lista[index];
    final ctrl = TextEditingController(text: prev);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Editar Unidad de Medida",
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.poppins(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF5842F4), width: 2)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text("CANCELAR", style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5842F4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final nombre = ctrl.text.trim();
                if (nombre.isNotEmpty && nombre.toLowerCase() != prev.toLowerCase()) {
                  Navigator.pop(dialogCtx);
                  setState(() {
                    _lista[index] = nombre;
                    if (_seleccionada.toLowerCase() == prev.toLowerCase()) {
                      _seleccionada = nombre;
                      widget.onSeleccionar(nombre);
                    }
                  });
                  final db = await DatabaseHelper.instance.database;
                  final raw = await db.query('unidades_medida', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [prev.toLowerCase()], limit: 1);
                  if (raw.isNotEmpty) {
                    final id = raw.first['id'] as int;
                    final oldFolderId = raw.first['folderId']?.toString();
                    // Registrar borrado del nombre anterior para sincronizar con la nube y los otros dispositivos
                    await DatabaseHelper.instance.recordDeletion('unidades_medida', oldFolderId ?? "OLD_${DateTime.now().millisecondsSinceEpoch}", nombre: prev);
                    // Actualizar registro con el nuevo nombre y UUID
                    final newUuid = "UM_${DateTime.now().millisecondsSinceEpoch}";
                    await DatabaseHelper.instance.updateUnidadMedida({
                      'id': id,
                      'nombre': nombre,
                      'folderId': newUuid,
                    }).catchError((_) => 0);
                  }
                  await DatabaseHelper.instance.setTableDirty('unidades_medida');
                  await SyncService.instance.syncTable('unidades_medida').catchError((_) {});
                  _recargarLista();
                } else {
                  Navigator.pop(dialogCtx);
                }
              },
              child: Text("ACTUALIZAR", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  void _eliminar(int index) async {
    if (_lista.length <= 1) return;
    final item = _lista[index];
    setState(() {
      _lista.removeAt(index);
      if (_seleccionada.toLowerCase() == item.toLowerCase()) {
        _seleccionada = _lista.first;
        widget.onSeleccionar(_seleccionada);
      }
    });
    final db = await DatabaseHelper.instance.database;
    final raw = await db.query('unidades_medida', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [item.toLowerCase()], limit: 1);
    if (raw.isNotEmpty) {
      final id = raw.first['id'] as int;
      final folderId = raw.first['folderId']?.toString();
      await DatabaseHelper.instance.recordDeletion('unidades_medida', folderId ?? "OLD_${DateTime.now().millisecondsSinceEpoch}", nombre: item);
      await DatabaseHelper.instance.deleteUnidadMedida(id).catchError((_) => 0);
    } else {
      await DatabaseHelper.instance.recordDeletion('unidades_medida', "OLD_${DateTime.now().millisecondsSinceEpoch}", nombre: item);
    }
    await DatabaseHelper.instance.setTableDirty('unidades_medida');
    await SyncService.instance.syncTable('unidades_medida').catchError((_) {});
    _recargarLista();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final cardBg = isDark ? const Color(0xFF1E222B) : Colors.white;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Unidad de Medida",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF5842F4),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(
                  "Agregar",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                onPressed: _dialogAgregar,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _lista.length,
              separatorBuilder: (_, __) => Divider(
                color: isDark ? Colors.white12 : const Color(0xFFF1F5F9),
                height: 1,
              ),
              itemBuilder: (context, idx) {
                final u = _lista[idx];
                final isSelected = _seleccionada.toLowerCase() == u.toLowerCase();

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  title: Text(
                    u,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? const Color(0xFF5842F4) : textColor,
                    ),
                  ),
                  leading: Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: isSelected ? const Color(0xFF5842F4) : (isDark ? Colors.white30 : const Color(0xFFCBD5E1)),
                    size: 22,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit_outlined, size: 18, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                        onPressed: () => _dialogEditar(idx),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                        onPressed: () => _eliminar(idx),
                      ),
                    ],
                  ),
                  onTap: () {
                    setState(() {
                      _seleccionada = u;
                    });
                    widget.onSeleccionar(u);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
