import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter/services.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'cotizaciones_menu_screen.dart';
import 'personal_manage_screen.dart';
import 'local_module/screens/cotizaciones_screen.dart';
import 'local_module/screens/crear_cotizacion_screen.dart';
import 'local_module/screens/crear_cotizacion_escaneada_screen.dart';
import 'local_module/screens/notas_entrega_screen.dart';
import 'local_module/screens/crear_nota_entrega_screen.dart';
import 'local_module/screens/clients_screen.dart';
import 'local_module/screens/inventory_screen.dart' as local_screens;
import 'local_module/screens/almacenamiento_screen.dart';
import 'local_module/screens/almacenamiento_configuracion_screen.dart';
import 'local_module/screens/venta_institucional_screen.dart';
import 'local_module/screens/personalizacion_screen.dart';
import 'local_module/database_helper.dart';
import 'local_module/services/pdf_service.dart';
import 'local_module/tenant_helper.dart';
import 'drive_service.dart';

final ValueNotifier<int> sessionNotifier = ValueNotifier<int>(0);

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Preload PDF resources (fonts, logo) in the background to speed up first PDF generation
  Future.microtask(() => PdfService.preloadResources());

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint("Warning: SharedPreferences failed to initialize: $e");
  }

  final bool isDark = prefs?.getBool('isDarkMode') ?? true; // Por defecto oscuro
  
  // Verificar si hay una sesión guardada activa para entrar directo al inicio (Recordar contraseña)
  final bool rememberMe = prefs?.getBool('remember_me') ?? false;
  final String savedUser = prefs?.getString('saved_user') ?? '';
  final String savedPass = prefs?.getString('saved_pass') ?? '';
  bool isLoggedIn = false;

  if (rememberMe && savedUser.isNotEmpty && savedPass.isNotEmpty) {
    final user = savedUser.trim().toLowerCase();
    final session = Session();
    session.userName = user.toUpperCase();
    
    if (user == "almir" || user == "joel") {
      session.role = UserRole.developer;
    } else if (user == "victor") {
      session.role = UserRole.designer;
    } else if (user == "gustavo" || user == "dani") {
      session.role = UserRole.seller;
    } else {
      // Encontrar rol del usuario personalizado
      try {
        final customUsersJson = prefs?.getString('novaled_custom_users');
        if (customUsersJson != null) {
          final List<dynamic> list = jsonDecode(customUsersJson);
          final userEntry = list.firstWhere(
            (u) => u['username']?.toString().toLowerCase().trim() == user,
            orElse: () => null,
          );
          if (userEntry != null) {
            final roleStr = userEntry['role']?.toString();
            if (roleStr == 'developer') {
              session.role = UserRole.developer;
            } else if (roleStr == 'admin') {
              session.role = UserRole.admin;
            } else if (roleStr == 'designer') {
              session.role = UserRole.designer;
            } else {
              session.role = UserRole.seller;
            }
          }
        }
      } catch (e) {
        debugPrint("Error resolviendo rol personalizado en inicio directo: $e");
      }
      session.role ??= UserRole.seller;
    }
    isLoggedIn = true;
  }

  // Borrar de una sola vez Notas de Entrega si no se ha hecho para limpiar errores históricos
  final bool clearedNotas = prefs?.getBool('clearedNotasEntregaV1') ?? false;
  if (!clearedNotas) {
    try {
      await DatabaseHelper.instance.clearAllNotasEntrega();
      // Ejecutar borrado en la nube de forma asíncrona en segundo plano
      Future.microtask(() async {
        try {
          final drive = DriveService();
          await drive.clearAllNotasEntrega();
        } catch (e) {
          debugPrint("Error clearing Notas de Entrega in background: $e");
        }
      });
      if (prefs != null) {
        await prefs.setBool('clearedNotasEntregaV1', true);
      }
    } catch (e) {
      debugPrint("Error clearing local Notas de Entrega: $e");
    }
  }

  runApp(NovaledApp(isDark: isDark, isLoggedIn: isLoggedIn));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NovaledApp extends StatefulWidget {
  final bool isDark;
  final bool isLoggedIn;
  const NovaledApp({super.key, required this.isDark, required this.isLoggedIn});

  static _NovaledAppState of(BuildContext context) => context.findAncestorStateOfType<_NovaledAppState>()!;

  @override
  State<NovaledApp> createState() => _NovaledAppState();
}

