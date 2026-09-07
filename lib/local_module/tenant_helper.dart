import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p_path;
import 'package:path_provider/path_provider.dart';
import 'services/sync_service.dart';
import 'database_helper.dart';
import '../login_screen.dart';

class TenantHelper {
  static const Set<String> novaledMembers = {
    'novaled',
    'novaled.elektroshop@gmail.com',
    'novaled@gmail.com',
    'joel',
    'almir',
    'victor',
    'gustavo',
    'alvaro',
    'kimen',
    'dani',
    'celia',
    'novaled.db',
  };

  static bool isNovaled(String? identifier) {
    if (identifier == null || identifier.trim().isEmpty) {
      final sessionUser = Session().userName;
      if (sessionUser != null && sessionUser.trim().isNotEmpty) {
        final clean = sessionUser.toLowerCase().trim();
        return novaledMembers.contains(clean) || clean.contains('novaled') || clean == 'novaled.db';
      }
      return true;
    }
    final clean = identifier.toLowerCase().trim();
    return novaledMembers.contains(clean) || clean.contains('novaled') || clean == 'novaled.db';
  }

  static String getTenantKey(String? identifier) {
    if (identifier == null || identifier.trim().isEmpty) {
      final sessionUser = Session().userName;
      if (sessionUser != null && sessionUser.trim().isNotEmpty) {
        return getTenantKey(sessionUser);
      }
      return 'novaled';
    }
    if (isNovaled(identifier)) {
      return 'novaled';
    }
    final clean = identifier.toLowerCase().trim();
    final safe = clean.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    return 'tenant_$safe';
  }

  static Future<String> getActiveTenantKey() async {
    try {
      final sessionUser = Session().userName;
      if (sessionUser != null && sessionUser.trim().isNotEmpty) {
        return getTenantKey(sessionUser);
      }
      final prefs = await SharedPreferences.getInstance();
      final active = prefs.getString('last_user') ?? prefs.getString('saved_user') ?? '';
      return getTenantKey(active);
    } catch (_) {
      return 'novaled';
    }
  }

  static Future<bool> isActiveNovaled() async {
    try {
      final sessionUser = Session().userName;
      if (sessionUser != null && sessionUser.trim().isNotEmpty) {
        return isNovaled(sessionUser);
      }
      final prefs = await SharedPreferences.getInstance();
      final active = prefs.getString('last_user') ?? prefs.getString('saved_user') ?? '';
      return isNovaled(active);
    } catch (_) {
      return true;
    }
  }

  /// Clave prefijada para SharedPreferences de cada empresa
  static String k(String key, String tenantKey) {
    if (tenantKey == 'novaled') {
      return key; // Para Novaled se preservan las claves históricas intactas
    }
    return '${tenantKey}_$key';
  }

