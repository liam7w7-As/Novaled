import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../database_helper.dart';
import '../tenant_helper.dart';
import '../../drive_service.dart';
import '../../login_screen.dart';
import '../../main.dart';

enum ReauthResult {
  success,
  invalidCredentials,
  networkError,
  noSavedCredentials
}

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  String _generateUuid(String table) {
    final rand = Random().nextInt(1000000);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${table.toUpperCase()}_${timestamp}_$rand';
  }

  final Map<String, bool> _activeSyncs = {};
  final Map<String, bool> _pendingSyncs = {};

  Future<bool> syncTable(String table) async {
    if (_activeSyncs[table] == true) {
      _pendingSyncs[table] = true;
      return false;
    }
    _activeSyncs[table] = true;

    final tenantKey = await TenantHelper.getActiveTenantKey();
    final prefs = await SharedPreferences.getInstance();
    final isDirtyKey = 'is_dirty_${tenantKey}_$table';
    final lastSyncKey = 'last_sync_${tenantKey}_$table';
    final bool wasDirty = prefs.getBool(isDirtyKey) ?? true;
    final bool migratedVendedor = prefs.getBool('vendedor_cloud_migrated_v5_$tenantKey') ?? false;
    bool effectiveDirty = wasDirty;
    if (!migratedVendedor && (table == 'cotizaciones' || table == 'notas_entrega' || table == 'proformas')) {
      effectiveDirty = true;
      await prefs.setString(lastSyncKey, '1970-01-01 00:00:00');
      await prefs.setBool('vendedor_cloud_migrated_v5_$tenantKey', true);
    }

    try {
      final db = await DatabaseHelper.instance.database;
      final lastSync = prefs.getString(lastSyncKey) ?? '1970-01-01 00:00:00';

      // 1. Obtener registros locales y asegurar UUIDs en lote
      final List<Map<String, dynamic>> localData = [];
      if (effectiveDirty) {
        // Limpiamos el flag de dirty antes de consultar para evitar condiciones de carrera
        await prefs.setBool(isDirtyKey, false);

        final localDataRaw = await db.query(table);
        final localUuidBatch = db.batch();
        bool needsUuidUpdate = false;

        for (var row in localDataRaw) {
          final mutable = Map<String, dynamic>.from(row);
          String uuid = '';
          
          if (table == 'cotizaciones' || table == 'notas_entrega' || table == 'proformas') {
            uuid = mutable['uuid']?.toString() ?? '';
            if (uuid.isEmpty) {
              uuid = _generateUuid(table);
              mutable['uuid'] = uuid;
              localUuidBatch.update(table, {'uuid': uuid}, where: 'id = ?', whereArgs: [mutable['id']]);
              needsUuidUpdate = true;
            }
          } else {
            uuid = mutable['folderId']?.toString() ?? '';
            if (uuid.isEmpty) {
              uuid = _generateUuid(table);
              mutable['folderId'] = uuid;
              localUuidBatch.update(table, {'folderId': uuid}, where: 'id = ?', whereArgs: [mutable['id']]);
              needsUuidUpdate = true;
            }
          }
          
          // Mapear local a formato de servidor (cambiar folderId por uuid si corresponde)
          final remoteRecord = Map<String, dynamic>.from(mutable);
          if (table != 'cotizaciones' && table != 'notas_entrega' && table != 'proformas') {
            remoteRecord['uuid'] = uuid;
            remoteRecord.remove('folderId');
          }
          localData.add(remoteRecord);
        }

        if (needsUuidUpdate) {
          await localUuidBatch.commit(noResult: true);
        }

        if (table == 'articulos') {
          // Ejecutar migración automática de imágenes de Drive a Hostinger
          try {
            final drive = DriveService();
            if (drive.driveApi != null) {
              for (var i = 0; i < localData.length; i++) {
                final record = localData[i];
                final imageVal = record['imagen']?.toString() ?? '';
                final folderIdVal = record['uuid']?.toString() ?? '';
                final finalArtIdVal = record['finalArtId']?.toString() ?? '';
                
                if (imageVal.isEmpty && folderIdVal.isNotEmpty && finalArtIdVal.isNotEmpty) {
                  final bytes = await drive.getProductThumbnail(folderIdVal, finalArtIdVal);
                  if (bytes != null && bytes.isNotEmpty) {
                    final filename = await uploadImageToHostinger(bytes, '${folderIdVal}.jpg');
                    if (filename != null) {
                      record['imagen'] = filename;
                      final localId = await DatabaseHelper.instance.findMatchingLocalId('articulos', {'folderId': folderIdVal});
                      if (localId != null) {
                        await db.update('articulos', {'imagen': filename}, where: 'id = ?', whereArgs: [localId]);
                      }
                      debugPrint('Imagen de artículo $folderIdVal migrada con éxito a Hostinger: $filename');
                    }
                  }
                }
              }
            }
          } catch (migErr) {
            debugPrint('Error en migración automática de imágenes: $migErr');
          }
        }
      }

      // 2. Obtener borrados locales registrados
      final deletedRecords = await DatabaseHelper.instance.getDeletedRecords(table);
      final deletedUuids = deletedRecords.map((e) => e['uuid'].toString()).toList();
      final deletedNames = deletedRecords.map((e) => e['nombre']?.toString()).where((n) => n != null && n.isNotEmpty).cast<String>().toList();

      // 3. Enviar al servidor (codificado en Base64 para saltar bloqueos de ModSecurity)
      final token = prefs.getString('novaled_jwt_token') ?? '';
      final payload = jsonEncode({
        'table': table,
        'last_sync': lastSync,
        'records': localData,
        'deleted_uuids': deletedUuids,
        'deleted_names': deletedNames,
      });
      final base64Body = base64Encode(utf8.encode(payload));

      final response = await http.post(
        Uri.parse('https://novaledbolivia.com/sistema/api/sync.php'),
        headers: {
          'Content-Type': 'text/plain',
          'Authorization': 'Bearer $token',
          'X-Authorization': 'Bearer $token',
          'X-Content-Encoding': 'base64',
        },
        body: base64Body,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('Error sync table $table: ${response.statusCode}. Intentando re-autenticación silenciosa...');
        final reauthRes = await _autoReauthenticate();
        if (reauthRes == ReauthResult.success) {
          return await syncTable(table);
        } else if (reauthRes == ReauthResult.networkError) {
          throw Exception("Sin conexión a internet o señal de red móvil muy débil.");
        } else {
          await Session.forceLogout(
            message: "Su sesión ha expirado o las credenciales cambiaron. Por favor inicie sesión de nuevo."
          );
          throw Exception("Sesión expirada. Redirigiendo a inicio de sesión...");
        }
      }

      if (response.statusCode != 200) {
        debugPrint('Error sync table $table: ${response.statusCode} - ${response.body}');
        String serverErr = '';
        try {
          final errJson = jsonDecode(response.body);
          if (errJson is Map && errJson.containsKey('error')) {
            serverErr = ': ${errJson['error']}';
          }
        } catch (_) {}
        throw Exception("El servidor respondió con código ${response.statusCode}$serverErr. Intenta más tarde.");
      }

      final resJson = jsonDecode(response.body);
      if (resJson['success'] != true) {
        debugPrint('Error sync table $table: ${resJson['error']}');
        throw Exception(resJson['error']?.toString() ?? "Error desconocido en el servidor.");
      }

      final serverTime = resJson['server_time'] as String;
      final List<dynamic> remoteRecords = resJson['records'] ?? [];

      // 4. Mapear la base de datos local actual para búsquedas rápidas O(1)
      final currentLocalRows = await db.query(table);
      final Map<String, int> folderIdToId = {};
      final Map<String, int> nameToId = {};

      for (var row in currentLocalRows) {
        final int id = row['id'] as int;
        if (table == 'cotizaciones' || table == 'notas_entrega' || table == 'proformas') {
          final uuid = row['uuid']?.toString();
          if (uuid != null && uuid.isNotEmpty) {
            folderIdToId[uuid] = id;
          }
        } else {
          final folderId = row['folderId']?.toString();
          if (folderId != null && folderId.isNotEmpty) {
            folderIdToId[folderId] = id;
          }
        }

        if (table == 'clientes') {
          final name = row['nombreCompania']?.toString().trim().toLowerCase();
          if (name != null && name.isNotEmpty) nameToId[name] = id;
        } else if (table == 'tiendas' || table == 'articulos' || table == 'unidades_medida') {
          final name = row['nombre']?.toString().trim().toLowerCase();
          if (name != null && name.isNotEmpty) nameToId[name] = id;
        }
      }

      int? findMatchInMemory(Map<String, dynamic> item) {
        if (table == 'cotizaciones' || table == 'notas_entrega' || table == 'proformas') {
          final uuid = item['uuid']?.toString();
          if (uuid != null && uuid.isNotEmpty && folderIdToId.containsKey(uuid)) {
            return folderIdToId[uuid];
          }
        } else {
          final folderId = item['folderId']?.toString();
          if (folderId != null && folderId.isNotEmpty && folderIdToId.containsKey(folderId)) {
            return folderIdToId[folderId];
          }
        }

        if (table == 'clientes') {
          final name = item['nombreCompania']?.toString().trim().toLowerCase();
          if (name != null && name.isNotEmpty && nameToId.containsKey(name)) {
            return nameToId[name];
          }
        } else if (table == 'tiendas' || table == 'articulos' || table == 'unidades_medida') {
          final name = item['nombre']?.toString().trim().toLowerCase();
          if (name != null && name.isNotEmpty && nameToId.containsKey(name)) {
            return nameToId[name];
          }
        }
        return null;
      }

      // 5. Aplicar cambios remotos en base de datos local
      if (table == 'cotizaciones' || table == 'notas_entrega' || table == 'proformas') {
        for (var rawRemote in remoteRecords) {
          final remote = Map<String, dynamic>.from(rawRemote);
          final localRecord = Map<String, dynamic>.from(remote);
          
          localRecord.remove('last_modified');
          localRecord.remove('deleted');
          localRecord.remove('tenant_key');

          // Sanitización y conversión de tipos para evitar excepciones de mismatch en SQLite
          localRecord['subtotal'] = double.tryParse(localRecord['subtotal']?.toString() ?? '') ?? 0.0;
          localRecord['impuesto'] = double.tryParse(localRecord['impuesto']?.toString() ?? '') ?? 0.0;
          localRecord['descuento'] = double.tryParse(localRecord['descuento']?.toString() ?? '') ?? 0.0;
          localRecord['descuentoPorcentaje'] = double.tryParse(localRecord['descuentoPorcentaje']?.toString() ?? '') ?? 0.0;
          localRecord['total'] = double.tryParse(localRecord['total']?.toString() ?? '') ?? 0.0;
          localRecord['incluyeFirmaEmpresa'] = int.tryParse(localRecord['incluyeFirmaEmpresa']?.toString() ?? '') ?? 0;
          localRecord['incluyeFirmaCliente'] = int.tryParse(localRecord['incluyeFirmaCliente']?.toString() ?? '') ?? 0;
          localRecord['mostrarTerminos'] = int.tryParse(localRecord['mostrarTerminos']?.toString() ?? '') ?? 1;

          final isDeleted = (remote['deleted'] == 1 || remote['deleted'] == true);

          if (isDeleted) {
            final localId = findMatchInMemory(localRecord);
            if (localId != null) {
              await db.delete(table, where: 'id = ?', whereArgs: [localId]);
            }
          } else {
            // Sincronizar el registro respetando el ID de origen y resolviendo conflictos de ID
            await DatabaseHelper.instance.saveDocumentWithSyncedId(table, localRecord);
          }
        }
      } else {
        final remoteUpdateBatch = db.batch();
        for (var rawRemote in remoteRecords) {
          final remote = Map<String, dynamic>.from(rawRemote);
          final uuid = remote['uuid'].toString();
          
          // Mapear de formato de servidor a SQLite local
          final localRecord = Map<String, dynamic>.from(remote);
          localRecord['folderId'] = uuid;
          localRecord.remove('uuid');
          localRecord.remove('last_modified');
          localRecord.remove('deleted');
          localRecord.remove('tenant_key');

          if (table == 'articulos') {
            localRecord['precio'] = double.tryParse(localRecord['precio']?.toString() ?? '') ?? 0.0;
            localRecord['precioCaja'] = double.tryParse(localRecord['precioCaja']?.toString() ?? '') ?? 0.0;
          }

          final isDeleted = (remote['deleted'] == 1 || remote['deleted'] == true || remote['deleted'] == '1');
          final localId = findMatchInMemory(localRecord);

          if (isDeleted) {
            if (localId != null) {
              remoteUpdateBatch.delete(table, where: 'id = ?', whereArgs: [localId]);
            }
            if (table == 'unidades_medida' || table == 'tiendas' || table == 'articulos') {
              final n = localRecord['nombre']?.toString().trim();
              if (n != null && n.isNotEmpty) {
                remoteUpdateBatch.delete(table, where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [n.toLowerCase()]);
              }
            }
            if (table == 'clientes') {
              final n = localRecord['nombreCompania']?.toString().trim();
              if (n != null && n.isNotEmpty) {
                remoteUpdateBatch.delete(table, where: 'LOWER(TRIM(nombreCompania)) = ?', whereArgs: [n.toLowerCase()]);
              }
            }
          } else {
            if (localId != null) {
              localRecord['id'] = localId;
              remoteUpdateBatch.update(table, localRecord, where: 'id = ?', whereArgs: [localId]);
            } else {
              localRecord.remove('id');
              remoteUpdateBatch.insert(table, localRecord, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }
        await remoteUpdateBatch.commit(noResult: true);
      }

      final bool hasChanges = localData.isNotEmpty || remoteRecords.isNotEmpty || deletedUuids.isNotEmpty;
      if (table == 'articulos' && hasChanges) {
        DriveService().clearMemoryCaches();
      }

      // 6. Limpiar registros de borrados procesados con éxito
      if (deletedUuids.isNotEmpty) {
        await DatabaseHelper.instance.clearDeletedRecords(table, deletedUuids);
      }

      // 7. Guardar nueva marca de tiempo del servidor
      await prefs.setString(lastSyncKey, serverTime);
      return true;

    } catch (e) {
      if (wasDirty) {
        // Restaurar flag de dirty si falló la sincronización
        await prefs.setBool(isDirtyKey, true);
      }
      debugPrint('Exception sync table $table: $e');
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') || 
          errStr.contains('timeoutexception') || 
          errStr.contains('handshakeexception') ||
          errStr.contains('connection failed') ||
          errStr.contains('network is unreachable')) {
        throw Exception("Modo Offline: Sin conexión a internet");
      }
      rethrow;
    } finally {
      _activeSyncs[table] = false;
      if (_pendingSyncs[table] == true) {
        _pendingSyncs[table] = false;
        Future.microtask(() => syncTable(table).catchError((_) => false));
      }
    }
  }

  Future<String?> uploadImageToHostinger(Uint8List bytes, String originalName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var token = prefs.getString('novaled_jwt_token') ?? '';

      if (token.isEmpty) {
        await _autoReauthenticate();
        token = prefs.getString('novaled_jwt_token') ?? '';
      }

      final uri = Uri.parse('https://novaledbolivia.com/sistema/api/upload_image.php');
      var request = http.MultipartRequest('POST', uri);
      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: originalName,
        ),
      );
      
      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 401) {
        // Token vencido, re-autenticar y reintentar
        await _autoReauthenticate();
        token = prefs.getString('novaled_jwt_token') ?? '';
        request = http.MultipartRequest('POST', uri);
        if (token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            bytes,
            filename: originalName,
          ),
        );
        streamedResponse = await request.send().timeout(const Duration(seconds: 30));
        response = await http.Response.fromStream(streamedResponse);
      }

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        if (resJson['success'] == true) {
          return resJson['filename'] as String;
        }
      }
      debugPrint('Error uploading image to Hostinger: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Exception uploading image: $e');
      return null;
    }
  }

  Future<void> syncEverything() async {
    final tables = ['clientes', 'articulos', 'unidades_medida', 'tiendas', 'proveedores', 'cotizaciones', 'notas_entrega', 'proformas', 'sub_ubicaciones'];
    for (var table in tables) {
      await syncTable(table);
    }
  }

  Future<ReauthResult> _autoReauthenticate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = prefs.getString('saved_user') ?? '';
      final pass = prefs.getString('saved_pass') ?? '';
      if (user.isEmpty || pass.isEmpty) {
        return ReauthResult.noSavedCredentials;
      }

      var bytes = utf8.encode(pass);
      final hashedInput = sha256.convert(bytes).toString();

      final response = await http.post(
        Uri.parse('https://novaledbolivia.com/sistema/api/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': user.trim().toLowerCase(),
          'passwordHash': hashedInput,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        if (resJson['success'] == true) {
          final token = resJson['token'] as String?;
          if (token != null) {
            await prefs.setString('novaled_jwt_token', token);
            debugPrint("Re-autenticación silenciosa exitosa para usuario: $user");
            return ReauthResult.success;
          }
        }
      } else if (response.statusCode == 401) {
        debugPrint("Re-autenticación silenciosa falló: Credenciales inválidas.");
        return ReauthResult.invalidCredentials;
      }
      return ReauthResult.invalidCredentials;
    } catch (e) {
      debugPrint("Error en re-autenticación silenciosa: $e");
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') || 
          errStr.contains('timeoutexception') || 
          errStr.contains('handshakeexception') ||
          errStr.contains('connection failed') ||
          errStr.contains('network is unreachable')) {
        return ReauthResult.networkError;
      }
      return ReauthResult.invalidCredentials;
    }
  }
}
