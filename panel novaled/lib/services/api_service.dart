import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://novaledbolivia.com/sistema/api';
  static String? _jwtToken;

  static String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  static Future<bool> loginSuperadmin({
    String username = 'joel',
    String password = 'novaled',
  }) async {
    try {
      final hashed = _hashPassword(password);
      final response = await http.post(
        Uri.parse('$baseUrl/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'passwordHash': hashed,
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['token'] != null) {
          _jwtToken = data['token'];
          debugPrint("[ONLINE] Conectado exitosamente con servidor MySQL: token obtenido.");
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint("[ONLINE] Error de conexión con el servidor: $e");
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchLiveUsers() async {
    try {
      if (_jwtToken == null) {
        await loginSuperadmin();
      }

      var response = await http.get(
        Uri.parse('$baseUrl/get_users.php'),
        headers: {
          'Authorization': 'Bearer $_jwtToken',
          'X-Authorization': 'Bearer $_jwtToken',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 401) {
        await loginSuperadmin();
        response = await http.get(
          Uri.parse('$baseUrl/get_users.php'),
          headers: {
            'Authorization': 'Bearer $_jwtToken',
            'X-Authorization': 'Bearer $_jwtToken',
          },
        ).timeout(const Duration(seconds: 8));
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      }
      return [];
    } catch (e) {
      debugPrint("[ONLINE] Error obteniendo usuarios del servidor: $e");
      return [];
    }
  }

  static Future<bool> saveLiveUsers(List<Map<String, dynamic>> users) async {
    try {
      if (_jwtToken == null) {
        await loginSuperadmin();
      }

      var response = await http.post(
        Uri.parse('$baseUrl/save_users.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
          'X-Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode(users),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 401) {
        await loginSuperadmin();
        response = await http.post(
          Uri.parse('$baseUrl/save_users.php'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_jwtToken',
            'X-Authorization': 'Bearer $_jwtToken',
          },
          body: jsonEncode(users),
        ).timeout(const Duration(seconds: 8));
      }

      final isSuccess = response.statusCode == 200;
      debugPrint("[ONLINE] Guardar usuarios resultado: ${response.statusCode} (success: $isSuccess)");
      return isSuccess;
    } catch (e) {
      debugPrint("[ONLINE] Error guardando usuarios en servidor: $e");
      return false;
    }
  }

  static Future<Map<String, dynamic>?> fetchLiveTenantStats() async {
    try {
      if (_jwtToken == null) {
        await loginSuperadmin();
      }

      var response = await http.get(
        Uri.parse('$baseUrl/get_tenant_stats.php'),
        headers: {
          'Authorization': 'Bearer $_jwtToken',
          'X-Authorization': 'Bearer $_jwtToken',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 401) {
        await loginSuperadmin();
        response = await http.get(
          Uri.parse('$baseUrl/get_tenant_stats.php'),
          headers: {
            'Authorization': 'Bearer $_jwtToken',
            'X-Authorization': 'Bearer $_jwtToken',
          },
        ).timeout(const Duration(seconds: 8));
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['success'] == true) {
          return data;
        }
      }
      return null;
    } catch (e) {
      debugPrint("[ONLINE] Error obteniendo estadísticas de empresas: $e");
      return null;
    }
  }

  static Future<bool> manageTenant({
    required String tenantKey,
    required String action, // 'soft_delete', 'restore', 'hard_delete'
    String email = '',
  }) async {
    try {
      if (_jwtToken == null) {
        await loginSuperadmin();
      }

      var response = await http.post(
        Uri.parse('$baseUrl/manage_tenant.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
          'X-Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode({
          'tenant_key': tenantKey,
          'action': action,
          'email': email,
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 401) {
        await loginSuperadmin();
        response = await http.post(
          Uri.parse('$baseUrl/manage_tenant.php'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_jwtToken',
            'X-Authorization': 'Bearer $_jwtToken',
          },
          body: jsonEncode({
            'tenant_key': tenantKey,
            'action': action,
            'email': email,
          }),
        ).timeout(const Duration(seconds: 8));
      }

      final isSuccess = response.statusCode == 200;
      debugPrint("[ONLINE] manageTenant ($action) resultado: ${response.statusCode}");
      return isSuccess;
    } catch (e) {
      debugPrint("[ONLINE] Error ejecutando manageTenant ($action): $e");
      return false;
    }
  }

  static Future<bool> uploadTenantSettings({
    required String tenantKey,
    required Map<String, dynamic> settings,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/tenant_settings.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tenant_key': tenantKey,
          'settings': settings,
        }),
      ).timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint("[ONLINE] Error subiendo tenant settings: $e");
      return false;
    }
  }
}