  /// Sincroniza desde la nube la configuración de la empresa/tenant (vendedores, sucursales, colores, info)
  static Future<void> syncTenantSettings() async {
    try {
      final tenantKey = await getActiveTenantKey();
      final url = Uri.parse('https://novaledbolivia.com/sistema/api/tenant_settings.php?tenant_key=$tenantKey');
      final resp = await http.get(url, headers: {'User-Agent': 'NovaledApp'}).timeout(const Duration(seconds: 8));
      
      if (resp.statusCode == 200) {
        String body = resp.body;
        if (body.startsWith('\uFEFF')) {
          body = body.substring(1);
        }
        final Map<String, dynamic> data = jsonDecode(body);
        if (data['success'] == true && data['settings'] is Map) {
          final Map<String, dynamic> settings = data['settings'];
          final prefs = await SharedPreferences.getInstance();

          // Sincronizar vendedores
          if (settings.containsKey('system_vendedores') && settings['system_vendedores'] is List) {
            final List<String> list = List<String>.from(settings['system_vendedores'].map((e) => e.toString().trim().toUpperCase()));
            await prefs.setStringList(k('system_vendedores', tenantKey), list);
          }

          // Sincronizar sucursales
          if (settings.containsKey('system_sucursales') && settings['system_sucursales'] is List) {
            final List<String> list = List<String>.from(settings['system_sucursales'].map((e) => e.toString().trim()));
            await prefs.setStringList(k('system_sucursales', tenantKey), list);
          }

          // Sincronizar plan
          if (settings.containsKey('plan_id')) {
            await prefs.setString(k('plan_id', tenantKey), settings['plan_id']?.toString() ?? 'free');
          } else {
            await prefs.setString(k('plan_id', tenantKey), tenantKey == 'novaled' ? 'plus' : 'free');
          }

          // Sincronizar info y colores
          if (settings.containsKey('pdf_company_name')) await prefs.setString(k('pdf_company_name', tenantKey), settings['pdf_company_name'] ?? '');
          if (settings.containsKey('pdf_company_email')) await prefs.setString(k('pdf_company_email', tenantKey), settings['pdf_company_email'] ?? '');
          if (settings.containsKey('pdf_company_phone')) await prefs.setString(k('pdf_company_phone', tenantKey), settings['pdf_company_phone'] ?? '');
          if (settings.containsKey('pdf_company_address')) await prefs.setString(k('pdf_company_address', tenantKey), settings['pdf_company_address'] ?? '');
          if (settings.containsKey('pdf_company_nit')) await prefs.setString(k('pdf_company_nit', tenantKey), settings['pdf_company_nit'] ?? '');
          if (settings.containsKey('pdf_company_currency')) await prefs.setString(k('pdf_company_currency', tenantKey), settings['pdf_company_currency'] ?? '');
          if (settings.containsKey('pdf_social_handle')) await prefs.setString(k('pdf_social_handle', tenantKey), settings['pdf_social_handle'] ?? '');
          if (settings.containsKey('pdf_website')) await prefs.setString(k('pdf_website', tenantKey), settings['pdf_website'] ?? '');
          
          if (settings.containsKey('pdf_primary_color')) await prefs.setInt(k('pdf_primary_color', tenantKey), int.tryParse(settings['pdf_primary_color'].toString()) ?? 0xFF5D43FF);
          if (settings.containsKey('pdf_icon_color')) await prefs.setInt(k('pdf_icon_color', tenantKey), int.tryParse(settings['pdf_icon_color'].toString()) ?? 0xFFA199F7);
          if (settings.containsKey('pdf_card_color')) await prefs.setInt(k('pdf_card_color', tenantKey), int.tryParse(settings['pdf_card_color'].toString()) ?? 0xFFDEE8F5);
          if (settings.containsKey('pdf_bg_color')) await prefs.setInt(k('pdf_bg_color', tenantKey), int.tryParse(settings['pdf_bg_color'].toString()) ?? 0xFFF4F7FB);
          if (settings.containsKey('pdf_selected_palette_index')) await prefs.setInt(k('pdf_selected_palette_index', tenantKey), int.tryParse(settings['pdf_selected_palette_index'].toString()) ?? 0);
          if (settings.containsKey('pdf_logo_scale')) await prefs.setDouble(k('pdf_logo_scale', tenantKey), double.tryParse(settings['pdf_logo_scale'].toString()) ?? 1.0);
          
          debugPrint("[MULTI-DEVICE] Configuración y paleta sincronizadas exitosamente desde la nube para: $tenantKey");
        }
      }
    } catch (e) {
      debugPrint("[MULTI-DEVICE] Error sincronizando tenant settings: $e");
    }
  }

  static Future<bool> isFreePlan() async {
    final tenantKey = await getActiveTenantKey();
    if (tenantKey == 'novaled') return false; // Novaled is Plus
    final prefs = await SharedPreferences.getInstance();
    final plan = prefs.getString(k('plan_id', tenantKey)) ?? 'free';
    return plan == 'free';
  }

