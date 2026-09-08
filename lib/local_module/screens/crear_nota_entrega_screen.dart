import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
import 'package:google_fonts/google_fonts.dart';
import '../../drive_service.dart';
import '../services/sync_service.dart';
import 'agregar_articulo_screen.dart';
import '../../login_screen.dart';
import '../widgets/zoomable_pdf_preview.dart';
import '../widgets/novaled_toast.dart';
import '../widgets/novaled_thick_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cotizacion_vista_previa_screen.dart';
import '../tenant_helper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_decorations.dart';
import '../../shared_widgets/modals/select_cliente_modal.dart';
import '../../shared_widgets/modals/select_sucursal_modal.dart';
import '../../shared_widgets/cards/total_summary_card.dart';
import '../../shared_widgets/buttons/primary_action_button.dart';


class CrearNotaEntregaScreen extends StatefulWidget {
  final Map<String, dynamic>? notaExistente;
  final int? displayId;
  final Map<String, dynamic>? convertFromQuote;
  final String tipoVenta;
  const CrearNotaEntregaScreen({super.key, this.notaExistente, this.displayId, this.convertFromQuote, this.tipoVenta = 'punto_venta'});

  @override
  State<CrearNotaEntregaScreen> createState() => _CrearNotaEntregaScreenState();
}

class _CrearNotaEntregaScreenState extends State<CrearNotaEntregaScreen> {
  final List<ItemCotizacion> _items = [];
  double _descuentoPorcentaje = 0.0;
  bool _incluyeFirmaEmpresa = false;
  bool _incluyeFirmaCliente = false;
  String _tipoDocumentoSeleccionado = 'nota_entrega';
  final TextEditingController _notasController = TextEditingController();
  final TextEditingController _terminosController = TextEditingController(
    text: "- Recibí conforme los productos detallados.\n- No se aceptan devoluciones después de 48 hrs.\n- La mercadería viaja por cuenta y riesgo del cliente."
  );
  bool _isSaved = false;
  int? _idNotaExistente;
  int? _displayId;
  bool _isColor = true;
  bool _mostrarAhorro = false;
  bool _mostrarTerminos = false;
  final DriveService _drive = DriveService();
  String? _fechaDocumento;
  String? _uuid;
  bool _mostrarNotas = false;
  String? _vendedorOriginal;

  // Nuevas variables para clientes flexibles e inline stepper
  final TextEditingController _clienteNombreCtrl = TextEditingController();
  final TextEditingController _clienteTelefonoCtrl = TextEditingController();
  final TextEditingController _clienteCorreoCtrl = TextEditingController();
  List<Cliente> _todosClientes = [];

  int _currentStep = 1;
  int _comprobado = 0;
  List<Cliente> _sugeridosClientes = [];
  bool _showClientSuggestions = false;

  // Inline product adding state
  bool _isAddingArticleInline = false;
  final TextEditingController _prodNombreCtrl = TextEditingController();
  final TextEditingController _prodPrecioCtrl = TextEditingController();
  final TextEditingController _prodCantCtrl = TextEditingController(text: "1");
  final FocusNode _prodNombreFocusNode = FocusNode();
  Articulo? _selectedCatalogArticulo;
  List<Articulo> _filtradosProd = [];
  bool _showProdSuggestions = false;
  int? _editingItemIndex;

  List<Articulo> _catalogArticulos = [];
  List<String> _unidadesMedida = [];
  String _seleccionUnidadMedida = "Unidad";
  String _metodoPago = "Transferencia Bancaria";
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
        
        _vendedorSeleccionado ??= (widget.notaExistente?['vendedor']?.toString().isNotEmpty ?? false)
            ? widget.notaExistente!['vendedor'].toString()
            : userDisplay;
            
        _sucursalSeleccionada ??= (widget.notaExistente?['sucursal']?.toString().isNotEmpty ?? false)
            ? widget.notaExistente!['sucursal'].toString()
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
    final selected = await SelectSucursalModal.show(context, initialSelected: _sucursalSeleccionada);
    if (selected != null && mounted) {
      setState(() {
        _sucursalSeleccionada = selected;
      });
    }
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


