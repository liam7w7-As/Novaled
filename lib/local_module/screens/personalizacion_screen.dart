import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import '../services/pdf_service.dart';
import '../tenant_helper.dart';
import '../models/item_cotizacion.dart';
import '../models/articulo.dart';
import '../widgets/zoomable_pdf_preview.dart';
import '../../login_screen.dart';
import '../../main.dart';

class PersonalizacionScreen extends StatefulWidget {
  const PersonalizacionScreen({super.key});

  @override
  State<PersonalizacionScreen> createState() => _PersonalizacionScreenState();
}

class _PersonalizacionScreenState extends State<PersonalizacionScreen> {
  int _activeTab = 0; // 0: Información, 1: Color de marca
  bool _isFree = false;

  final _companyNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _nitController = TextEditingController();
  final _currencyController = TextEditingController();

  final _socialController = TextEditingController();
  final _websiteController = TextEditingController();

  List<String> _agentes = ["JOEL", "GABRIEL", "CELIA"];
  List<String> _sucursales = ["#818", "#840"];

  String? _logoPath;
  String? _selloPath;

  double _logoScale = 1.0;
  int _primaryColor = 0xFF5A45F5;

  int _selectedPaletteIndex = 0;

  final List<Map<String, dynamic>> _suggestedPalettes = [
    {
      'name': 'Morado',
      'colors': [0xFF5A45F5, 0xFF7A6DF5, 0xFFA199F7, 0xFFC6C2F9, 0xFFF7F8FD],
    },
    {
      'name': 'Océano',
      'colors': [0xFF2782EA, 0xFF57BCEB, 0xFFA3E3DB, 0xFFC7EAE4, 0xFFF2FAF8],
    },
    {
      'name': 'Fuego',
      'colors': [0xFFF75454, 0xFFFA9F32, 0xFFFAC951, 0xFFFCE3A2, 0xFFFDF7F2],
    },
    {
      'name': 'Bosque',
      'colors': [0xFF1DA074, 0xFF5BC55E, 0xFFA4DD97, 0xFFD6EDCB, 0xFFF2F9F5],
    },
  ];

  bool _isLoading = true;
  int _previewKeyCounter = 0;
  Timer? _debounceTimer;

  // Preset Colors
  final List<int> _presetColors = [
    0xFF5D43FF, // Brand Purple
    0xFF00ADEF, // Cyan
    0xFFEFA820, // Orange
    0xFFEF4444, // Red
    0xFF3B82F6, // Blue
    0xFF10B981, // Green
    0xFF8B5CF6, // Violet
    0xFF0F172A, // Navy
  ];