class _NovaledAppState extends State<NovaledApp> {
  late ThemeMode _themeMode;
  Color brandColor = const Color(0xFF5D43FF);
  Color iconColor = const Color(0xFFA199F7);
  Color cardColor = const Color(0xFFDEE8F5);
  Color appBgColor = const Color(0xFFF4F7FB);

  @override
  void initState() {
    super.initState();
    _themeMode = widget.isDark ? ThemeMode.dark : ThemeMode.light;
    _loadBrandColor();
  }

  Future<void> _loadBrandColor() async {
    final prefs = await SharedPreferences.getInstance();
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final colorInt = prefs.getInt(TenantHelper.k('pdf_primary_color', tenantKey)) ?? 0xFF5D43FF;
    final iconColorInt = prefs.getInt(TenantHelper.k('pdf_icon_color', tenantKey)) ?? 0xFFA199F7;
    final cardColorInt = prefs.getInt(TenantHelper.k('pdf_card_color', tenantKey)) ?? 0xFFDEE8F5;
    final bgColorInt = prefs.getInt(TenantHelper.k('pdf_bg_color', tenantKey)) ?? 0xFFF4F7FB;
    setState(() {
      brandColor = Color(colorInt);
      iconColor = Color(iconColorInt);
      cardColor = Color(cardColorInt);
      appBgColor = Color(bgColorInt);
    });
  }

  void reloadBrandColor() {
    _loadBrandColor();
  }

  void updateBrandColor(Color newColor, {Color? newIconColor, Color? newCardColor, Color? newBgColor}) async {
    final effectiveIconColor = newIconColor ?? HSLColor.fromColor(newColor).withLightness(0.7).toColor();
    final effectiveCardColor = newCardColor ?? HSLColor.fromColor(newColor).withLightness(0.85).toColor();
    final effectiveBgColor = newBgColor ??
        HSLColor.fromColor(newColor)
            .withLightness(0.975)
            .withSaturation((HSLColor.fromColor(newColor).saturation * 0.22).clamp(0.02, 0.30))
            .toColor();
    setState(() {
      brandColor = newColor;
      iconColor = effectiveIconColor;
      cardColor = effectiveCardColor;
      appBgColor = effectiveBgColor;
    });
    final prefs = await SharedPreferences.getInstance();
    final tenantKey = await TenantHelper.getActiveTenantKey();
    await prefs.setInt(TenantHelper.k('pdf_primary_color', tenantKey), newColor.value);
    await prefs.setInt(TenantHelper.k('pdf_icon_color', tenantKey), effectiveIconColor.value);
    await prefs.setInt(TenantHelper.k('pdf_card_color', tenantKey), effectiveCardColor.value);
    await prefs.setInt(TenantHelper.k('pdf_bg_color', tenantKey), effectiveBgColor.value);
  }