  @override
  void initState() {
    super.initState();
    _loadClientes();
    _loadCatalogData();
    _loadVendedoresYSucursales();
    if (widget.displayId != null) {
      _displayId = widget.displayId;
    }
    if (widget.notaExistente != null) {
      _cargarNota(widget.notaExistente!);
      _currentStep = 2;
    }
    if (widget.convertFromQuote != null) {
      final cot = widget.convertFromQuote!;
      _clienteNombreCtrl.text = cot['clienteNombre']?.toString() ?? '';
      _notasController.text = cot['notas']?.toString() ?? '';
      _descuentoPorcentaje = (cot['descuentoPorcentaje'] as num?)?.toDouble() ?? 0.0;
      _incluyeFirmaEmpresa = (cot['incluyeFirmaEmpresa'] ?? 0) == 1;
      _incluyeFirmaCliente = (cot['incluyeFirmaCliente'] ?? 0) == 1;
      _mostrarTerminos = (cot['mostrarTerminos'] ?? 1) == 1;
      
      try {
        final List<dynamic> itemsList = jsonDecode(cot['itemsJson'] ?? '[]');
        _items.clear();
        _items.addAll(itemsList.map((itemMap) => ItemCotizacion.fromMap(itemMap)).toList());
      } catch (e) {
        debugPrint("Error decodificando items de cotización para nota: $e");
      }
    }
    _prodNombreFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadClientes() async {
    try {
      final list = await DatabaseHelper.instance.queryAllClientes();
      setState(() {
        _todosClientes = list.map((c) => Cliente.fromMap(c)).toList();
      });
      if (widget.notaExistente != null) {
        final name = widget.notaExistente!['clienteNombre'] as String?;
        if (name != null && name.isNotEmpty && name.trim().toLowerCase() != 'sin cliente' && name.trim().toLowerCase() != 'sin cliente asignado') {
          final match = _todosClientes.firstWhere(
            (c) => c.nombreCompania.toLowerCase() == name.toLowerCase(),
            orElse: () => Cliente(nombreCompania: name, telefono: "", correo: ""),
          );
          _clienteTelefonoCtrl.text = match.telefono;
          _clienteCorreoCtrl.text = match.correo;
        }
      }
    } catch (e) {
      debugPrint("Error loading clientes: $e");
    }
  }

  @override
  void dispose() {
    _clienteNombreCtrl.dispose();
    _clienteTelefonoCtrl.dispose();
    _clienteCorreoCtrl.dispose();
    _notasController.dispose();
    _terminosController.dispose();
    _prodNombreCtrl.dispose();
    _prodPrecioCtrl.dispose();
    _prodCantCtrl.dispose();
    _prodNombreFocusNode.dispose();
    super.dispose();
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
      _prodNombreCtrl.clear();
      _prodPrecioCtrl.clear();
      _prodCantCtrl.text = "1";
      _selectedCatalogArticulo = null;
      _isAddingArticleInline = false;
    });
    _guardarNotaSilently();
  }

  Future<void> _guardarNotaSilently() async {
    if (_idNotaExistente == null && widget.notaExistente == null) return;
    try {
      final String clienteNombreText = _clienteNombreCtrl.text.trim();
      final nota = {
        if (_idNotaExistente != null) 'id': _idNotaExistente,
        'uuid': _uuid,
        'displayId': _displayId,
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
        'tipo_venta': widget.tipoVenta,
        'vendedor': _vendedorSeleccionado ?? _vendedorOriginal ?? (Session().userName ?? ''),
        'sucursal': _sucursalSeleccionada ?? (_listaSucursales.isNotEmpty ? _listaSucursales.first : ''),
        'metodo_pago': _metodoPago,
        'comprobado': _comprobado,
      };
      if (_idNotaExistente != null) {
        await DatabaseHelper.instance.updateNotaEntrega(nota);
        await DatabaseHelper.instance.setTableDirty('notas_entrega');
        SyncService.instance.syncTable('notas_entrega').catchError((_) {});
      }
    } catch (e) {
      debugPrint("Error auto-guardando nota de entrega: $e");
    }
  }

  Widget _buildStepper(int activeStep) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = const Color(0xFFEFA820);
    final inactiveBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final inactiveText = isDark ? Colors.white38 : Colors.black38;
    final activeText = isDark ? Colors.white : Colors.black87;

    Widget buildStepItem(int stepNum, String title) {
      final bool isActive = activeStep == stepNum;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isActive ? activeColor : inactiveBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              stepNum.toString(),
              style: TextStyle(
                color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: isActive ? activeText : inactiveText,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    Widget buildLine() {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Container(
            height: 2,
            color: isDark ? Colors.white10 : Colors.grey[200]!,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          buildStepItem(1, "Cliente"),
          buildLine(),
          buildStepItem(2, "Artículos"),
          buildLine(),
          buildStepItem(3, "Resumen"),
        ],
      ),
    );
  }

  Widget _buildBottomButton(String text, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEFA820),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 2,
        ),
        onPressed: onPressed,
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
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
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              _buildVendedorSucursalCard(isDark, textColor, isDark ? Colors.white70 : const Color(0xFF64748B)),
              Text(
                "Datos del cliente",
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: EdgeInsets.zero,
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _clienteNombreCtrl,
                      style: TextStyle(color: textColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "",
                        hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                        prefixIcon: const Icon(Icons.business_rounded, color: Colors.grey, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.contacts_rounded, color: AppColors.primaryPurple, size: 22),
                          tooltip: "Buscar / Registrar Cliente",
                          onPressed: () async {
                            final cli = await SelectClienteModal.show(context);
                            if (cli != null && mounted) {
                              setState(() {
                                _clienteNombreCtrl.text = cli.nombreCompania;
                                _clienteTelefonoCtrl.text = cli.telefono;
                                _clienteCorreoCtrl.text = cli.correo;
                                _showClientSuggestions = false;
                              });
                            }
                          },
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFFEFA820), width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.black38 : Colors.grey[50],
                      ),
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
                                backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.grey[200],
                                side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                label: Text(
                                  cli.nombreCompania,
                                  style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: _clienteTelefonoCtrl,
                      style: TextStyle(color: textColor, fontSize: 14),
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: "",
                        hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                        prefixIcon: const Icon(Icons.phone_rounded, color: Colors.grey, size: 20),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFFEFA820), width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.black38 : Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _clienteCorreoCtrl,
                      style: TextStyle(color: textColor, fontSize: 14),
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: "",
                        hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                        prefixIcon: const Icon(Icons.email_rounded, color: Colors.grey, size: 20),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFFEFA820), width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.black38 : Colors.grey[50],
                      ),
                    ),
                  ],
                ),
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

  Widget _buildStep2() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              Text(
                "Añadir Artículo",
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              // Formulario inline si está expandido
              if (_isAddingArticleInline)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131A26) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFEFA820), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _prodNombreCtrl,
                        focusNode: _prodNombreFocusNode,
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "Nombre del producto",
                          hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Color(0xFFEFA820), width: 1.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: isDark ? Colors.black38 : Colors.grey[50],
                        ),
                        onChanged: (val) {
                          _filterProdSuggestions(val);
                          setState(() {
                            _showProdSuggestions = true;
                          });
                        },
                      ),
                      if (_showProdSuggestions && (_filtradosProd.isNotEmpty || _catalogArticulos.isNotEmpty)) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E222B) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: (_filtradosProd.isEmpty ? _catalogArticulos : _filtradosProd).length,
                            separatorBuilder: (context, i) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final list = _filtradosProd.isEmpty ? _catalogArticulos : _filtradosProd;
                              final a = list[i];
                              return ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        a.nombre,
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "${a.precio.toStringAsFixed(1)} Bs | ${a.unidad.isNotEmpty ? a.unidad : 'Unidad'}",
                                      style: const TextStyle(
                                        color: Color(0xFFEFA820),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  final cant = int.tryParse(_prodCantCtrl.text.trim()) ?? 1;
                                  final int cantidadToAdd = cant <= 0 ? 1 : cant;

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
                                    _prodCantCtrl.text = "1";
                                    _selectedCatalogArticulo = null;
                                    _showProdSuggestions = false;
                                    _isAddingArticleInline = false;
                                  });
                                  _prodNombreFocusNode.unfocus();
                                },
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          // Precio
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _prodPrecioCtrl,
                              style: TextStyle(color: textColor, fontSize: 14),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                hintText: "Bs. 000",
                                hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Color(0xFFEFA820), width: 1.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: isDark ? Colors.black38 : Colors.grey[50],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Cantidad Counter: - X +
                          Expanded(
                            flex: 3,
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black38 : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 20),
                                    onPressed: () {
                                      final current = int.tryParse(_prodCantCtrl.text) ?? 1;
                                      if (current > 1) {
                                        setState(() {
                                          _prodCantCtrl.text = (current - 1).toString();
                                        });
                                      }
                                    },
                                  ),
                                  SizedBox(
                                    width: 45,
                                    child: TextField(
                                      controller: _prodCantCtrl,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                                        border: InputBorder.none,
                                      ),
                                      onChanged: (val) {
                                        if (val.isEmpty) {
                                          _prodCantCtrl.text = "1";
                                          _prodCantCtrl.selection = TextSelection.fromPosition(
                                            TextPosition(offset: _prodCantCtrl.text.length),
                                          );
                                        }
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 20),
                                    onPressed: () {
                                      final current = int.tryParse(_prodCantCtrl.text) ?? 1;
                                      setState(() {
                                        _prodCantCtrl.text = (current + 1).toString();
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Unidad de Medida
                          Expanded(
                            flex: 3,
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black38 : Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _seleccionUnidadMedida,
                                  dropdownColor: isDark ? const Color(0xFF1E222B) : Colors.white,
                                  style: TextStyle(color: textColor, fontSize: 13),
                                  items: _unidadesMedida.map((u) {
                                    return DropdownMenuItem<String>(
                                      value: u,
                                      child: Text(u),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _seleccionUnidadMedida = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isAddingArticleInline = false;
                                _editingItemIndex = null;
                                _prodNombreCtrl.clear();
                                _prodPrecioCtrl.clear();
                                _prodCantCtrl.text = "1";
                              });
                            },
                            child: const Text("Cancelar", style: TextStyle(color: Colors.redAccent)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey[700],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _saveItemInline,
                            child: const Text("Guardar"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              // Listado de artículos ya agregados
              if (_items.isNotEmpty)
                Column(
                  children: List.generate(_items.length, (i) {
                    final item = _items[i];
                    return Container(
                      key: ValueKey(item),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131A26) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
                      ),
                      child: ListTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${i + 1}",
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.inventory_2, color: Color(0xFFEFA820), size: 32),
                          ],
                        ),
                        title: Text(item.articulo.nombre, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                        subtitle: Text("${item.cantidad} x ${item.precioOriginal.toStringAsFixed(2)} Bs = ${item.total.toStringAsFixed(2)} Bs"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (i > 0)
                              IconButton(
                                icon: const Icon(Icons.arrow_upward, color: Colors.grey, size: 18),
                                onPressed: () {
                                  setState(() {
                                    final item = _items.removeAt(i);
                                    _items.insert(i - 1, item);
                                    _isSaved = false;
                                  });
                                },
                              ),
                            if (i < _items.length - 1)
                              IconButton(
                                icon: const Icon(Icons.arrow_downward, color: Colors.grey, size: 18),
                                onPressed: () {
                                  setState(() {
                                    final item = _items.removeAt(i);
                                    _items.insert(i + 1, item);
                                    _isSaved = false;
                                  });
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 20),
                              onPressed: () => _startEditingItem(i),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              onPressed: () {
                                setState(() {
                                  _items.removeAt(i);
                                  _isSaved = false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              // Botón punteado "+ Añadir nuevo artículo"
              if (!_isAddingArticleInline)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isAddingArticleInline = true;
                      _editingItemIndex = null;
                      _prodNombreCtrl.clear();
                      _prodPrecioCtrl.clear();
                      _prodCantCtrl.text = "1";
                    });
                  },
                  child: Container(
                    height: 60,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.02) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFEFA820).withOpacity(0.5),
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.add, color: Color(0xFFEFA820)),
                        SizedBox(width: 8),
                        Text(
                          "Añadir nuevo artículo",
                          style: TextStyle(color: Color(0xFFEFA820), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Builder(
          builder: (context) {
            final bool showSiguiente = _items.isNotEmpty && !_isAddingArticleInline && _editingItemIndex == null;
            return AnimatedSlide(
              offset: showSiguiente ? Offset.zero : const Offset(0, 1.2),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: showSiguiente ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: IgnorePointer(
                  ignoring: !showSiguiente,
                  child: _buildBottomButton("Siguiente", () {
                    if (!showSiguiente) return;
                    setState(() {
                      _currentStep = 3;
                    });
                  }),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStep3() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secTextColor = isDark ? Colors.white70 : Colors.black87;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            children: [
              // 0. Toggle Pill Switch [ Proforma ] | [ Nota de entrega ] (solo cuando hay cliente o artículos)
              if (_clienteNombreCtrl.text.trim().isNotEmpty || _items.isNotEmpty) ...[
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
                                ? const Color(0xFF5842F4)
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
                                  : (isDark ? secTextColor : const Color(0xFF5842F4)),
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
                                ? const Color(0xFF5842F4)
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
                                  : (isDark ? secTextColor : const Color(0xFF5842F4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

              Text(
                "Resumen de la nota de entrega",
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 24),

              // Sección Cliente
              Text(
                "Cliente",
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _clienteNombreCtrl.text,
                style: TextStyle(color: secTextColor, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (_clienteTelefonoCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _clienteTelefonoCtrl.text,
                  style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 14),
                ),
              ],
              if (_clienteCorreoCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _clienteCorreoCtrl.text,
                  style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 14),
                ),
              ],
              const SizedBox(height: 24),
              Divider(color: isDark ? Colors.white10 : Colors.grey[200]!),
              const SizedBox(height: 16),

              // Sección Artículos
              Text(
                "Artículos",
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              ...List.generate(_items.length, (index) {
                final item = _items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.articulo.nombre,
                              style: TextStyle(color: secTextColor, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "${item.cantidad} x Bs. ${item.precioOriginal.toStringAsFixed(2)}",
                              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "Bs. ${item.total.toStringAsFixed(2)}",
                        style: TextStyle(color: secTextColor, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              Divider(color: isDark ? Colors.white10 : Colors.grey[200]!),
              const SizedBox(height: 16),

              // Resumen Financiero
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Subtotal", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15)),
                  Text("Bs. ${_subtotal.toStringAsFixed(2)}", style: TextStyle(color: textColor, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 12),
              // Slider interactivo de descuento
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Descuento (${_descuentoPorcentaje.toStringAsFixed(0)}%)",
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15),
                        ),
                        Slider(
                          value: _descuentoPorcentaje,
                          min: 0,
                          max: 100,
                          divisions: 20,
                          activeColor: const Color(0xFFEFA820),
                          onChanged: (val) {
                            setState(() {
                              _descuentoPorcentaje = val;
                              _isSaved = false;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text("Bs. ${_montoDescuento.toStringAsFixed(2)}", style: TextStyle(color: textColor, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Total", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    "Bs. ${_total.toStringAsFixed(2)}",
                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: isDark ? Colors.white10 : Colors.grey[200]!),
              const SizedBox(height: 16),

              // Sección Método de Pago
              Text(
                "Método de pago",
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (context) {
                      final methods = ["Transferencia Bancaria", "Efectivo", "QR", "Tarjeta de Crédito/Débito"];
                      return SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: methods.map((m) {
                            return ListTile(
                              title: Text(m, style: TextStyle(color: textColor)),
                              trailing: _metodoPago == m ? const Icon(Icons.check, color: Color(0xFFEFA820)) : null,
                              onTap: () {
                                setState(() {
                                  _metodoPago = m;
                                });
                                Navigator.pop(context);
                              },
                            );
                          }).toList(),
                        ),
                      );
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E222B) : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _metodoPago,
                        style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      Icon(Icons.chevron_right, color: isDark ? Colors.white54 : Colors.black54),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Divider(color: isDark ? Colors.white10 : Colors.grey[200]!),
              const SizedBox(height: 16),

              // Opciones de Impresión / Sello
              Text(
                "Opciones de impresión / Sello",
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Incluir sello", style: TextStyle(fontSize: 14)),
                value: _incluyeFirmaEmpresa,
                activeColor: const Color(0xFFEFA820),
                onChanged: (val) => setState(() { _incluyeFirmaEmpresa = val; _isSaved = false; }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Mostrar Términos", style: TextStyle(fontSize: 14)),
                value: _mostrarTerminos,
                activeColor: const Color(0xFFEFA820),
                onChanged: (val) => setState(() { _mostrarTerminos = val; _isSaved = false; }),
              ),
              if (_mostrarTerminos) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _terminosController,
                  maxLines: 4,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "Escriba aquí los términos...",
                    hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38),
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (val) {
                    setState(() => _isSaved = false);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        // Guardar/PDF Buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEFA820),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 2,
                ),
                icon: Icon(_isSaved ? Icons.check : Icons.save),
                label: Text(_isSaved ? "GUARDADO CORRECTAMENTE" : "Generar nota de entrega"),
                onPressed: () async {
                  final saved = await _guardarNota();
                  if (saved && mounted) {
                    NovaledToast.notaEntregaGenerada(context);
                    _generarPDF();
                  }
                },
              ),
              if (_isSaved) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.print, size: 16),
                        label: const Text("IMPRIMIR", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: _generarPDF,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEFA820),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text("DESCARGAR", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: _descargarComoPDF,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.share, size: 16),
                        label: const Text("COMPARTIR", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final currentBytes = await PdfService.generateCotizacionBytes(
                            clienteNombre: _clienteNombreCtrl.text,
                            items: _items,
                            subtotalOriginal: _subtotalOriginal,
                            ahorroItems: _ahorroTotalItems,
                            descuentoGlobal: _montoDescuento,
                            total: _total,
                            notas: _notasController.text,
                            terminos: _terminosController.text,
                            docId: _displayId ?? 0,
                            incluyeFirmaEmpresa: _incluyeFirmaEmpresa,
                            incluyeFirmaCliente: _incluyeFirmaCliente,
                            tituloDocumento: "NOTA DE ENTREGA",
                            isColor: _isColor,
                            fecha: _fechaDocumento ?? DateTime.now().toIso8601String().substring(0, 10),
                            sucursal: _sucursalSeleccionada ?? (_listaSucursales.isNotEmpty ? _listaSucursales.first : ''),
                            vendedor: _vendedorSeleccionado ?? _vendedorOriginal ?? (Session().userName ?? ''),
                          );
                          await Printing.sharePdf(
                            bytes: currentBytes,
                            filename: 'NotaEntrega_${_displayId ?? 0}.pdf',
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _cargarNota(Map<String, dynamic> data) {
    _idNotaExistente = data['id'];
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
    _comprobado = data['comprobado'] as int? ?? 0;
    _mostrarNotas = _notasController.text.trim().isNotEmpty;
    _vendedorOriginal = data['vendedor']?.toString();
    if (data['sucursal'] != null && data['sucursal'].toString().trim().isNotEmpty && data['sucursal'].toString() != 'null') {
      _sucursalSeleccionada = data['sucursal'].toString().trim();
    }
    if (data['vendedor'] != null && data['vendedor'].toString().trim().isNotEmpty && data['vendedor'].toString() != 'null') {
      _vendedorSeleccionado = data['vendedor'].toString().trim();
    }

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
                });
                final success = await _guardarNota();
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Documento guardado y marcado 'Por Cobrar'"),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text("ACEPTAR", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0C10) : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF161A22) : Colors.white,
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
                color: isDark ? Colors.white : Colors.black87,
              ),
              onPressed: () {
                if (_currentStep > 1) {
                  setState(() {
                    _currentStep--;
                  });
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          ),
        ),
        title: Text(
          _idNotaExistente != null ? "Editar Nota de Entrega" : "Nueva Nota de Entrega",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: const [],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_prodNombreFocusNode.hasFocus) _buildStepper(_currentStep),
            Expanded(
              child: _buildStepBody(),
            ),
          ],
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                  backgroundColor: isDark ? const Color(0xFF161A22) : Colors.white,
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
                          _buildVendedorSucursalCard(isDark, textColor, isDark ? Colors.white70 : const Color(0xFF64748B)),
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
                _guardarNotaSilently();
              }
            },
            onDelete: () {
              setState(() {
                _items.removeAt(index);
                _isSaved = false;
              });
              _guardarNotaSilently();
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
    }
  }

  Future<bool> _guardarNota() async {
    try {
      final String clienteNombreText = _clienteNombreCtrl.text.trim();
      if (clienteNombreText.isEmpty || _items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error: Ingrese cliente y artículos primero"), backgroundColor: Colors.red),
        );
        return false;
      }

      // Verificar si el cliente existe por nombre (insensible a mayúsculas/minúsculas)
      Cliente? matchedCliente;
      try {
        matchedCliente = _todosClientes.firstWhere(
          (c) => c.nombreCompania.toLowerCase() == clienteNombreText.toLowerCase(),
        );
      } catch (_) {
        // No existe
      }

      if (matchedCliente != null) {
        // Si existe y cambió su tlf o correo, actualizarlo
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
        // Si no existe, crearlo
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
        _loadClientes();
      }

      _fechaDocumento ??= DateTime.now().toString().split('.')[0];
      final Map<String, dynamic> nota = {
        'id': _idNotaExistente,
        'uuid': _uuid,
        'clienteNombre': clienteNombreText,
        'fecha': _fechaDocumento,
        'subtotal': _subtotal,
        'descuento': _montoDescuento,
        'descuentoPorcentaje': _descuentoPorcentaje,
        'total': _total,
        'notes': _notasController.text,
        'notas': _notasController.text,
        'terminos': _terminosController.text,
        'incluyeFirmaEmpresa': _incluyeFirmaEmpresa ? 1 : 0,
        'incluyeFirmaCliente': _incluyeFirmaCliente ? 1 : 0,
        'mostrarTerminos': _mostrarTerminos ? 1 : 0,
        'mostrarAhorro': _mostrarAhorro ? 1 : 0,
        'itemsJson': jsonEncode(_items.map((i) => i.toMap()).toList()),
        'tipo_venta': widget.tipoVenta,
        'vendedor': _vendedorSeleccionado ?? _vendedorOriginal ?? (Session().userName ?? ''),
        'sucursal': _sucursalSeleccionada ?? (_listaSucursales.isNotEmpty ? _listaSucursales.first : ''),
        'metodo_pago': _metodoPago,
        'comprobado': _comprobado,
      };

      int savedId;
      if (_idNotaExistente != null) {
        await DatabaseHelper.instance.updateNotaEntrega(nota);
        savedId = _idNotaExistente!;
        final uuidToUse = _uuid ?? '';
        if (uuidToUse.isNotEmpty) {
          final db = await DatabaseHelper.instance.database;
          for (var t in ['proformas', 'notas_entrega', 'cotizaciones']) {
            try {
              await DatabaseHelper.instance.setTableDirty(t);
              await db.update(
                t,
                {'sucursal': nota['sucursal'], 'vendedor': nota['vendedor']},
                where: 'uuid = ?',
                whereArgs: [uuidToUse],
              );
            } catch (_) {}
          }
        }
      } else {
        final canCreate = await PlanLimitHelper.canCreateNotaEntrega();
        if (!canCreate) {
          setState(() => _isSaved = false);
          if (mounted) {
            PlanLimitHelper.showUpgradeDialog(context, feature: "notas de entrega", currentLimit: PlanLimitHelper.freeNotasEntrega);
          }
          return false;
        }
        savedId = await DatabaseHelper.instance.insertNotaEntrega(nota);
        try {
          final newlyInserted = await DatabaseHelper.instance.queryAllNotasEntrega();
          final match = newlyInserted.firstWhere((element) => element['id'] == savedId);
          _uuid = match['uuid']?.toString();
        } catch (e) {
          debugPrint("Error retrieving generated UUID: $e");
        }
      }

      int computedDisplayId;
      if (_displayId != null) {
        computedDisplayId = _displayId!;
      } else {
        final all = await DatabaseHelper.instance.queryAllNotasEntrega();
        computedDisplayId = all.length;
      }

      setState(() {
        _isSaved = true;
        _idNotaExistente = savedId;
        _displayId = computedDisplayId;
      });

      // Background Sync:
      final fullData = await DatabaseHelper.instance.queryAllNotasEntrega();
      final currentItem = fullData.firstWhere((element) => element['id'] == savedId, orElse: () => nota);
      _drive.syncItemToDrive('notas_entrega', Map<String, dynamic>.from(currentItem)).then((newFolderId) async {
        if (newFolderId != null && newFolderId != currentItem['folderId']) {
          final updated = Map<String, dynamic>.from(currentItem);
          updated['folderId'] = newFolderId;
          await DatabaseHelper.instance.updateNotaEntrega(updated);
        }
        // Sincronizar también con MySQL (Hostinger) en segundo plano
        SyncService.instance.syncEverything().catchError((e) {
          debugPrint("Silent Hostinger sync error: $e");
        });
      });

      // Sincronizar Cotización vinculada con Google Drive
      try {
        final String? docUuid = currentItem['uuid']?.toString() ?? nota['uuid']?.toString();
        if (docUuid != null && docUuid.isNotEmpty) {
          final allCot = await DatabaseHelper.instance.queryAllCotizaciones();
          final matchCot = allCot.firstWhere((c) => c['uuid']?.toString() == docUuid);
          _drive.syncItemToDrive('cotizaciones', Map<String, dynamic>.from(matchCot)).then((newFolderId) async {
            if (newFolderId != null && newFolderId != matchCot['folderId']) {
              final updated = Map<String, dynamic>.from(matchCot);
              updated['folderId'] = newFolderId;
              await DatabaseHelper.instance.updateCotizacion(updated);
            }
          });
        }
      } catch (e) {
        debugPrint("Error syncing linked cotizacion to Drive: $e");
      }

      if (!mounted) return true;
      return true;
    } catch (e, stack) {
      debugPrint("Error al guardar nota de entrega: $e\n$stack");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.red),
        );
      }
      return false;
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
        final all = await DatabaseHelper.instance.queryAllNotasEntrega();
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
        tituloDocumento: "NOTA DE ENTREGA",
        isColor: _isColor,
        fecha: _fechaDocumento,
        sucursal: _sucursalSeleccionada ?? (_listaSucursales.isNotEmpty ? _listaSucursales.first : ''),
        vendedor: _vendedorSeleccionado ?? _vendedorOriginal ?? (Session().userName ?? ''),
      );

      final filename = "NotaEntrega_NOTA-$formattedId.pdf";

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
        final all = await DatabaseHelper.instance.queryAllNotasEntrega();
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
        fecha: _fechaDocumento,
        tituloDocumento: "NOTA DE ENTREGA",
      );

      final filename = "NotaEntrega_NOTA-$formattedId.docx";

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
      final all = await DatabaseHelper.instance.queryAllNotasEntrega();
      previewId = all.length + 1;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CotizacionVistaPreviaScreen(
          titulo: "Nota de entrega",
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
          tituloDocumento: "NOTA DE ENTREGA",
          fecha: _fechaDocumento,
          sucursal: _sucursalSeleccionada ?? (_listaSucursales.isNotEmpty ? _listaSucursales.first : ''),
          vendedor: _vendedorSeleccionado ?? _vendedorOriginal ?? (Session().userName ?? ''),
          returnButtonText: "Volver a notas de entrega",
          onEdit: () => Navigator.pop(context),
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
