import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../database_helper.dart';
import '../models/cliente.dart';
import '../models/articulo.dart';
import '../models/item_cotizacion.dart';
import '../services/pdf_service.dart';
import '../../drive_service.dart';
import '../services/sync_service.dart';
import 'agregar_articulo_screen.dart';
import '../../login_screen.dart';
import '../widgets/zoomable_pdf_preview.dart';
import '../widgets/novaled_thick_icon.dart';
import 'cotizacion_vista_previa_screen.dart';
import '../tenant_helper.dart';

class CrearCotizacionEscaneadaScreen extends StatefulWidget {
  final Map<String, dynamic>? cotizacionExistente;
  final int? displayId;
  final String tipoVenta;
  final List<XFile>? initialImages;

  const CrearCotizacionEscaneadaScreen({
    super.key,
    this.cotizacionExistente,
    this.displayId,
    this.tipoVenta = 'punto_venta',
    this.initialImages,
  });

  @override
  State<CrearCotizacionEscaneadaScreen> createState() => _CrearCotizacionEscaneadaScreenState();
}

class _CrearCotizacionEscaneadaScreenState extends State<CrearCotizacionEscaneadaScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];
  bool _isLoadingScan = false;
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
  bool _isColor = true;
  bool _mostrarAhorro = false;
  bool _mostrarTerminos = false;
  final DriveService _drive = DriveService();
  String? _fechaDocumento;
  String? _uuid;
  bool _mostrarNotas = false;
  String? _vendedorOriginal;

  // Nuevas variables para clientes flexibles
  final TextEditingController _clienteNombreCtrl = TextEditingController();
  final TextEditingController _clienteTelefonoCtrl = TextEditingController();
  final TextEditingController _clienteCorreoCtrl = TextEditingController();
  List<Cliente> _todosClientes = [];
  final List<int> _newArticlesCreatedIds = [];


  @override
  void initState() {
    super.initState();
    _loadClientes();
    if (widget.displayId != null) {
      _displayId = widget.displayId;
    }
    if (widget.cotizacionExistente != null) {
      _cargarCotizacion(widget.cotizacionExistente!);
    }
    if (widget.initialImages != null && widget.initialImages!.isNotEmpty) {
      _selectedImages.addAll(widget.initialImages!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _procesarConIA();
      });
    }
  }



  @override
  void dispose() {
    _clienteNombreCtrl.dispose();
    _clienteTelefonoCtrl.dispose();
    _clienteCorreoCtrl.dispose();
    _notasController.dispose();
    _terminosController.dispose();
    super.dispose();
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
    } catch (e) {
      debugPrint("Error loading clientes: $e");
    }
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
    _mostrarNotas = _notasController.text.trim().isNotEmpty;
    _vendedorOriginal = data['vendedor']?.toString();

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0C10) : Colors.grey[50],
      appBar: AppBar(
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
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: Text(
          _idCotizacionExistente != null ? "Editar Cotización" : "Nueva Cotización",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
            height: 1.0,
          ),
        ),
        actions: [
          if (_items.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 24),
              color: const Color(0xFF00ADEF),
              onPressed: _showConfigMenu,
              tooltip: "Configuración extra",
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFFF6600), size: 24),
              onPressed: _clienteNombreCtrl.text.trim().isEmpty ? null : _generarPDF,
              tooltip: "Generar PDF",
            ),
            const SizedBox(width: 4),
            _GlowingCheckButton(
              glow: _isSaved,
              onPressed: _clienteNombreCtrl.text.trim().isEmpty
                  ? null
                  : () async {
                      await _guardarCotizacion();
                    },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 20),
                  children: [
                    _buildClientSelector(),
                    const Divider(color: Colors.white10, height: 1),
                    if (_items.isEmpty)
                      _buildEmptyState()
                    else
                      _buildItemsList(),
                    if (_items.isNotEmpty && _mostrarNotas)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: _buildNotesField(),
                      ),
                  ],
                ),
              ),
              if (_items.isNotEmpty)
                _buildSummary(),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.purpleAccent.withOpacity(isDark ? 0.15 : 0.08),
                      Colors.purpleAccent.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [Colors.white, Colors.grey[100]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.purpleAccent.withOpacity(0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purpleAccent.withOpacity(isDark ? 0.15 : 0.06),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  size: 48,
                  color: Colors.purpleAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "Cotización Flash con IA",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Seleccione o tome las fotos de la cotización impresa o digital (sin límite de imágenes). La IA extraerá los artículos, buscará en el inventario y los agregará automáticamente.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          
          // Área de imágenes seleccionadas
          if (_selectedImages.isNotEmpty) ...[
            Container(
              height: 110,
              margin: const EdgeInsets.only(bottom: 20),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.purpleAccent.withOpacity(0.5)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: kIsWeb
                            ? Image.network(
                                _selectedImages[index].path,
                                fit: BoxFit.cover,
                              )
                            : Image.file(
                                File(_selectedImages[index].path),
                                fit: BoxFit.cover,
                              ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.red,
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 8, color: Colors.white),
                            onPressed: () => _removeImage(index),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.add_a_photo_rounded, size: 16),
                label: Text(
                  _selectedImages.isEmpty ? "SELECCIONAR FOTOS" : "AGREGAR FOTOS (${_selectedImages.length})",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00ADEF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
              if (_selectedImages.isNotEmpty) ...[
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isLoadingScan ? null : _procesarConIA,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text(
                    "PROCESAR CON IA",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Paso 1: Seleccione imágenes y pulse Procesar",
            style: TextStyle(
              color: isDark ? Colors.grey[600] : Colors.grey[500],
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImages() async {
    final canScan = await PlanLimitHelper.canScan();
    if (!canScan) {
      if (mounted) {
        final isFree = await TenantHelper.isFreePlan();
        PlanLimitHelper.showUpgradeDialog(
          context,
          feature: "escaneos mágicos por mes",
          currentLimit: isFree ? PlanLimitHelper.freeEscaneos : PlanLimitHelper.proEscaneos,
        );
      }
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161A22) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                "Agregar Fotos (Sin Límite)",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF00ADEF)),
                title: Text(
                  "Galería (Seleccionar varias fotos)",
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final List<XFile> images = await _picker.pickMultiImage(imageQuality: 85);
                    if (images.isNotEmpty && mounted) {
                      setState(() {
                        _selectedImages.addAll(images);
                      });
                    }
                  } catch (e) {
                    debugPrint("Error picking multi image: $e");
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF00ADEF)),
                title: Text(
                  "Cámara (Tomar foto)",
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                    if (image != null && mounted) {
                      setState(() {
                        _selectedImages.add(image);
                      });
                    }
                  } catch (e) {
                    debugPrint("Error taking photo: $e");
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _procesarConIA() async {
    if (_selectedImages.isEmpty) return;

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

    setState(() => _isLoadingScan = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF131A26)
                : Colors.white,
            content: Row(
              children: [
                const CircularProgressIndicator(color: Color(0xFF00ADEF)),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    "Escaneando con IA (ChatGPT)...\nBuscando y creando artículos en el inventario...",
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
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

      for (int i = 0; i < _selectedImages.length; i++) {
        final path = _selectedImages[i].path;
        final file = await http.MultipartFile.fromPath('images[]', path);
        request.files.add(file);
      }

      final responseStream = await request.send();
      final response = await http.Response.fromStream(responseStream);

      if (mounted) Navigator.pop(context); // Cerrar diálogo

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        if (resJson['success'] == true && resJson['items'] is List) {
          final itemsList = resJson['items'] as List;

          // Procesar cliente si viene en la respuesta de la IA
          if (resJson['cliente'] != null && resJson['cliente'] is Map) {
            final clientMap = Map<String, dynamic>.from(resJson['cliente']);
            final String? detectedClientName = clientMap['nombre']?.toString().trim();
            final String detectedClientPhone = clientMap['telefono']?.toString().trim() ?? '';
            final String detectedClientEmail = clientMap['correo']?.toString().trim() ?? '';

            if (detectedClientName != null && detectedClientName.isNotEmpty) {
              Cliente? matchedClient;
              // Buscar en _todosClientes
              try {
                matchedClient = _todosClientes.firstWhere(
                  (c) => c.nombreCompania.toLowerCase().trim() == detectedClientName.toLowerCase(),
                );
              } catch (_) {
                // Intentar búsqueda por subcadena (sólo para nombres de 5 o más caracteres para evitar falsos positivos como letras sueltas o palabras muy cortas)
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
                // Si no existe el cliente, crearlo e insertarlo
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

                // Sincronizar clientes con el servidor en segundo plano
                SyncService.instance.syncTable('clientes').catchError((e) {
                  debugPrint("Error al sincronizar nuevo cliente escaneado: $e");
                });
              }
            }
          }
          
          final allArticulosMap = await DatabaseHelper.instance.queryAllArticulos();
          final allArticulos = allArticulosMap.map((e) => Articulo.fromMap(e)).toList();

          int itemsJalados = 0;
          int itemsCreados = 0;

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
                  : "Creado automáticamente vía escaneo",
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
            itemsCreados++;
          }

          PlanLimitHelper.incrementScanCount();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Escaneo completo: $itemsJalados jalados, $itemsCreados creados automáticamente."),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw Exception("Respuesta del servidor inválida");
        }
      } else {
        final errJson = jsonDecode(response.body);
        throw Exception(errJson['error'] ?? "Código de error ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al procesar: ${e.toString().replaceFirst("Exception: ", "")}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoadingScan = false);
    }
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
              }
            },
            onDelete: () {
              setState(() {
                _items.removeAt(index);
                _isSaved = false;
              });
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
    final n = _items.length;
    final currentPos = index + 1;
    final textController = TextEditingController(text: currentPos.toString());

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
                "Mover artículo",
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
            const Text(
              "Cambia la posición del artículo en el documento.",
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Text(
              "Posición actual: #$currentPos",
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
                  SnackBar(content: Text("Por favor ingrese un número válido entre 1 y $n")),
                );
              }
            },
            child: const Text("MOVER", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
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
        _items.addAll(result);
        _isSaved = false;
      });
    }
  }

  Future<bool> _guardarCotizacion() async {
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
    final Map<String, dynamic> cotizacion = {
      'id': _idCotizacionExistente,
      'uuid': _uuid,
      'clienteNombre': clienteNombreText,
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
      'vendedor': _vendedorOriginal ?? Session().userName ?? 'Dueño',
    };

    int savedId;
    if (_idCotizacionExistente != null) {
      await DatabaseHelper.instance.updateCotizacion(cotizacion);
      savedId = _idCotizacionExistente!;
    } else {
      savedId = await DatabaseHelper.instance.insertCotizacion(cotizacion);
      try {
        final newlyInserted = await DatabaseHelper.instance.queryAllCotizaciones();
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
      final all = await DatabaseHelper.instance.queryAllCotizaciones();
      computedDisplayId = all.length;
    }

    setState(() {
      _isSaved = true;
      _idCotizacionExistente = savedId;
      _displayId = computedDisplayId;
    });

    // Background Sync:
    final fullData = await DatabaseHelper.instance.queryAllCotizaciones();
    final currentItem = fullData.firstWhere((element) => element['id'] == savedId, orElse: () => cotizacion);
    _drive.syncItemToDrive('cotizaciones', Map<String, dynamic>.from(currentItem)).then((newFolderId) async {
      if (newFolderId != null && newFolderId != currentItem['folderId']) {
        final updated = Map<String, dynamic>.from(currentItem);
        updated['folderId'] = newFolderId;
        await DatabaseHelper.instance.updateCotizacion(updated);
      }
      // Sincronizar también con MySQL (Hostinger) en segundo plano
      SyncService.instance.syncEverything().catchError((e) {
        debugPrint("Silent Hostinger sync error: $e");
      });
    });

    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("¡Cotización guardada exitosamente!"), backgroundColor: Colors.green),
    );
    return true;
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

  Future<void> _generarPDF() async {
    if (!mounted) return;

    int? previewId = _displayId;
    if (previewId == null) {
      final all = await DatabaseHelper.instance.queryAllCotizaciones();
      previewId = all.length + 1;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CotizacionVistaPreviaScreen(
          titulo: "Cotización lista",
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
          tituloDocumento: "COTIZACIÓN",
          fecha: _fechaDocumento,
          returnButtonText: "Volver a cotizaciones",
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