  /// Sube a la nube la configuración de la empresa/tenant para que todos los dispositivos la tengan
  static Future<void> uploadTenantSettings({
    List<String>? vendedores,
    List<String>? sucursales,
    String? companyName,
    String? companyEmail,
    String? companyPhone,
    String? companyAddress,
    String? companyNit,
    String? companyCurrency,
    String? socialHandle,
    String? website,
    int? primaryColor,
    int? iconColor,
    int? cardColor,
    int? bgColor,
    int? paletteIndex,
    double? logoScale,
    int? totalEscaneos,
  }) async {
    try {
      final tenantKey = await getActiveTenantKey();
      final prefs = await SharedPreferences.getInstance();

      final payloadSettings = <String, dynamic>{
        'system_vendedores': vendedores ?? prefs.getStringList(k('system_vendedores', tenantKey)) ?? [],
        'system_sucursales': sucursales ?? prefs.getStringList(k('system_sucursales', tenantKey)) ?? [],
        'pdf_company_name': companyName ?? prefs.getString(k('pdf_company_name', tenantKey)) ?? '',
        'pdf_company_email': companyEmail ?? prefs.getString(k('pdf_company_email', tenantKey)) ?? '',
        'pdf_company_phone': companyPhone ?? prefs.getString(k('pdf_company_phone', tenantKey)) ?? '',
        'pdf_company_address': companyAddress ?? prefs.getString(k('pdf_company_address', tenantKey)) ?? '',
        'pdf_company_nit': companyNit ?? prefs.getString(k('pdf_company_nit', tenantKey)) ?? '',
        'pdf_company_currency': companyCurrency ?? prefs.getString(k('pdf_company_currency', tenantKey)) ?? '',
        'pdf_social_handle': socialHandle ?? prefs.getString(k('pdf_social_handle', tenantKey)) ?? '',
        'pdf_website': website ?? prefs.getString(k('pdf_website', tenantKey)) ?? '',
        'pdf_primary_color': primaryColor ?? prefs.getInt(k('pdf_primary_color', tenantKey)) ?? 0xFF5D43FF,
        'pdf_icon_color': iconColor ?? prefs.getInt(k('pdf_icon_color', tenantKey)) ?? 0xFFA199F7,
        'pdf_card_color': cardColor ?? prefs.getInt(k('pdf_card_color', tenantKey)) ?? 0xFFDEE8F5,
        'pdf_bg_color': bgColor ?? prefs.getInt(k('pdf_bg_color', tenantKey)) ?? 0xFFF4F7FB,
        'pdf_selected_palette_index': paletteIndex ?? prefs.getInt(k('pdf_selected_palette_index', tenantKey)) ?? 0,
        'pdf_logo_scale': logoScale ?? prefs.getDouble(k('pdf_logo_scale', tenantKey)) ?? 1.0,
      };

      if (totalEscaneos != null) {
        payloadSettings['total_escaneos'] = totalEscaneos;
        payloadSettings['scans_count'] = totalEscaneos;
      }

      final url = Uri.parse('https://novaledbolivia.com/sistema/api/tenant_settings.php');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'User-Agent': 'NovaledApp'},
        body: jsonEncode({
          'tenant_key': tenantKey,
          'settings': payloadSettings,
        }),
      ).timeout(const Duration(seconds: 8));

