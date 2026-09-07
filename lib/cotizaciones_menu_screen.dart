import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_module/screens/inventory_screen.dart' as local;
import 'local_module/screens/clients_screen.dart';
import 'local_module/screens/cotizaciones_screen.dart';
import 'local_module/screens/notas_entrega_screen.dart';
import 'local_module/screens/almacenamiento_screen.dart';
import 'drive_service.dart';
import 'local_module/database_helper.dart';
import 'inventory_screen.dart' as global_inv;
import 'local_module/services/sync_service.dart';
import 'product_model.dart';
import 'login_screen.dart';
import 'main.dart';
import 'local_module/services/update_service.dart';

class CotizacionesMenuScreen extends StatefulWidget {
  const CotizacionesMenuScreen({super.key});

  @override
  State<CotizacionesMenuScreen> createState() => _CotizacionesMenuScreenState();
}

class _CotizacionesMenuScreenState extends State<CotizacionesMenuScreen> with SingleTickerProviderStateMixin {
  final DriveService _drive = DriveService();
  bool _isSyncing = false;
  List<Product> _allProducts = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final session = Session();
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_isSyncing) {
        _syncEverything(silent: true);
      }
    });
  }

  Future<void> _loadProducts() async {
    final list = await _drive.getLocalCache();
    if (mounted) {
      setState(() {
        _allProducts = list;
      });
    }
  }

  Future<void> _syncEverything({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _isSyncing = true);
    try {
      await _drive.syncDriveCatalogToSQLite();
      await SyncService.instance.syncEverything().timeout(const Duration(seconds: 45));
      await _loadProducts(); // Recargar tras sincronización
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sincronización completa exitosa"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
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
      if (mounted && !silent) setState(() => _isSyncing = false);
    }
  }

  void _showAlmacenamientoOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryCyan = const Color(0xFF00ADEF);
    final cardBg = isDark ? const Color(0xFF161A22) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Almacenamiento",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryCyan.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.storage_rounded, color: primaryCyan, size: 24),
                  ),
                  title: Text(
                    "Ver Almacenamiento",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    "Gestión y consulta de existencias físicas.",
                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/almacenamiento');
                  },
                ),
                const Divider(height: 24),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.settings_rounded, color: Colors.orange, size: 24),
                  ),
                  title: Text(
                    "Configuración",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    "Configurar ubicaciones, tiendas y sub-ubicaciones.",
                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/almacenamiento/configuracion');
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showInventarioOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryCyan = const Color(0xFF00ADEF);
    final cardBg = isDark ? const Color(0xFF161A22) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Inventario",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryCyan.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.inventory_2_rounded, color: primaryCyan, size: 24),
                  ),
                  title: Text(
                    "Inventario",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    "Ver catálogo y existencias oficiales de la empresa.",
                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        settings: const RouteSettings(name: '/inventario'),
                        builder: (c) => const local.InventoryScreen(initialTab: 'oficial'),
                      ),
                    );
                  },
                ),
                const Divider(height: 24),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.list_alt_rounded, color: Colors.orange, size: 24),
                  ),
                  title: Text(
                    "Pre-inventario",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    "Registro rápido y control preventivo de stock.",
                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        settings: const RouteSettings(name: '/pre-inventario'),
                        builder: (c) => const local.InventoryScreen(
                          initialTab: 'pre',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Paleta de colores dinámica para Light/Dark mode
    final Color backgroundColor = isDark ? const Color(0xFF0B0F19) : Theme.of(context).scaffoldBackgroundColor;
    final Color headerColor = isDark ? const Color(0xFF131A26) : Colors.white;
    final Color primaryCyan = const Color(0xFF00ADEF);
    
    // Títulos y textos generales
    final Color titleColor = primaryCyan;
    final Color iconColor = isDark ? Colors.white : Colors.black87;
    final Color textPrimaryColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSecondaryColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    
    // Sombras para light mode
    final List<BoxShadow> cardShadow = isDark 
        ? [] 
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ];
          
    final List<BoxShadow> headerShadow = isDark 
        ? [] 
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: backgroundColor,
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: isDark ? const Color(0xFF1F2833) : primaryCyan),
              child: Center(
                child: Image.asset(
                  'icono/logo.png',
                  height: 80,
                  color: isDark ? Colors.white : null,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'novaled_logo.png',
                    height: 80,
                    color: isDark ? Colors.white : null,
                  ),
                ),
              ),
            ),
            SwitchListTile(
              title: const Text("Modo Oscuro"),
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: primaryCyan),
              value: isDark,
              onChanged: (bool value) {
                NovaledApp.of(context).toggleTheme(value);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.calculate, color: primaryCyan),
              title: const Text("Cotizaciones/Nota de Entrega"),
              onTap: () {
                Navigator.pop(context); // Cerrar drawer
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory, color: Colors.orange),
              title: const Text("Inventario"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    settings: const RouteSettings(name: '/inventario'),
                    builder: (c) => const local.InventoryScreen(initialTab: 'oficial'),
                  ),
                ).then((_) => _loadProducts());
              },
            ),

            if (session.isAdmin)
              ListTile(
                leading: const Icon(Icons.people, color: Colors.blue),
                title: const Text("Personal"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/personal');
                },
              ),
            ListTile(
              leading: const Icon(Icons.bug_report, color: Colors.redAccent),
              title: const Text("Google Debug"),
              onTap: () {
                Navigator.pop(context);
                _showGoogleDebugDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.system_update, color: Color(0xFF00ADEF)),
              title: const Text("Buscar Actualización"),
              onTap: () {
                Navigator.pop(context);
                UpdateService.buscarActualizacion(context);
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Cerrar Sesión"),
              onTap: () async {
                Session().clear();
                _drive.signOut();
                DriveService().clearMemoryCaches();
                await DatabaseHelper.instance.closeDatabase();
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('remember_me', false);
                await prefs.remove('saved_user');
                await prefs.remove('saved_pass');
                if (mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Cabecera customizada con sandwich y volver
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                boxShadow: headerShadow,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.menu_rounded, color: iconColor, size: 24),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    tooltip: "Menú",
                  ),
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: iconColor, size: 20),
                    onPressed: () => Navigator.pop(context),
                    tooltip: "Volver",
                  ),
                  Expanded(
                    child: Text(
                      "Punto de Venta",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 40), // Para balancear los dos botones de la izquierda
                ],
              ),
            ),
            
            // Grid y Cards
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                child: Column(
                  children: [
                    // Fila 1: Cotizaciones
                    _buildCotizacionesCard(
                      isDark: isDark,
                      textPrimaryColor: textPrimaryColor,
                      primaryCyan: primaryCyan,
                      cardShadow: cardShadow,
                    ),
                    const SizedBox(height: 20),
                    
                    // Fila 2: Inventario y Clientes
                    Row(
                      children: [
                        Expanded(
                          child: _buildSquareCard(
                            title: "Inventario",
                            icon: Icons.inventory_2_rounded,
                            onTap: () => _showInventarioOptions(context),
                            isDark: isDark,
                            textPrimaryColor: textPrimaryColor,
                            textSecondaryColor: textSecondaryColor,
                            cardShadow: cardShadow,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _buildSquareCard(
                            title: "Clientes",
                            icon: Icons.people_alt_rounded,
                            onTap: () => Navigator.pushNamed(context, '/clientes'),
                            isDark: isDark,
                            textPrimaryColor: textPrimaryColor,
                            textSecondaryColor: textSecondaryColor,
                            cardShadow: cardShadow,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Fila 3: Nota Entrega
                    _buildNotaEntregaCard(
                      isDark: isDark,
                      textPrimaryColor: textPrimaryColor,
                      textSecondaryColor: textSecondaryColor,
                      cardShadow: cardShadow,
                    ),
                    const SizedBox(height: 20),
                    
                    // Fila 4: Almacenamiento
                    _buildAlmacenamientoCard(
                      isDark: isDark,
                      textPrimaryColor: textPrimaryColor,
                      textSecondaryColor: textSecondaryColor,
                      cardShadow: cardShadow,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Card destacada de Cotizaciones (Mismo degradado y borde cyan del mockup)
  Widget _buildCotizacionesCard({
    required bool isDark,
    required Color textPrimaryColor,
    required Color primaryCyan,
    required List<BoxShadow> cardShadow,
  }) {
    final Color startColor = isDark ? const Color(0xFF1E2E3D) : const Color(0xFFE0F2FE);
    final Color endColor = isDark ? const Color(0xFF121B24) : const Color(0xFFF0F9FF);
    final Color calcBg = isDark ? const Color(0xFF0D131F) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [startColor, endColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primaryCyan, width: 2.2),
        boxShadow: cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Navigator.pushNamed(context, '/cotizaciones'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 26.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Cotizaciones",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textPrimaryColor,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: calcBg,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isDark ? [] : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: AnimatedDashboardIcon(
                    type: 'calculator',
                    icon: Icons.calculate_rounded,
                    color: primaryCyan,
                    size: 36,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Cards cuadradas gemelas (Inventario, Clientes, Almacenamiento, Pre-inventario)
  Widget _buildSquareCard({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    required Color textPrimaryColor,
    required Color textSecondaryColor,
    required List<BoxShadow> cardShadow,
  }) {
    final Color cardBg = isDark ? const Color(0xFF182232) : Colors.white;

    String animType = 'box';
    if (title.toLowerCase().contains('inventario')) {
      animType = 'box';
    } else if (title.toLowerCase().contains('clientes')) {
      animType = 'people';
    } else if (title.toLowerCase().contains('almacenamiento')) {
      animType = 'warehouse';
    } else if (title.toLowerCase().contains('pre-inventario')) {
      animType = 'checklist';
    }

    return AspectRatio(
      aspectRatio: 1.15,
      child: Container(
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedDashboardIcon(
                  type: animType,
                  icon: icon,
                  color: textSecondaryColor,
                  size: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: textPrimaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Card de Nota de Entrega horizontal
  Widget _buildNotaEntregaCard({
    required bool isDark,
    required Color textPrimaryColor,
    required Color textSecondaryColor,
    required List<BoxShadow> cardShadow,
  }) {
    final Color cardBg = isDark ? const Color(0xFF182232) : Colors.white;

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
          onTap: () => Navigator.pushNamed(context, '/notas_entrega'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Nota Entrega",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textPrimaryColor,
                  ),
                ),
                AnimatedDashboardIcon(
                  type: 'truck',
                  icon: Icons.local_shipping_rounded,
                  color: textSecondaryColor,
                  size: 36,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Card de Almacenamiento horizontal
  Widget _buildAlmacenamientoCard({
    required bool isDark,
    required Color textPrimaryColor,
    required Color textSecondaryColor,
    required List<BoxShadow> cardShadow,
  }) {
    final Color cardBg = isDark ? const Color(0xFF182232) : Colors.white;

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
          onTap: () => _showAlmacenamientoOptions(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Almacenamiento",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textPrimaryColor,
                  ),
                ),
                AnimatedDashboardIcon(
                  type: 'warehouse',
                  icon: Icons.warehouse_rounded,
                  color: textSecondaryColor,
                  size: 36,
                ),
              ],
            ),
          ),
        ),
      ),
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
              title: const Row(
                children: [
                  Icon(Icons.bug_report, color: Colors.redAccent),
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
                              _loadProducts();
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
                              _loadProducts();
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
                              _loadProducts();
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
