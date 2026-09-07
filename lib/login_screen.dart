import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'drive_service.dart';
import 'main.dart'; // Import para navigatorKey
import 'local_module/services/update_service.dart';
import 'local_module/services/sync_service.dart';
import 'local_module/database_helper.dart';
import 'local_module/tenant_helper.dart';


enum UserRole { admin, designer, seller, developer }

class Session {
  static final Session _instance = Session._internal();
  factory Session() => _instance;
  Session._internal();

  String? userName;
  UserRole? role;

  String? originalUserName;
  UserRole? originalRole;

  bool get isImpersonating => originalRole != null;

  bool get isAdmin => role == UserRole.admin || role == UserRole.developer;
  bool get isDesigner => role == UserRole.designer;
  bool get isSeller => role == UserRole.seller;

  void clear() {
    userName = null;
    role = null;
    originalUserName = null;
    originalRole = null;
  }

  static Future<void> forceLogout({String? message}) async {
    SessionWatchdog.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('novaled_jwt_token');
    await prefs.remove('remember_me');
    Session().clear();
    if (message != null && message.isNotEmpty) {
      await prefs.setString('logout_reason_message', message);
    }
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }
}

class SessionWatchdog {
  static Timer? _timer;
  static bool _isChecking = false;

  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => checkStatus());
    // Ejecución inmediata inicial
    Future.microtask(() => checkStatus());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> checkStatus() async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('novaled_jwt_token');
      if (token == null || token.isEmpty) {
        _isChecking = false;
        return;
      }

      final url = Uri.parse('https://novaledbolivia.com/sistema/api/get_users.php');
      final resp = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
        'X-Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 4));

      if (resp.statusCode == 403) {
        String msg = "Esta empresa ha sido suspendida o dada de baja por el administrador. El acceso ha sido cerrado.";
        try {
          final data = jsonDecode(resp.body);
          if (data is Map && data['message'] != null) {
            msg = data['message'].toString();
          } else if (data is Map && data['error'] != null) {
            msg = data['error'].toString();
          }
        } catch (_) {}
        stop();
        await Session.forceLogout(message: msg);
      }
    } catch (_) {} finally {
      _isChecking = false;
    }
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscureText = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _isGoogleConnected = false;

  final Map<String, String> _authorizedUsers = {
    "joel": _hashPassword("novaled"), // Especial Maestro
    "novaled.elektroshop@gmail.com": _hashPassword("novanovaled2026"), // Cuenta Empresa Novaled
    "almir": _hashPassword("novanovaled2026"),
    "victor": _hashPassword("novanovaled2026"),
    "gustavo": _hashPassword("novanovaled2026"),
    "alvaro": _hashPassword("novanovaled2026"),
    "kimen": _hashPassword("novanovaled2026"),
    "dani": _hashPassword("novanovaled2026"),
  };

  static String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  @override
  void initState() {
    super.initState();
    _loadRememberMe();
  }

  Future<void> _syncUsersFromMySQL() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('novaled_jwt_token') ?? '';
      if (token.isEmpty) {
        debugPrint("Saltando sync de usuarios de MySQL: No hay token de autenticación.");
        return;
      }
      
      final response = await http.get(
        Uri.parse('https://novaledbolivia.com/sistema/api/get_users.php'),
        headers: {
          'Authorization': 'Bearer $token',
          'X-Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final List<dynamic> mysqlUsers = jsonDecode(response.body);
        if (mysqlUsers.isNotEmpty) {
          await prefs.setString('novaled_custom_users', jsonEncode(mysqlUsers));
          
          if (mounted) {
            setState(() {
              _authorizedUsers.clear(); // Limpiar fijos/anteriores para reflejar eliminaciones
              for (var u in mysqlUsers) {
                final username = u['username']?.toString().toLowerCase().trim();
                final passwordHash = u['passwordHash']?.toString();
                if (username != null && passwordHash != null) {
                  _authorizedUsers[username] = passwordHash;
                }
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error sincronizando usuarios de MySQL: $e");
    }
  }

  void _loadRememberMe() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Mostrar mensaje de logout si existe y omitir auto-login silencioso
    final logoutReason = prefs.getString('logout_reason_message');
    if (logoutReason != null && logoutReason.isNotEmpty) {
      await prefs.remove('logout_reason_message');
      
      // Cargar el último usuario para facilitar el re-login
      final rememberMe = prefs.getBool('remember_me') ?? false;
      if (rememberMe) {
        _userController.text = prefs.getString('saved_user') ?? '';
        setState(() {
          _rememberMe = true;
        });
      } else {
        _userController.text = prefs.getString('last_user') ?? '';
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⚠️ $logoutReason"),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 5),
          ),
        );
      });
      return; // Detener auto-login silencioso
    }

    // Cargar usuarios personalizados de la caché local e insertarlos en la lista autorizada
    try {
      final customUsersJson = prefs.getString('novaled_custom_users');
      if (customUsersJson != null) {
        final List<dynamic> list = jsonDecode(customUsersJson);
        _authorizedUsers.clear(); // Limpiar fijos locales si ya tenemos caché guardada
        for (var u in list) {
          final userMap = u as Map<String, dynamic>;
          final username = userMap['username']?.toString().toLowerCase().trim();
          final passwordHash = userMap['passwordHash']?.toString();
          if (username != null && passwordHash != null) {
            _authorizedUsers[username] = passwordHash;
          }
        }
      }
    } catch (e) {
      debugPrint("Error leyendo usuarios personalizados cache: $e");
    }

    final rememberMe = prefs.getBool('remember_me') ?? false;
    if (rememberMe) {
      final savedUser = prefs.getString('saved_user') ?? '';
      final savedPass = prefs.getString('saved_pass') ?? '';
      if (savedUser.isNotEmpty && savedPass.isNotEmpty) {
        _userController.text = savedUser;
        _passController.text = savedPass;
        setState(() {
          _rememberMe = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _login(silent: true);
        });
      }
    } else {
      final lastUser = prefs.getString('last_user') ?? '';
      if (lastUser.isNotEmpty) {
        _userController.text = lastUser;
      }
    }
  }

  Future<void> _login({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final user = _userController.text.toLowerCase().trim();
    final pass = _passController.text.trim();
    final hashedInput = _hashPassword(pass);
    
    bool loggedInOnServer = false;
    String? token;
    String? resolvedRole;
    List<dynamic>? remoteUsers;
    bool isNetworkError = false;

    // Intentar login online primero
    try {
      final response = await http.post(
        Uri.parse('https://novaledbolivia.com/sistema/api/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': user,
          'passwordHash': hashedInput,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        if (resJson['success'] == true) {
          loggedInOnServer = true;
          token = resJson['token'];
          resolvedRole = resJson['role'];
          remoteUsers = resJson['users'];
        }
      }
    } catch (e) {
      debugPrint("Servidor de login inaccesible (modo offline/error): $e");
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') || 
          errStr.contains('timeoutexception') || 
          errStr.contains('handshakeexception') ||
          errStr.contains('connection failed') ||
          errStr.contains('network is unreachable')) {
        isNetworkError = true;
      }
    }

    if (loggedInOnServer) {
      final session = Session();
      final prefs = await SharedPreferences.getInstance();
      
      session.userName = user.toUpperCase();
      if (token != null) {
        await prefs.setString('novaled_jwt_token', token);
      }

      // Actualizar caché de usuarios recibida del login exitoso
      if (remoteUsers != null && remoteUsers.isNotEmpty) {
        await prefs.setString('novaled_custom_users', jsonEncode(remoteUsers));
        _authorizedUsers.clear();
        for (var u in remoteUsers) {
          final username = u['username']?.toString().toLowerCase().trim();
          final passwordHash = u['passwordHash']?.toString();
          if (username != null && passwordHash != null) {
            _authorizedUsers[username] = passwordHash;
          }
        }
      }

      if (resolvedRole == 'developer') {
        session.role = UserRole.developer;
      } else if (resolvedRole == 'admin') {
        session.role = UserRole.admin;
      } else if (resolvedRole == 'designer') {
        session.role = UserRole.designer;
      } else {
        session.role = UserRole.seller;
      }

      await prefs.setString('last_user', user);
      await prefs.setBool('remember_me', _rememberMe);
      
      if (_rememberMe) {
        await prefs.setString('saved_user', user);
        await prefs.setString('saved_pass', pass);
      } else {
        await prefs.remove('saved_user');
        await prefs.remove('saved_pass');
      }

      // Conectar / Aislar la base de datos correspondiente a este usuario o empresa
      await DatabaseHelper.instance.switchTenant(user);
      TenantHelper.syncTenantSettings();
      SyncService.instance.syncEverything().catchError((e) {});

      if (mounted) {
        try {
          NovaledApp.of(context).reloadBrandColor();
        } catch (_) {}
        setState(() => _isLoading = false);
        Navigator.pushReplacementNamed(context, '/home');
      }
      return;
    }

    // Fallback a login offline ÚNICAMENTE si no hay conexión a internet (isNetworkError)
    if (isNetworkError) {
      final prefs = await SharedPreferences.getInstance();
      try {
        final customUsersJson = prefs.getString('novaled_custom_users');
        if (customUsersJson != null) {
          final List<dynamic> list = jsonDecode(customUsersJson);
          for (var u in list) {
            final userMap = u as Map<String, dynamic>;
            final username = userMap['username']?.toString().toLowerCase().trim();
            final passwordHash = userMap['passwordHash']?.toString();
            if (username != null && passwordHash != null) {
              _authorizedUsers[username] = passwordHash;
            }
          }
        }
      } catch (e) {
        debugPrint("Error actualizando mapa de usuarios al loguear offline: $e");
      }

      if (_authorizedUsers.containsKey(user) && _authorizedUsers[user] == hashedInput) {
        final session = Session();
        session.userName = user.toUpperCase();

        // Encontrar rol del usuario en la lista cargada
        try {
          final customUsersJson = prefs.getString('novaled_custom_users');
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
          debugPrint("Error resolviendo rol offline: $e");
        }

        // Fallback a los valores históricos
        if (session.role == null) {
          if (user == "almir" || user == "joel") {
            session.role = UserRole.developer;
          } else if (user == "victor") {
            session.role = UserRole.designer;
          } else if (user == "novaled.elektroshop@gmail.com") {
            session.role = UserRole.admin;
          } else {
            session.role = UserRole.seller;
          }
        }

        await prefs.setString('last_user', user);
        await prefs.setBool('remember_me', _rememberMe);
        
        if (_rememberMe) {
          await prefs.setString('saved_user', user);
          await prefs.setString('saved_pass', pass);
        } else {
          await prefs.remove('saved_user');
          await prefs.remove('saved_pass');
        }

        // Conectar / Aislar la base de datos correspondiente a este usuario o empresa
        await DatabaseHelper.instance.switchTenant(user);
        TenantHelper.syncTenantSettings(); // Sincronizar vendedores y configuraciones entre todos los dispositivos

        if (mounted) {
          try {
            NovaledApp.of(context).reloadBrandColor();
          } catch (_) {}
          setState(() => _isLoading = false);
          Navigator.pushReplacementNamed(context, '/home');
        }
        return;
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
    if (!silent && mounted) {
      final message = isNetworkError
          ? "⚠️ Sin conexión a internet. No se pudo validar en línea y no hay credenciales locales guardadas para este usuario."
          : "❌ Credenciales inválidas";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isNetworkError ? Colors.orange[800] : Colors.red,
          duration: Duration(seconds: isNetworkError ? 5 : 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryPurple = const Color(0xFF5842F4);
    final bgColor = isDark ? const Color(0xFF131510) : const Color(0xFFF3F5FD);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      // Header Section: Title + Subtitle on Left, Purple Circle Lock Icon on Right
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Bienvenido!",
                                  style: GoogleFonts.poppins(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Inicia sesión para continuar",
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: isDark ? Colors.white60 : const Color(0xFF8C98B6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: primaryPurple,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.lock_outline_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),

                      // Campo Usuario
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Image.asset(
                                'Iconos/pantalla 1/usuario.png',
                                width: 16,
                                height: 16,
                                color: isDark ? Colors.white70 : const Color(0xFF8C98B6),
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.person_outline_rounded,
                                  size: 16,
                                  color: isDark ? Colors.white70 : const Color(0xFF8C98B6),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Usuario",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: isDark ? Colors.white70 : const Color(0xFF8C98B6),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _userController,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              border: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: isDark ? Colors.white24 : const Color(0xFF475569),
                                  width: 1,
                                ),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: isDark ? Colors.white24 : const Color(0xFF475569),
                                  width: 1,
                                ),
                              ),
                              focusedBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0xFF5842F4),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Campo Contraseña
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Image.asset(
                                'Iconos/pantalla 1/candado.png',
                                width: 16,
                                height: 16,
                                color: isDark ? Colors.white70 : const Color(0xFF8C98B6),
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.lock_outline_rounded,
                                  size: 16,
                                  color: isDark ? Colors.white70 : const Color(0xFF8C98B6),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Contraseña",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: isDark ? Colors.white70 : const Color(0xFF8C98B6),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _passController,
                            obscureText: _obscureText,
                            onSubmitted: (_) => _login(),
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              suffixIconConstraints: const BoxConstraints(maxHeight: 28, minWidth: 28),
                              suffixIcon: GestureDetector(
                                onTap: () => setState(() => _obscureText = !_obscureText),
                                child: Image.asset(
                                  'Iconos/pantalla 1/visualizar.png',
                                  width: 20,
                                  height: 20,
                                  color: isDark ? Colors.white70 : const Color(0xFF8C98B6),
                                  errorBuilder: (_, __, ___) => Icon(
                                    _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                    size: 20,
                                    color: isDark ? Colors.white70 : const Color(0xFF8C98B6),
                                  ),
                                ),
                              ),
                              border: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: isDark ? Colors.white24 : const Color(0xFF475569),
                                  width: 1,
                                ),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: isDark ? Colors.white24 : const Color(0xFF475569),
                                  width: 1,
                                ),
                              ),
                              focusedBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0xFF5842F4),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Recordar Contraseña
                      Row(
                        children: [
                          SizedBox(
                            height: 22,
                            width: 22,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: primaryPurple,
                              checkColor: Colors.white,
                              side: BorderSide(color: isDark ? Colors.white38 : const Color(0xFF94A3B8), width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              onChanged: (val) {
                                setState(() {
                                  _rememberMe = val ?? false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "Recordar contraseña",
                            style: GoogleFonts.poppins(
                              color: isDark ? Colors.white70 : const Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 36),

                      // Botón Iniciar Sesión
                      _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF5842F4),
                              ),
                            )
                          : SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: () => _login(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryPurple,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(27),
                                  ),
                                ),
                                child: Text(
                                  "Iniciar sesión",
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),

                       const SizedBox(height: 60),

                      // Footer: Logo Lumis (reemplaza 'impulsado por novastore')
                      Center(
                        child: Image.asset(
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
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              bottom: 20,
              child: Text(
                "v${UpdateService.currentVersion}",
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white30 : Colors.black26,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