      debugPrint("[MULTI-DEVICE] Configuración y paleta subidas a la nube (status ${resp.statusCode}) para: $tenantKey");
    } catch (e) {
      debugPrint("[MULTI-DEVICE] Error subiendo tenant settings: $e");
    }
  }

  /// Obtiene la lista unificada de vendedores/asesores para el tenant activo.
  static Future<List<String>> getVendedores() async {
    final prefs = await SharedPreferences.getInstance();
    final tenantKey = await getActiveTenantKey();
    final isNovaled = tenantKey == 'novaled';

    // 1. Si ya existe la lista guardada/editada por el usuario, respetarla al 100% (lo que se borra no reaparece)
    final saved = prefs.getStringList(k('system_vendedores', tenantKey));
    if (saved != null) {
      return saved;
    }

    // 2. Fallback inicial por defecto solo si nunca se ha configurado:
    if (isNovaled) {
      return ["JOEL", "ALMIR", "GABRIEL", "CELIA"];
    }

    final currentUser = Session().userName?.trim();
    if (currentUser != null && currentUser.isNotEmpty) {
      final displayName = currentUser.contains('@') ? currentUser.split('@').first.toUpperCase() : currentUser.toUpperCase();
      return [displayName];
    }
    return [];
  }

  /// Obtiene la lista de sucursales para el tenant activo.
  static Future<List<String>> getSucursales() async {
    final prefs = await SharedPreferences.getInstance();
    final tenantKey = await getActiveTenantKey();
    final isNovaled = tenantKey == 'novaled';

    // 1. Si ya existe la lista guardada/editada por el usuario, respetarla al 100%
    final saved = prefs.getStringList(k('system_sucursales', tenantKey));
    if (saved != null) {
      return saved;
    }

    // 2. Fallback inicial por defecto solo si nunca se ha configurado:
    if (isNovaled) {
      return ["C. Isaac Tamayo #840 La Paz - Bolivia", "C. Isaac Tamayo #818 La Paz - Bolivia"];
    }
    final customAddress = prefs.getString(k('pdf_company_address', tenantKey));
    if (customAddress != null && customAddress.trim().isNotEmpty) {
      return [customAddress.trim()];
    }
    return [];
  }

  /// Comprime una imagen (máx 1200px, JPEG 75%) y la sube a Hostinger para no saturar la base de datos
  static Future<String?> processAndUploadReceipt(XFile pickedFile) async {
    try {
      final rawBytes = await pickedFile.readAsBytes();
      Uint8List compressedBytes = rawBytes;
      try {
        final decoded = img.decodeImage(rawBytes);
        if (decoded != null) {
          img.Image resized = decoded;
          if (decoded.width > 1200 || decoded.height > 1200) {
            if (decoded.width >= decoded.height) {
              resized = img.copyResize(decoded, width: 1200);
            } else {
              resized = img.copyResize(decoded, height: 1200);
            }
          }
          compressedBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 75));
        }
      } catch (e) {
        debugPrint("Error al comprimir comprobante: $e");
      }

      // Subir a Hostinger
      final cloudFilename = await SyncService.instance.uploadImageToHostinger(
        compressedBytes,
        'COMP_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      // Guardar caché local
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final localFileName = cloudFilename ?? 'comprobante_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final localFile = File('${appDir.path}/$localFileName');
        await localFile.writeAsBytes(compressedBytes);
      } catch (_) {}

      return cloudFilename ?? pickedFile.path;
    } catch (e) {
      debugPrint("Error procesando/subiendo comprobante: $e");
      return null;
    }
  }

  /// Construye un widget de imagen para el comprobante compatible con URL de Hostinger o archivo local
  static Widget buildReceiptImage(String imgPath, {double? width, double? height, BoxFit fit = BoxFit.contain}) {
    if (imgPath.startsWith('http://') || imgPath.startsWith('https://')) {
      return Image.network(
        imgPath,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey)),
      );
    }
    if (!kIsWeb && File(imgPath).existsSync()) {
      return Image.file(
        File(imgPath),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey)),
      );
    }
    final cleanName = p_path.basename(imgPath);
    final cloudUrl = 'https://novaledbolivia.com/sistema/api/uploads/$cleanName';
    return Image.network(
      cloudUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey)),
    );
  }
}

class PlanLimitHelper {
  static const int freeCotizaciones = 5;
  static const int freeNotasVenta = 5;
  static const int freeNotasEntrega = 5;
  static const int freeEscaneos = 5;
  static const int freeUsuarios = 2;

  static const int proEscaneos = 50;
  static const int proUsuarios = 6;

  static Future<String> getPlanId() async {
    final tenantKey = await TenantHelper.getActiveTenantKey();
    if (tenantKey == 'novaled') return 'plus';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(TenantHelper.k('plan_id', tenantKey)) ?? 'free';
  }

  static Future<int> getUsedCotizacionesCount() async {
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(TenantHelper.k('cumulative_cotizaciones_created', tenantKey)) ?? 0;
    
    final all = await DatabaseHelper.instance.queryAllCotizaciones();
    int highestDisplayId = 0;
    for (var d in all) {
      final did = (d['displayId'] as int?) ?? 0;
      if (did > highestDisplayId) highestDisplayId = did;
    }
    
    final counts = [stored, all.length, highestDisplayId];
    int used = counts.reduce((a, b) => a > b ? a : b);
    if (used > stored) {
      await prefs.setInt(TenantHelper.k('cumulative_cotizaciones_created', tenantKey), used);
    }
    return used;
  }

  static Future<int> getUsedNotasEntregaCount() async {
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(TenantHelper.k('cumulative_notas_entrega_created', tenantKey)) ?? 0;
    
    final all = await DatabaseHelper.instance.queryAllNotasEntrega();
    int highestDisplayId = 0;
    for (var d in all) {
      final did = (d['displayId'] as int?) ?? 0;
      if (did > highestDisplayId) highestDisplayId = did;
    }
    
    final counts = [stored, all.length, highestDisplayId];
    int used = counts.reduce((a, b) => a > b ? a : b);
    if (used > stored) {
      await prefs.setInt(TenantHelper.k('cumulative_notas_entrega_created', tenantKey), used);
    }
    return used;
  }