  @override
  void reassemble() async {
    super.reassemble();
    debugPrint("Hot Reload detectado. Redirigiendo a pantalla principal...");
    
    // Obtener estado de inicio de sesión actual
    final prefs = await SharedPreferences.getInstance();
    final bool rememberMe = prefs.getBool('remember_me') ?? false;
    final String savedUser = prefs.getString('saved_user') ?? '';
    final String savedPass = prefs.getString('saved_pass') ?? '';
    final bool isLoggedIn = rememberMe && savedUser.isNotEmpty && savedPass.isNotEmpty;

    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => isLoggedIn ? const HomeScreen() : const LoginScreen()),
        (route) => false,
      );
    }
  }

  void toggleTheme(bool isOn) async {
    setState(() {
      _themeMode = isOn ? ThemeMode.dark : ThemeMode.light;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isOn);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Novaled System',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      builder: (context, child) {
        return ValueListenableBuilder<int>(
          valueListenable: sessionNotifier,
          builder: (context, _, __) {
            return ConnectivityWrapper(child: child!);
          },
        );
      },
      
      // TEMA CLARO
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme),
        brightness: Brightness.light,
        primaryColor: brandColor,
        colorScheme: ColorScheme.light(
          primary: brandColor,
          secondary: brandColor,
          surface: cardColor,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: appBgColor,
          foregroundColor: const Color(0xFF0F172A),
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
        scaffoldBackgroundColor: appBgColor,
      ),

      // TEMA OSCURO (Original de Novaled)
      darkTheme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        brightness: Brightness.dark,
        primaryColor: brandColor,
        scaffoldBackgroundColor: const Color(0xFF131510),
        colorScheme: ColorScheme.dark(
          primary: brandColor,
          secondary: brandColor,
          surface: const Color(0xFF1E293B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF131510),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
        ),
      ),
      initialRoute: widget.isLoggedIn ? '/home' : '/login',
      onGenerateRoute: (settings) {
        final routeName = settings.name ?? '/';
        final bool authed = Session().userName != null && Session().role != null;

        String targetRoute = routeName;
        if (targetRoute == '/') {
          targetRoute = authed ? '/home' : '/login';
        }

        if (!authed && targetRoute != '/login') {
          return MaterialPageRoute(
            builder: (context) => const LoginScreen(),
            settings: const RouteSettings(name: '/login'),
          );
        }

        Widget builder;
        switch (targetRoute) {
          case '/login':
            builder = const LoginScreen();
            break;
          case '/home':
            builder = const HomeScreen();
            break;
          case '/cotizaciones/menu':
            builder = const CotizacionesMenuScreen();
            break;
          case '/cotizaciones':
            final args = settings.arguments as Map<String, dynamic>?;
            builder = CotizacionesScreen(
              tipoVenta: args?['tipoVenta'] ?? 'cotizacion',
              initialTab: args?['initialTab'],
            );
            break;
          case '/cotizaciones/creacion':
            final args = settings.arguments as Map<String, dynamic>?;
            builder = CrearCotizacionScreen(
              cotizacionExistente: args?['cotizacionExistente'],
              displayId: args?['displayId'],
              tipoVenta: args?['tipoVenta'] ?? 'cotizacion',
            );
            break;
          case '/cotizaciones/escaneo':
            final args = settings.arguments as Map<String, dynamic>?;
            builder = CrearCotizacionEscaneadaScreen(
              cotizacionExistente: args?['cotizacionExistente'],
              displayId: args?['displayId'],
              tipoVenta: args?['tipoVenta'] ?? 'punto_venta',
            );
            break;
          case '/notas_entrega':
            final args = settings.arguments as Map<String, dynamic>?;
            builder = NotasEntregaScreen(
              tipoVenta: args?['tipoVenta'] ?? 'punto_venta',
            );
            break;
          case '/notas_entrega/creacion':
            final args = settings.arguments as Map<String, dynamic>?;
            builder = CrearNotaEntregaScreen(
              notaExistente: args?['notaExistente'],
              displayId: args?['displayId'],
              tipoVenta: args?['tipoVenta'] ?? 'punto_venta',
            );
            break;
          case '/clientes':
            builder = const ClientsScreen();
            break;
          case '/venta_institucional':
            final args = settings.arguments as Map<String, dynamic>?;
            builder = VentaInstitucionalScreen(
              tipoVenta: args?['tipoVenta'] ?? 'venta_institucional',
            );
            break;
          case '/inventario':
            builder = const local_screens.InventoryScreen();
            break;
          case '/almacenamiento':
            builder = const AlmacenamientoScreen();
            break;
          case '/almacenamiento/configuracion':
            builder = const AlmacenamientoConfiguracionScreen();
            break;
          case '/personal':
            builder = const PersonalManageScreen();
            break;
          case '/personalizacion':
            builder = const PersonalizacionScreen();
            break;
          default:
            builder = authed ? const HomeScreen() : const LoginScreen();
        }

        return MaterialPageRoute(
          builder: (context) => builder,
          settings: RouteSettings(name: targetRoute, arguments: settings.arguments),
        );
      },
    );
  }
}

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  static _ConnectivityWrapperState? _instance;

  static void rebuild() {
    _instance?._forceRebuild();
  }

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  bool _isConnected = true;
  bool _showRestored = false;
  Timer? _checkTimer;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    ConnectivityWrapper._instance = this;
    _checkConnectivity();
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkConnectivity());
  }

  @override
  void dispose() {
    if (ConnectivityWrapper._instance == this) {
      ConnectivityWrapper._instance = null;
    }
    _checkTimer?.cancel();
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _forceRebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkConnectivity() async {
    bool currentStatus = true;
    if (kIsWeb) {
      currentStatus = true;
    } else {
      try {
        final result = await InternetAddress.lookup('novaledbolivia.com').timeout(const Duration(seconds: 3));
        currentStatus = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } catch (_) {
        currentStatus = false;
      }
    }

    if (!mounted) return;

    if (currentStatus != _isConnected) {
      setState(() {
        if (currentStatus) {
          _isConnected = true;
          _showRestored = true;
          _dismissTimer?.cancel();
          _dismissTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _showRestored = false;
              });
            }
          });
        } else {
          _isConnected = false;
          _showRestored = false;
        }
      });
    }
  }

  String _getRoleLabel(UserRole? role) {
    if (role == null) return "";
    switch (role) {
      case UserRole.developer:
        return "vendedor"; // Se muestra como vendedor / dueño / según corresponda
      case UserRole.admin:
        return "almacenes";
      case UserRole.designer:
        return "diseñador";
      case UserRole.seller:
        return "vendedor";
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget banner = const SizedBox.shrink();
    Color bannerColor = Colors.transparent;

    if (!_isConnected) {
      bannerColor = Colors.orange[800]!;
      banner = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.wifi_off, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Sin conexión a internet. Modo offline activo",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none,
                fontFamily: 'Montserrat',
              ),
            ),
          ),
        ],
      );
    } else if (_showRestored) {
      bannerColor = Colors.green[700]!;
      banner = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.wifi, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            "se restablecio internet",
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      );
    }

    final double bannerHeight = (!_isConnected || _showRestored) ? 40.0 : 0.0;
    
    // Impersonación
    final bool isImpersonating = Session().isImpersonating;
    final double topBannerHeight = isImpersonating ? 45.0 : 0.0;

    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(top: topBannerHeight, bottom: bannerHeight),
            child: widget.child,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: bannerHeight,
            color: bannerColor,
            alignment: Alignment.center,
            child: bannerHeight > 0
                ? Material(color: Colors.transparent, child: banner)
                : const SizedBox.shrink(),
          ),
        ),
        // Banner de Impersonación / Modo de Prueba (Arriba)
        if (isImpersonating)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Material(
              color: Colors.amber[900],
              child: Container(
                height: 45.0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Row(
                  children: [
                    const Icon(Icons.supervised_user_circle, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "esta viendo como ${_getRoleLabel(Session().role)} (${Session().userName?.toLowerCase()})",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      tooltip: "Salir del modo de prueba",
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() {
                          Session().userName = Session().originalUserName;
                          Session().role = Session().originalRole;
                          Session().originalUserName = null;
                          Session().originalRole = null;
                        });
                        sessionNotifier.value++;
                        if (navigatorKey.currentState != null) {
                          navigatorKey.currentState!.pushNamedAndRemoveUntil('/home', (route) => false);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