  final List<ItemCotizacion> _sampleItems = [
    ItemCotizacion(
      articulo: Articulo(
        id: 1,
        nombre: "FOCO LED NOVALED 12W",
        precio: 15.0,
        descripcion: "Foco led alta potencia",
        unidad: "Pza",
      ),
      precioOriginal: 15.0,
      cantidad: 10,
    ),
    ItemCotizacion(
      articulo: Articulo(
        id: 2,
        nombre: "CINTA AISLANTE 3M",
        precio: 8.5,
        descripcion: "Cinta de aislar profesional",
        unidad: "Rollo",
      ),
      precioOriginal: 8.5,
      cantidad: 5,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _companyNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _nitController.dispose();
    _currencyController.dispose();
    _socialController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    // Sincronizar primero desde la nube para tener la versión más actualizada entre todos los dispositivos
    await TenantHelper.syncTenantSettings();

    final prefs = await SharedPreferences.getInstance();
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final isNovaled = tenantKey == 'novaled';

    final compName = prefs.getString(TenantHelper.k('pdf_company_name', tenantKey)) ?? (isNovaled ? "NOVALED" : "");
    final compEmail = prefs.getString(TenantHelper.k('pdf_company_email', tenantKey)) ?? (isNovaled ? "contacto@novaled.bo" : "");
    final compPhone = prefs.getString(TenantHelper.k('pdf_company_phone', tenantKey)) ?? (isNovaled ? "67502547" : "");
    final compAddr = prefs.getString(TenantHelper.k('pdf_company_address', tenantKey)) ?? (isNovaled ? "Calle 16 de Obrajes, edif Centro de..." : "");
    final compNit = prefs.getString(TenantHelper.k('pdf_company_nit', tenantKey)) ?? (isNovaled ? "123456789123456" : "");
    final compCurr = prefs.getString(TenantHelper.k('pdf_company_currency', tenantKey)) ?? "BO";
    final compSocial = prefs.getString(TenantHelper.k('pdf_social_handle', tenantKey)) ?? (isNovaled ? "@novaledbolivia" : "");
    final compWeb = prefs.getString(TenantHelper.k('pdf_website', tenantKey)) ?? (isNovaled ? "www.novaledbolivia.com" : "");

    final savedLogo = prefs.getString(TenantHelper.k('pdf_company_logo_path', tenantKey));
    final logoPath = (savedLogo != null && File(savedLogo).existsSync()) ? savedLogo : null;
    final savedSello = prefs.getString(TenantHelper.k('pdf_company_sello_path', tenantKey));
    final selloPath = (savedSello != null && File(savedSello).existsSync()) ? savedSello : null;

    final logoScale = prefs.getDouble(TenantHelper.k('pdf_logo_scale', tenantKey)) ?? 1.0;
    final primaryColor = prefs.getInt(TenantHelper.k('pdf_primary_color', tenantKey)) ?? 0xFF5D43FF;
    int selectedPalIndex = prefs.getInt(TenantHelper.k('pdf_selected_palette_index', tenantKey)) ?? 0;

    if (selectedPalIndex >= 0 && selectedPalIndex < _suggestedPalettes.length) {
      final List<int> palColors = List<int>.from(_suggestedPalettes[selectedPalIndex]['colors']);
      if (palColors[0] != primaryColor) {
        int matchIdx = -1;
        for (int i = 0; i < _suggestedPalettes.length; i++) {
          final List<int> c = List<int>.from(_suggestedPalettes[i]['colors']);
          if (c[0] == primaryColor) {
            matchIdx = i;
            break;
          }
        }
        selectedPalIndex = matchIdx;
      }
    }

    final vendedores = await TenantHelper.getVendedores();
    final sucursales = await TenantHelper.getSucursales();
    final isFree = await TenantHelper.isFreePlan();

    if (mounted) {
      setState(() {
        _isFree = isFree;
        _companyNameController.text = compName;
        _emailController.text = compEmail;
        _phoneController.text = compPhone;
        _addressController.text = compAddr;
        _nitController.text = compNit;
        _currencyController.text = compCurr;
        _socialController.text = compSocial;
        _websiteController.text = compWeb;

        _logoPath = logoPath;
        _selloPath = selloPath;

        _logoScale = logoScale;
        _primaryColor = isFree ? 0xFF5D43FF : primaryColor;
        _selectedPaletteIndex = isFree ? 0 : selectedPalIndex;

        _agentes = List<String>.from(vendedores);
        _sucursales = List<String>.from(sucursales);
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final isFree = await TenantHelper.isFreePlan();

    await prefs.setString(TenantHelper.k('pdf_company_name', tenantKey), _companyNameController.text);
    await prefs.setString(TenantHelper.k('pdf_company_email', tenantKey), _emailController.text);
    await prefs.setString(TenantHelper.k('pdf_company_phone', tenantKey), _phoneController.text);
    await prefs.setString(TenantHelper.k('pdf_company_address', tenantKey), _addressController.text);
    await prefs.setString(TenantHelper.k('pdf_company_nit', tenantKey), _nitController.text);
    await prefs.setString(TenantHelper.k('pdf_company_currency', tenantKey), _currencyController.text);
    await prefs.setString(TenantHelper.k('pdf_social_handle', tenantKey), _socialController.text);
    await prefs.setString(TenantHelper.k('pdf_website', tenantKey), _websiteController.text);

    if (_logoPath != null) await prefs.setString(TenantHelper.k('pdf_company_logo_path', tenantKey), _logoPath!);
    if (_selloPath != null) await prefs.setString(TenantHelper.k('pdf_company_sello_path', tenantKey), _selloPath!);
    await prefs.setStringList(TenantHelper.k('system_vendedores', tenantKey), _agentes);
    await prefs.setStringList(TenantHelper.k('system_sucursales', tenantKey), _sucursales);

    final effectivePrimary = isFree ? 0xFF5D43FF : _primaryColor;
    final effectivePalIdx = isFree ? 0 : _selectedPaletteIndex;

    final Color swatch3Color = _compute3rdSwatchColor(effectivePrimary, effectivePalIdx);
    final Color swatch4Color = _compute4thSwatchColor(effectivePrimary, effectivePalIdx);
    final Color swatch5Color = _compute5thSwatchColor(effectivePrimary, effectivePalIdx);

    await prefs.setDouble(TenantHelper.k('pdf_logo_scale', tenantKey), _logoScale);
    await prefs.setInt(TenantHelper.k('pdf_primary_color', tenantKey), effectivePrimary);
    await prefs.setInt(TenantHelper.k('pdf_icon_color', tenantKey), swatch3Color.value);
    await prefs.setInt(TenantHelper.k('pdf_card_color', tenantKey), swatch4Color.value);
    await prefs.setInt(TenantHelper.k('pdf_bg_color', tenantKey), swatch5Color.value);
    await prefs.setInt(TenantHelper.k('pdf_selected_palette_index', tenantKey), effectivePalIdx);

    // Sincronizar en tiempo real hacia la nube
    TenantHelper.uploadTenantSettings(
      vendedores: _agentes,
      sucursales: _sucursales,
      companyName: _companyNameController.text,
      companyEmail: _emailController.text,
      companyPhone: _phoneController.text,
      companyAddress: _addressController.text,
      companyNit: _nitController.text,
      companyCurrency: _currencyController.text,
      socialHandle: _socialController.text,
      website: _websiteController.text,
      primaryColor: effectivePrimary,
      iconColor: swatch3Color.value,
      cardColor: swatch4Color.value,
      bgColor: swatch5Color.value,
      paletteIndex: effectivePalIdx,
      logoScale: _logoScale,
    );

    setState(() {
      _previewKeyCounter++;
    });

    if (mounted) {
      try {
        NovaledApp.of(context).updateBrandColor(
          Color(_primaryColor),
          newIconColor: swatch3Color,
          newCardColor: swatch4Color,
          newBgColor: swatch5Color,
        );
      } catch (_) {}
    }
  }

  Future<void> _saveAndGoHome() async {
    await _saveSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Configuración guardada correctamente"),
          backgroundColor: Color(_primaryColor),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Color _compute3rdSwatchColor(int primaryColorInt, int paletteIndex) {
    if (paletteIndex >= 0 && paletteIndex < _suggestedPalettes.length) {
      final List<int> colors = List<int>.from(_suggestedPalettes[paletteIndex]['colors']);
      return Color(colors[2]);
    }
    final base = Color(primaryColorInt);
    final hsl = HSLColor.fromColor(base);
    final newLightness = (hsl.lightness < 0.5)
        ? (hsl.lightness + 0.40).clamp(0.0, 0.95)
        : (hsl.lightness + 0.25).clamp(0.0, 0.95);
    return hsl.withLightness(newLightness).withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0)).toColor();
  }

  Color _compute4thSwatchColor(int primaryColorInt, int paletteIndex) {
    if (paletteIndex >= 0 && paletteIndex < _suggestedPalettes.length) {
      final List<int> colors = List<int>.from(_suggestedPalettes[paletteIndex]['colors']);
      return Color(colors[3]);
    }
    final base = Color(primaryColorInt);
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness + 0.35).clamp(0.0, 0.95)).toColor();
  }

  Color _compute5thSwatchColor(int primaryColorInt, int paletteIndex) {
    if (paletteIndex >= 0 && paletteIndex < _suggestedPalettes.length) {
      final List<int> colors = List<int>.from(_suggestedPalettes[paletteIndex]['colors']);
      return Color(colors[4]);
    }
    final base = Color(primaryColorInt);
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + 0.45).clamp(0.95, 0.985))
        .withSaturation((hsl.saturation * 0.22).clamp(0.02, 0.30))
        .toColor();
  }

  Future<void> _pickImage(bool isLogo) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          if (isLogo) {
            _logoPath = picked.path;
          } else {
            _selloPath = picked.path;
          }
        });
        _saveSettings();
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  Future<void> _cerrarSesion() async {
    Session().clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', false);
    await prefs.remove('saved_user');
    await prefs.remove('saved_pass');
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgCol = isDark ? const Color(0xFF0F172A) : _compute5thSwatchColor(_primaryColor, _selectedPaletteIndex);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8);
    final purpleBrand = Color(_primaryColor);
    final purpleLight = isDark ? const Color(0xFF2D2B52) : Color(_primaryColor).withOpacity(0.12);
    final tagBg = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final tagText = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgCol,
        body: Center(
          child: CircularProgressIndicator(color: Color(_primaryColor)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgCol,
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back, color: textPrimary, size: 24),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Expanded(
                    child: Text(
                      "Modo edición",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
              ),
            ),

            // TABS (Información / Color de marca)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _activeTab == 0 ? purpleBrand : cardBg,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: _activeTab == 0 ? purpleBrand : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            "Información",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _activeTab == 0 ? (purpleBrand.computeLuminance() > 0.5 ? Colors.black87 : Colors.white) : textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _activeTab == 1 ? purpleBrand : cardBg,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: _activeTab == 1 ? purpleBrand : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            "Color de marca",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _activeTab == 1 ? (purpleBrand.computeLuminance() > 0.5 ? Colors.black87 : Colors.white) : textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // BODY CONTENT
            Expanded(
              child: _activeTab == 0
                  ? _buildInformacionTab(cardBg, textPrimary, textSecondary, purpleBrand, purpleLight, tagBg, tagText, isDark)
                  : _buildColorDeMarcaTab(cardBg, textPrimary, textSecondary, purpleBrand, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInformacionTab(
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    Color purpleBrand,
    Color purpleLight,
    Color tagBg,
    Color tagText,
    bool isDark,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          // LOGO SECTION
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Logo",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _pickImage(true),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    decoration: BoxDecoration(
                      color: purpleLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: purpleBrand.withOpacity(0.4), width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_logoPath != null && File(_logoPath!).existsSync()) ...[
                          Image.file(
                            File(_logoPath!),
                            height: 36,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Text(
                          (_logoPath != null && File(_logoPath!).existsSync()) ? "Cambiar logo" : "+ Subir logo",
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: purpleBrand,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // INFORMACIÓN SECTION
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Información",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                _buildUnderlineFormField("Nombre de la empresa", _companyNameController, textPrimary, textSecondary),
                const SizedBox(height: 16),
                _buildUnderlineFormField("Correo", _emailController, textPrimary, textSecondary),
                const SizedBox(height: 16),
                _buildUnderlineFormField("Número de contacto", _phoneController, textPrimary, textSecondary),
                const SizedBox(height: 16),
                _buildUnderlineFormField("NIT", _nitController, textPrimary, textSecondary),
                const SizedBox(height: 16),
                _buildUnderlineFormField("Tipo de moneda", _currencyController, textPrimary, textSecondary),
                const SizedBox(height: 16),
                _buildUnderlineFormField("Red Social", _socialController, textPrimary, textSecondary, hintText: "@tunombreredsocial"),
                const SizedBox(height: 16),
                _buildUnderlineFormField("Página Web", _websiteController, textPrimary, textSecondary, hintText: "www.mipagina.com"),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // AGENTES DE VENTA SECTION
          GestureDetector(
            onTap: _gestionarAgentesDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Agentes de venta",
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      Icon(Icons.edit_outlined, color: textSecondary, size: 18),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _agentes
                        .map(
                          (agente) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: tagBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              agente,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: tagText,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // SUCURSAL SECTION
          GestureDetector(
            onTap: _gestionarSucursalesDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Sucursal",
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      Icon(Icons.edit_outlined, color: textSecondary, size: 18),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _sucursales
                        .map(
                          (sucursal) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: tagBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              sucursal,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: tagText,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // SELLO SECTION
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Sello",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _pickImage(false),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    decoration: BoxDecoration(
                      color: purpleLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: purpleBrand.withOpacity(0.4), width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_selloPath != null && File(_selloPath!).existsSync()) ...[
                          Image.file(
                            File(_selloPath!),
                            height: 36,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Text(
                          (_selloPath != null && File(_selloPath!).existsSync()) ? "Cambiar sello" : "+ Subir sello",
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: purpleBrand,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // FOOTER ACTIONS
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveAndGoHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: purpleBrand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    "Guardar",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _cerrarSesion,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.redAccent,
                  ),
                  child: Text(
                    "Cerrar sesión",
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnderlineFormField(
    String label,
    TextEditingController controller,
    Color textPrimary,
    Color textSecondary, {
    String? hintText,
  }) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hintText,
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: textSecondary.withOpacity(0.5),
                    ),
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                  onChanged: (_) => _saveSettings(),
                ),
              ),
              Icon(Icons.edit_outlined, color: textSecondary, size: 16),
            ],
          ),
        ],
      ),
    );
  }

  void _showProFeatureDialog(String feature, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: Color(0xFFEAB308), size: 24),
            const SizedBox(width: 8),
            Text(
              "Función Plan PRO ⚡",
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "La personalización de $feature está bloqueada en la versión Gratis.",
              style: GoogleFonts.poppins(fontSize: 13, color: isDark ? Colors.white70 : const Color(0xFF334155)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF5A45F5).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF5A45F5).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("⭐ Beneficios Plan PRO (Bs. 95/mes):", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF5A45F5))),
                  const SizedBox(height: 4),
                  Text("• Cotizaciones y Notas de Venta ilimitadas\n• Paleta de colores y modo edición desbloqueado\n• 50 escaneos mágicos / mes\n• Hasta 6 usuarios", style: GoogleFonts.poppins(fontSize: 11, color: isDark ? Colors.white70 : const Color(0xFF334155))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Entendido", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF5A45F5))),
          ),
        ],
      ),
    );
  }

  void _onColorWheelTap(Offset localPosition) {
    if (_isFree) {
      _showProFeatureDialog("la Paleta de Colores y Color de Marca", Theme.of(context).brightness == Brightness.dark);
      return;
    }

    const double radius = 96.0;
    final double dx = localPosition.dx - radius;
    final double dy = localPosition.dy - radius;

    final double r = sqrt(dx * dx + dy * dy);
    final double rClamped = r.clamp(0.0, radius);

    final double angle = atan2(dy, dx);
    final double hue = (angle * 180 / pi + 360) % 360;
    final double saturation = (rClamped / radius).clamp(0.1, 1.0);

    final color = HSVColor.fromAHSV(1.0, hue, saturation, 0.95).toColor();
    setState(() {
      _primaryColor = color.value;
      _selectedPaletteIndex = -1;
    });
    _saveSettings();
  }

  void _showHexEditDialog() {
    if (_isFree) {
      _showProFeatureDialog("el Color de Marca", Theme.of(context).brightness == Brightness.dark);
      return;
    }

    final hexController = TextEditingController(
      text: _primaryColor.toRadixString(16).substring(2).toUpperCase(),
    );
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("Editar Código HEX", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: hexController,
          autofocus: true,
          decoration: const InputDecoration(
            prefixText: "#",
            hintText: "5842F4",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              final clean = hexController.text.replaceAll('#', '').trim();
              if (clean.length == 6) {
                final val = int.tryParse("FF$clean", radix: 16);
                if (val != null) {
                  setState(() {
                    _primaryColor = val;
                    _selectedPaletteIndex = -1;
                  });
                  _saveSettings();
                }
              }
              Navigator.pop(c);
            },
            child: const Text("Aplicar"),
          ),
        ],
      ),
    );
  }

  List<int> _generatePaletteFromBase(int baseInt) {
    final base = Color(baseInt);
    final hsl = HSLColor.fromColor(base);
    return [
      baseInt,
      hsl.withLightness((hsl.lightness + 0.10).clamp(0.0, 0.95)).toColor().value,
      hsl.withLightness((hsl.lightness + 0.22).clamp(0.0, 0.95)).toColor().value,
      hsl.withLightness((hsl.lightness + 0.35).clamp(0.0, 0.95)).toColor().value,
      hsl
          .withLightness((hsl.lightness + 0.45).clamp(0.95, 0.985))
          .withSaturation((hsl.saturation * 0.22).clamp(0.02, 0.30))
          .toColor()
          .value,
    ];
  }

  Widget _buildColorDeMarcaTab(
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    Color purpleBrand,
    bool isDark,
  ) {
    final hexString = "#${_primaryColor.toRadixString(16).substring(2).toUpperCase()}";
    final hsv = HSVColor.fromColor(Color(_primaryColor));
    final double currentHue = hsv.hue;
    final double currentSat = hsv.saturation;
    final double thumbDist = (currentSat * 80.0).clamp(10.0, 88.0);
    final double currentAngleRad = currentHue * pi / 180;
    final double thumbX = 96 + thumbDist * cos(currentAngleRad) - 10;
    final double thumbY = 96 + thumbDist * sin(currentAngleRad) - 10;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          if (_isFree)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEAB308).withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, color: Color(0xFFEAB308), size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Color de marca y paleta bloqueados (Plan Gratis)",
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          "La personalización de colores está disponible en Plan PRO (Bs. 95/mes). En Plan Gratis mantienes tu información comercial y logotipo intactos.",
                          style: GoogleFonts.poppins(fontSize: 11.5, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // COLOR PRINCIPAL CARD
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Color principal",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF141B34),
                  ),
                ),
                const SizedBox(height: 24),

                // COLOR WHEEL INTERACTIVA (Sin restricciones de posición ni tinte)
                Center(
                  child: GestureDetector(
                    onTapDown: (details) => _onColorWheelTap(details.localPosition),
                    onPanUpdate: (details) => _onColorWheelTap(details.localPosition),
                    child: Container(
                      width: 192,
                      height: 192,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            Color(0xFFFF0000),
                            Color(0xFFFF8000),
                            Color(0xFFFFFF00),
                            Color(0xFF00FF00),
                            Color(0xFF00FFFF),
                            Color(0xFF0000FF),
                            Color(0xFFFF00FF),
                            Color(0xFFFF0000),
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.white.withOpacity(0.85),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: thumbX,
                            top: thumbY,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(_primaryColor),
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // HEX INPUT & CURRENT COLOR PREVIEW INTERACTIVO
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _showHexEditDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFF4F6FC),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                hexString.toLowerCase(),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textPrimary,
                                ),
                              ),
                              Icon(Icons.edit_outlined, color: const Color(0xFFA8B1CF), size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Color(_primaryColor),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Color(_primaryColor).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // SWATCHES ROW (Shades of primary color / palette colors)
                Builder(builder: (context) {
                  final base = Color(_primaryColor);
                  final hsl = HSLColor.fromColor(base);
                  final List<Color> swatchColors = (_selectedPaletteIndex >= 0 && _selectedPaletteIndex < _suggestedPalettes.length)
                      ? (_suggestedPalettes[_selectedPaletteIndex]['colors'] as List<int>).map((c) => Color(c)).toList()
                      : [
                          base,
                          hsl.withLightness((hsl.lightness + 0.10).clamp(0.0, 0.95)).toColor(),
                          hsl.withLightness((hsl.lightness + 0.22).clamp(0.0, 0.95)).toColor(),
                          hsl.withLightness((hsl.lightness + 0.35).clamp(0.0, 0.95)).toColor(),
                          hsl
                              .withLightness((hsl.lightness + 0.45).clamp(0.95, 0.985))
                              .withSaturation((hsl.saturation * 0.22).clamp(0.02, 0.30))
                              .toColor(),
                        ];

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSwatchCircle(swatchColors[0]),
                      _buildSwatchCircle(swatchColors[1]),
                      _buildSwatchCircle(swatchColors[2]), // 3ª Ruedita = Color de Íconos!
                      _buildSwatchCircle(swatchColors[3]),
                      _buildSwatchCircle(swatchColors[4]),
                    ],
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // PALETAS SUGERIDAS CARD
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Paletas sugeridas",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF141B34),
                  ),
                ),
                const SizedBox(height: 16),

                if (_selectedPaletteIndex == -1) ...[
                  Builder(builder: (context) {
                    final customColors = _generatePaletteFromBase(_primaryColor);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Color(_primaryColor),
                          width: 2.0,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: Color(_primaryColor),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check, size: 10, color: Colors.white),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "Paleta seleccionada",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: customColors.map((c) => Container(
                                    width: 22,
                                    height: 22,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: Color(c),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1.5),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          blurRadius: 3,
                                        ),
                                      ],
                                    ),
                                  )).toList(),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Color(_primaryColor).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "#${_primaryColor.toRadixString(16).substring(2).toUpperCase()}",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(_primaryColor),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                // 2x2 GRID OF PALETTES
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: _suggestedPalettes.length,
                  itemBuilder: (context, idx) {
                    final pal = _suggestedPalettes[idx];
                    final isSelected = _selectedPaletteIndex == idx;
                    final List<int> colors = pal['colors'];

                    return GestureDetector(
                      onTap: () {
                        if (_isFree) {
                          _showProFeatureDialog("las Paletas de Colores Sugeridas", isDark);
                          return;
                        }
                        setState(() {
                          _selectedPaletteIndex = idx;
                          _primaryColor = colors[0];
                        });
                        _saveSettings();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF5A45F5) : (isDark ? Colors.white10 : const Color(0xFFE4E7F3)),
                            width: isSelected ? 2.0 : 1.0,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              top: 0,
                              right: 0,
                              child: isSelected
                                  ? Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF5A45F5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check, size: 10, color: Colors.white),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xFFA8B1CF)),
                                      ),
                                      child: const Icon(Icons.check, size: 8, color: Color(0xFFA8B1CF)),
                                    ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: colors
                                      .map((c) => Container(
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: Color(c),
                                              shape: BoxShape.circle,
                                            ),
                                          ))
                                      .toList(),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  pal['name'],
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: textPrimary,
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
              ],
            ),
          ),
          const SizedBox(height: 28),

          // FOOTER ACTIONS
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveAndGoHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(_primaryColor),
                    foregroundColor: Color(_primaryColor).computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 4,
                    shadowColor: Color(_primaryColor).withOpacity(0.4),
                  ),
                  child: Text(
                    "Guardar",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(_primaryColor).computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _cerrarSesion,
                child: Text(
                  "Cerrar sesión",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFE74C3C),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ],
      ),
    );
  }

  void _gestionarAgentesDialog() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final primaryColor = Color(_primaryColor);

          return Dialog(
            backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Agentes de Venta",
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: textCtrl,
                          style: GoogleFonts.poppins(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            hintText: "Nuevo agente",
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onPressed: () {
                          final val = textCtrl.text.trim();
                          if (val.isNotEmpty && !_agentes.contains(val)) {
                            setState(() {
                              _agentes.add(val);
                            });
                            textCtrl.clear();
                            setModalState(() {});
                            _saveSettings();
                          }
                        },
                        child: const Text("+", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _agentes.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final item = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                  onPressed: () async {
                                    setState(() {
                                      _agentes.removeAt(idx);
                                    });
                                    setModalState(() {});
                                    await _saveSettings();
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: Text("Cerrar", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: primaryColor)),
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

  void _gestionarSucursalesDialog() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final primaryColor = Color(_primaryColor);

          return Dialog(
            backgroundColor: isDark ? const Color(0xFF1E222B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Sucursales",
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: textCtrl,
                          style: GoogleFonts.poppins(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            hintText: "Ej: #818, #840...",
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onPressed: () async {
                          final val = textCtrl.text.trim();
                          if (val.isNotEmpty && !_sucursales.contains(val)) {
                            setState(() {
                              _sucursales.add(val);
                            });
                            textCtrl.clear();
                            setModalState(() {});
                            await _saveSettings();
                          }
                        },
                        child: const Text("+", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _sucursales.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final item = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                  onPressed: () async {
                                    setState(() {
                                      _sucursales.removeAt(idx);
                                    });
                                    setModalState(() {});
                                    await _saveSettings();
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: Text("Cerrar", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: primaryColor)),
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

  Widget _buildSwatchCircle(Color color) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}