  static Future<int> getUsedNotasVentaCount() async {
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(TenantHelper.k('cumulative_notas_venta_created', tenantKey)) ?? 0;
    
    final all = await DatabaseHelper.instance.queryAllProformas();
    int highestDisplayId = 0;
    for (var d in all) {
      final did = (d['displayId'] as int?) ?? 0;
      if (did > highestDisplayId) highestDisplayId = did;
    }
    
    final counts = [stored, all.length, highestDisplayId];
    int used = counts.reduce((a, b) => a > b ? a : b);
    if (used > stored) {
      await prefs.setInt(TenantHelper.k('cumulative_notas_venta_created', tenantKey), used);
    }
    return used;
  }

  static Future<void> registerCotizacionCreated() async {
    final current = await getUsedCotizacionesCount();
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(TenantHelper.k('cumulative_cotizaciones_created', tenantKey), current + 1);
  }

  static Future<void> registerNotaEntregaCreated() async {
    final current = await getUsedNotasEntregaCount();
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(TenantHelper.k('cumulative_notas_entrega_created', tenantKey), current + 1);
  }

  static Future<void> registerNotaVentaCreated() async {
    final current = await getUsedNotasVentaCount();
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(TenantHelper.k('cumulative_notas_venta_created', tenantKey), current + 1);
  }

  static Future<bool> canCreateCotizacion() async {
    final plan = await getPlanId();
    if (plan != 'free') return true;
    final totalUsed = await getUsedCotizacionesCount();
    return totalUsed < freeCotizaciones;
  }

  static Future<bool> canCreateNotaEntrega() async {
    final plan = await getPlanId();
    if (plan != 'free') return true;
    final totalUsed = await getUsedNotasEntregaCount();
    return totalUsed < freeNotasEntrega;
  }

  static Future<bool> canCreateNotaVenta() async {
    final plan = await getPlanId();
    if (plan != 'free') return true;
    final totalUsed = await getUsedNotasVentaCount();
    return totalUsed < freeNotasVenta;
  }

  static Future<bool> canScan() async {
    final plan = await getPlanId();
    if (plan == 'plus') return true;
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final prefs = await SharedPreferences.getInstance();
    final currentMonthKey = "${DateTime.now().year}_${DateTime.now().month}";
    final lastMonthKey = prefs.getString(TenantHelper.k('scans_month_key', tenantKey)) ?? '';
    if (lastMonthKey != currentMonthKey) {
      await prefs.setString(TenantHelper.k('scans_month_key', tenantKey), currentMonthKey);
      await prefs.setInt(TenantHelper.k('scans_count_month', tenantKey), 0);
    }
    final scansUsed = prefs.getInt(TenantHelper.k('scans_count_month', tenantKey)) ?? 0;
    if (plan == 'free') return scansUsed < freeEscaneos;
    if (plan == 'pro') return scansUsed < proEscaneos;
    return true;
  }

  static Future<void> incrementScanCount() async {
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(TenantHelper.k('scans_count_month', tenantKey)) ?? 0;
    final updated = current + 1;
    await prefs.setInt(TenantHelper.k('scans_count_month', tenantKey), updated);
    try {
      await TenantHelper.uploadTenantSettings(totalEscaneos: updated);
    } catch (_) {}
  }

  static Future<bool> canCreateUser(int currentUsersCount) async {
    final plan = await getPlanId();
    if (plan == 'plus') return true;
    if (plan == 'free') return currentUsersCount < freeUsuarios;
    if (plan == 'pro') return currentUsersCount < proUsuarios;
    return true;
  }

  static void showUpgradeDialog(BuildContext context, {required String feature, required int currentLimit}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.stars_rounded, color: Color(0xFFEAB308), size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Límite del Plan Alcanzado",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
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
              "Has alcanzado el límite máximo de $currentLimit $feature incluido en el Plan Gratis.",
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
              ),
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
                  const Text(
                    "⭐ Beneficios Plan PRO (Bs. 95/mes):",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A45F5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "• Cotizaciones, Ventas y Entregas ILIMITADAS\n• Modo edición y colores desbloqueados\n• 50 escaneos mágicos por mes\n• Hasta 6 usuarios para tu equipo",
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Entendido",
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF5A45F5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
