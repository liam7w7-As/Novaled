import 'dart:convert';
import 'dart:io' show Platform, File;
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, print;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'product_model.dart';

import 'local_module/database_helper.dart';
import 'local_module/tenant_helper.dart';

// Extension to safely convert Map to mutable for Drive upload
extension MapMutableExtension on Map {
  Map<String, dynamic> toMutable() {
    return jsonDecode(jsonEncode(this)) as Map<String, dynamic>;
  }
}


class DriveService {
  static final DriveService _instance = DriveService._internal();
  factory DriveService() => _instance;

  static const _rootFolderId = "1_rV47JiauhIlZasrEeztXz5TUhWPCdXk";
  static const _cacheKey = "novaled_products_cache";
  
  // ID de cliente de aplicación de escritorio (Windows)
  final String _clientId = "589557753451-nmud759lvb6gm4froqfs25sbstsm0qhd.apps.googleusercontent.com";
  final String _clientSecret = "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"; 

  // ID de cliente de aplicación Web (debe ser de tipo "Aplicación web" en Google Cloud)
  final String _webClientId = "589557753451-qk8gr4dsbgsm48j68k80484bodk8a282.apps.googleusercontent.com";

  late final GoogleSignIn _googleSignIn;
  drive.DriveApi? _driveApi;
  http.Client? _httpClient; // Cliente autenticado principal
  AccessCredentials? _currentWindowsCreds; // Para manual headers en Windows
  Completer<void>? _authCompleter;
  String? lastError;
  GoogleSignIn get googleSignIn => _googleSignIn;
  drive.DriveApi? get driveApi => _driveApi;

  // Caché en memoria para actualizaciones instantáneas
  List<Product> _inMemoryProducts = [];
  List<Product> get inMemoryProducts => _inMemoryProducts;
  List<Product> _inMemoryPreProducts = [];
  List<Product> get inMemoryPreProducts => _inMemoryPreProducts;

  void clearMemoryCaches() {
    _inMemoryProducts.clear();
    _inMemoryPreProducts.clear();
    print('Caché en memoria de productos limpiada.');
  }

  void clearMemoryCache() {
    clearMemoryCaches();
  }

  final Map<String, Uint8List> _thumbnailCache = {};
  Map<String, Uint8List> get thumbnailCache => _thumbnailCache;

  // Registro de actualizaciones recientes para combatir la consistencia eventual de Drive
  final Map<String, DateTime> _recentlyUpdated = {};

  // Registro de eliminaciones recientes para combatir la consistencia eventual de Drive
  final Set<String> _recentlyDeleted = {};
  Set<String> get recentlyDeleted => _recentlyDeleted;

  DriveService._internal() {
    _googleSignIn = GoogleSignIn(
      clientId: kIsWeb ? _webClientId : null,
      serverClientId: null, // Desactivado en móvil para evitar ApiException 10, ya que obtenemos el token de acceso directamente
      scopes: [
        drive.DriveApi.driveFileScope,
        drive.DriveApi.driveScope,
      ],
    );
  }

  Future<void> _saveToLocalCache(List<Product> products) async {
    _inMemoryProducts = List.from(products); // Actualizar memoria
  }

  Future<List<Product>> getLocalCache() async {
    if (_inMemoryProducts.isNotEmpty) {
      return _inMemoryProducts;
    }
    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> rows = await db.query('articulos', orderBy: 'nombre ASC');
      final isNovaled = await TenantHelper.isActiveNovaled();
      
      final List<Product> list = [];
      for (var row in rows) {
        bool isCatalog = true; // Todos los artículos creados o existentes pertenecen al catálogo por defecto
        final stockJsonStr = row['stockJson']?.toString() ?? '';
        if (stockJsonStr.isNotEmpty) {
          try {
            final Map<String, dynamic> extra = jsonDecode(stockJsonStr);
            if (extra.containsKey('isCatalog')) {
              if (extra['isCatalog'] == false && isNovaled) {
                isCatalog = false;
              } else if (extra['isCatalog'] == true) {
                isCatalog = true;
              }
            }
          } catch (_) {}
        }
        
        if (!isCatalog) continue; // Solo si fue explícitamente pre-inventario

        final rawFolderId = row['folderId']?.toString() ?? '';
        final folderId = rawFolderId.isNotEmpty ? rawFolderId : 'art_${row['id']}';
        final finalArtId = row['finalArtId']?.toString() ?? '';
        final estado = finalArtId.isNotEmpty ? 'listo' : 'pendiente';

        Map<String, String> medidas = {};
        List<String> imageIds = [];
        List<String> camposModificados = [];
        int totalStock = 0;

        if (stockJsonStr.isNotEmpty) {
          try {
            final Map<String, dynamic> extra = jsonDecode(stockJsonStr);
            if (extra.containsKey('medidas') && extra['medidas'] is Map) {
              medidas = (extra['medidas'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
            }
            if (extra.containsKey('imageIds') && extra['imageIds'] is List) {
              imageIds = List<String>.from(extra['imageIds']);
            }
            if (extra.containsKey('camposModificados') && extra['camposModificados'] is List) {
              camposModificados = List<String>.from(extra['camposModificados']);
            }
            if (extra.containsKey('general')) {
              totalStock = int.tryParse(extra['general'].toString()) ?? 0;
            } else {
              extra.values.forEach((v) {
                if (v is Map) {
                  v.values.forEach((subV) => totalStock += (int.tryParse(subV.toString()) ?? 0));
                } else if (v is! bool) {
                  totalStock += (int.tryParse(v.toString()) ?? 0);
                }
              });
            }
          } catch (_) {}
        }

        list.add(Product(
          folderId: folderId,
          dataFileId: null,
          titulo: row['nombre']?.toString() ?? '',
          detalles: row['descripcion']?.toString() ?? '',
          precio: row['precio']?.toString() ?? '',
          estado: estado,
          medidas: medidas,
          familia: row['familia']?.toString() ?? '',
          subcategoria: row['subcategoria']?.toString() ?? '',
          codTienda: '',
          codCaja: row['codCaja']?.toString() ?? '',
          watts: '',
          marca: row['proveedor']?.toString() ?? '',
          finalArtId: finalArtId,
          infoDocId: null,
          verificadoPor: null,
          camposModificados: camposModificados,
          imageIds: imageIds,
          fecha: row['fecha']?.toString() ?? '',
          precioCaja: (row['precioCaja'] as num?)?.toDouble() ?? 0.0,
          cantidad: totalStock,
          unidad: row['unidad']?.toString() ?? 'Unidad',
          unidadDetalle: row['unidadDetalle']?.toString() ?? '',
        ));
      }

      _inMemoryProducts = List.from(list);
      return _inMemoryProducts;
    } catch (e) {
      print("Error leyendo SQLite articulos en getLocalCache: $e");
      return [];
    }
  }

  Future<List<Product>> getPreInventoryProducts() async {
    if (_inMemoryPreProducts.isNotEmpty) {
      return _inMemoryPreProducts;
    }
    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> rows = await db.query('articulos', orderBy: 'nombre ASC');
      
      final List<Product> list = [];
      for (var row in rows) {
        bool isCatalog = false;
        final stockJsonStr = row['stockJson']?.toString() ?? '';
        if (stockJsonStr.isNotEmpty) {
          try {
            final Map<String, dynamic> extra = jsonDecode(stockJsonStr);
            if (extra['isCatalog'] == true) {
              isCatalog = true;
            }
          } catch (_) {}
        }
        
        if (isCatalog) continue; // Saltar catálogo

        final folderId = row['folderId']?.toString() ?? '';
        final finalArtId = row['finalArtId']?.toString() ?? '';
        final estado = finalArtId.isNotEmpty ? 'listo' : 'pendiente';

        Map<String, String> medidas = {};
        List<String> imageIds = [];
        List<String> camposModificados = [];
        int totalStock = 0;

        if (stockJsonStr.isNotEmpty) {
          try {
            final Map<String, dynamic> extra = jsonDecode(stockJsonStr);
            if (extra.containsKey('medidas') && extra['medidas'] is Map) {
              medidas = (extra['medidas'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
            }
            if (extra.containsKey('imageIds') && extra['imageIds'] is List) {
              imageIds = List<String>.from(extra['imageIds']);
            }
            if (extra.containsKey('camposModificados') && extra['camposModificados'] is List) {
              camposModificados = List<String>.from(extra['camposModificados']);
            }
            if (extra.containsKey('general')) {
              totalStock = int.tryParse(extra['general'].toString()) ?? 0;
            } else {
              extra.values.forEach((v) {
                if (v is Map) {
                  v.values.forEach((subV) => totalStock += (int.tryParse(subV.toString()) ?? 0));
                } else if (v is! bool) {
                  totalStock += (int.tryParse(v.toString()) ?? 0);
                }
              });
            }
          } catch (_) {}
        }

        list.add(Product(
          folderId: folderId,
          dataFileId: null,
          titulo: row['nombre']?.toString() ?? '',
          detalles: row['descripcion']?.toString() ?? '',
          precio: row['precio']?.toString() ?? '',
          estado: estado,
          medidas: medidas,
          familia: row['familia']?.toString() ?? '',
          subcategoria: row['subcategoria']?.toString() ?? '',
          codTienda: '',
          codCaja: row['codCaja']?.toString() ?? '',
          watts: '',
          marca: row['proveedor']?.toString() ?? '',
          finalArtId: finalArtId,
          infoDocId: null,
          verificadoPor: null,
          camposModificados: camposModificados,
          imageIds: imageIds,
          fecha: row['fecha']?.toString() ?? '',
          precioCaja: (row['precioCaja'] as num?)?.toDouble() ?? 0.0,
          cantidad: totalStock,
          unidad: row['unidad']?.toString() ?? 'Unidad',
          unidadDetalle: row['unidadDetalle']?.toString() ?? '',
        ));
      }
      _inMemoryPreProducts = List.from(list);
      return _inMemoryPreProducts;
    } catch (e) {
      print("Error leyendo SQLite pre-inventario: $e");
      return [];
    }
  }

  Future<void> syncDriveCatalogToSQLite({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncStr = prefs.getString('last_drive_catalog_sync') ?? '';
      final now = DateTime.now();
      
      if (!force && lastSyncStr.isNotEmpty) {
        final lastSync = DateTime.parse(lastSyncStr);
        if (now.difference(lastSync).inMinutes < 5) {
          print("Drive catalog sync skipped (last sync was less than 5 minutes ago)");
          return;
        }
      }
      
      final authenticated = await authenticate();
      if (!authenticated || _driveApi == null) {
        print("Drive catalog sync skipped: not authenticated");
        return;
      }
      
      print("Starting Drive catalog sync...");
      
      // 1. List all active folders in Google Drive root
      final foldersRes = await _driveApi!.files.list(
        q: "'$_rootFolderId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false",
        $fields: "files(id, name, modifiedTime)",
        pageSize: 1000,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      final folders = foldersRes.files ?? [];
      if (folders.isEmpty) return;
      
      final db = await DatabaseHelper.instance.database;
      
      // 2. Fetch all data.json files in Drive (fast global search)
      final dataFilesRes = await _driveApi!.files.list(
        q: "name='data.json' and trashed=false",
        $fields: "files(id, name, parents, modifiedTime)",
        pageSize: 1000,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      final dataFiles = dataFilesRes.files ?? [];
      
      // Map parent ID to data.json file info
      final Map<String, drive.File> parentToDataFile = {};
      for (var f in dataFiles) {
        if (f.parents != null && f.parents!.isNotEmpty) {
          parentToDataFile[f.parents!.first] = f;
        }
      }
      
      final batch = db.batch();
      bool hasUpdates = false;
      
      for (var folder in folders) {
        final folderId = folder.id!;
        final folderName = folder.name!;
        
        // Find matching data.json
        final dataFile = parentToDataFile[folderId];
        if (dataFile == null) continue;
        
        // Check if we have this folderId in SQLite
        final List<Map<String, dynamic>> existing = await db.query(
          'articulos',
          where: 'folderId = ?',
          whereArgs: [folderId],
          limit: 1,
        );
        
        bool needDownload = false;
        Map<String, dynamic>? currentStockJson;
        
        if (existing.isEmpty) {
          needDownload = true;
        } else {
          final row = existing.first;
          final stockJsonStr = row['stockJson']?.toString() ?? '';
          if (stockJsonStr.isNotEmpty) {
            try {
              currentStockJson = jsonDecode(stockJsonStr);
            } catch (_) {}
          }
          currentStockJson ??= {};
          
          if (currentStockJson['isCatalog'] != true) {
            needDownload = true; // Necesita marcarse como catálogo y potencialmente actualizar
          }
          
          // Comparar fecha de modificación si está disponible
          final dbModTimeStr = currentStockJson['driveModifiedTime']?.toString() ?? '';
          final driveModTimeStr = dataFile.modifiedTime?.toIso8601String() ?? '';
          if (dbModTimeStr != driveModTimeStr) {
            needDownload = true;
          }
        }
        
        if (needDownload) {
          try {
            print("Downloading data.json for catalog product: $folderName");
            final response = await _driveApi!.files.get(dataFile.id!, downloadOptions: drive.DownloadOptions.fullMedia);
            if (response is drive.Media) {
              final List<int> bytes = [];
              await for (final chunk in response.stream) { bytes.addAll(chunk); }
              final jsonData = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
              
              final product = Product.fromJson(jsonData, folderId, dataFile.id!);
              if (product.fecha.isEmpty && dataFile.modifiedTime != null) {
                product.fecha = dataFile.modifiedTime!.toIso8601String();
              }
              
              // Preparar stockJson con isCatalog: true y metadatos
              final Map<String, dynamic> newStockJson = {
                'isCatalog': true,
                'driveModifiedTime': dataFile.modifiedTime?.toIso8601String(),
                'medidas': product.medidas,
                'imageIds': product.imageIds,
                'camposModificados': product.camposModificados,
                'general': product.cantidad,
              };
              
              final row = {
                'nombre': product.titulo,
                'precio': double.tryParse(product.precio) ?? 0.0,
                'precioCaja': product.precioCaja,
                'descripcion': product.detalles,
                'folderId': folderId,
                'finalArtId': product.finalArtId ?? '',
                'proveedor': product.marca,
                'codCaja': product.codCaja,
                'familia': product.familia,
                'subcategoria': product.subcategoria,
                'unidad': product.unidad,
                'unidadDetalle': product.unidadDetalle,
                'stockJson': jsonEncode(newStockJson),
                'fecha': product.fecha,
              };
              
              if (existing.isEmpty) {
                batch.insert('articulos', row);
              } else {
                batch.update('articulos', row, where: 'id = ?', whereArgs: [existing.first['id']]);
              }
              hasUpdates = true;
            }
          } catch (e) {
            print("Error downloading data.json for $folderName: $e");
          }
        } else {
          // Si ya está al día pero isCatalog no estaba explícitamente en true
          if (currentStockJson != null && currentStockJson['isCatalog'] != true) {
            currentStockJson['isCatalog'] = true;
            batch.update(
              'articulos',
              {'stockJson': jsonEncode(currentStockJson)},
              where: 'id = ?',
              whereArgs: [existing.first['id']],
            );
            hasUpdates = true;
          }
        }
      }
      
      if (hasUpdates) {
        await batch.commit(noResult: true);
        print("Drive catalog sync completed with updates.");
      } else {
        print("Drive catalog sync completed. No updates needed.");
      }
      
      await prefs.setString('last_drive_catalog_sync', now.toIso8601String());
    } catch (e) {
      print("Error in syncDriveCatalogToSQLite: $e");
    }
  }

  Future<bool> authenticate({bool forceSignIn = false}) async {
    if (_driveApi != null) return true;

    if (!forceSignIn && (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS)))) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final isConnected = prefs.getBool('google_drive_connected') ?? false;
        if (!isConnected) {
          lastError = "Google Drive no está conectado";
          return false;
        }
      } catch (e) {
        print("Error checking google_drive_connected flag: $e");
      }
    }
    
    // Si ya hay una autenticación en curso, esperar por ella
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      await _authCompleter!.future;
      return _driveApi != null;
    }

    _authCompleter = Completer<void>();
    try {
      if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
        GoogleSignInAccount? account;
        if (forceSignIn) {
          // Si es interactivo/forzado, llamamos a signIn de forma directa e inmediata para
          // evitar que el navegador móvil bloquee el popup (los awaits previos pierden el token de gesto del usuario).
          account = await _googleSignIn.signIn();
        } else {
          // Reutilizar el usuario actual si ya existe para evitar popups redundantes,
          // pero intentar signInSilently primero para asegurar el refresco de los tokens.
          try {
            account = await _googleSignIn.signInSilently();
          } catch (e) {
            print("Error de inicio silencioso Google: $e");
            lastError = "signInSilently error: $e";
          }
          account ??= _googleSignIn.currentUser;
        }
        
        if (account == null) {
          _authCompleter!.complete();
          lastError = "signIn cancelado/bloqueado por el navegador";
          return false;
        }

        // Verificar que tenga los scopes necesarios de Google Drive (autorización incremental)
        // En algunas plataformas y versiones del plugin, canAccessScopes() no está implementado y lanza UnimplementedError, por lo que lo envolvemos en un try-catch.
        if (!kIsWeb) {
          final List<String> requiredScopes = [
            drive.DriveApi.driveFileScope,
            drive.DriveApi.driveScope,
          ];
          try {
            final bool hasScopes = await _googleSignIn.canAccessScopes(requiredScopes);
            if (!hasScopes) {
              if (forceSignIn) {
                final bool granted = await _googleSignIn.requestScopes(requiredScopes);
                if (!granted) {
                  _authCompleter!.complete();
                  lastError = "Scopes denegados por el usuario";
                  return false;
                }
              } else {
                _authCompleter!.complete();
                lastError = "Scopes faltantes. Requiere forceSignIn";
                return false;
              }
            }
          } catch (e) {
            print("canAccessScopes no está implementado o soportado en esta plataforma: $e");
          }
        }
        
        final client = await _googleSignIn.authenticatedClient();
        if (client == null) {
          _authCompleter!.complete();
          lastError = "authenticatedClient retornó null";
          // Limpiar la sesión corrupta/vencida para evitar que se quede atascado y obligar a borrar cookies
          await signOut();
          return false;
        }
        _httpClient = client;
        _driveApi = drive.DriveApi(client);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('google_drive_connected', true);
        } catch (_) {}
        _authCompleter!.complete();
        return true;
      } else {
        // --- LÓGICA DE PERSISTENCIA PARA WINDOWS ---
        final id = ClientId(_clientId, _clientSecret);
        final scopes = [drive.DriveApi.driveFileScope, drive.DriveApi.driveScope];
        
        // 1. Intentar cargar credenciales guardadas
        AccessCredentials? savedCreds = await _loadStoredCredentials();
        
        if (savedCreds != null) {
          _currentWindowsCreds = savedCreds;
          // Crear un cliente que se auto-refresca
          final client = autoRefreshingClient(id, savedCreds, http.Client());
          _httpClient = client;
          _driveApi = drive.DriveApi(client);
          _authCompleter!.complete();
          return true;
        }

        // Si no hay credenciales guardadas y forceSignIn es false, no abrir el navegador
        if (!forceSignIn) {
          _authCompleter!.complete();
          lastError = "Windows credentials not found";
          return false;
        }

        // 2. Si no hay, pedir consentimiento (abre navegador)
        final client = await clientViaUserConsent(id, scopes, (url) async {
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          }
        });
        
        _currentWindowsCreds = client.credentials;
        // 3. Guardar las nuevas credenciales para la próxima vez
        await _saveCredentials(client.credentials);
        
        _httpClient = client;
        _driveApi = drive.DriveApi(client);
        _authCompleter!.complete();
        return true;
      }
    } catch (e) {
      print("Error de autenticación Novaled: $e");
      lastError = "Exception en authenticate: $e";
      if (_authCompleter != null && !_authCompleter!.isCompleted) {
        _authCompleter!.complete();
      }
      return false;
    }
  }

  Future<AccessCredentials?> _loadStoredCredentials() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/auth_tokens.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        return AccessCredentials(
          AccessToken(data['type'], data['data'], DateTime.parse(data['expiry'])),
          data['refreshToken'],
          List<String>.from(data['scopes']),
        );
      }
    } catch (e) { print("Error cargando tokens: $e"); }
    return null;
  }

  Future<void> _saveCredentials(AccessCredentials creds) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/auth_tokens.json');
      final data = {
        'type': creds.accessToken.type,
        'data': creds.accessToken.data,
        'expiry': creds.accessToken.expiry.toIso8601String(),
        'refreshToken': creds.refreshToken,
        'scopes': creds.scopes,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) { print("Error guardando tokens: $e"); }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    if (!kIsWeb && Platform.isWindows) {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/auth_tokens.json');
      if (await file.exists()) await file.delete();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('google_drive_connected', false);
    } catch (_) {}
    _driveApi = null;
    _httpClient = null;
    _currentWindowsCreds = null;
    _authCompleter = null;
  }

  Future<Map<String, String>> _getManualAuthHeaders() async {
    try {
      if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
        return (await _googleSignIn.currentUser?.authHeaders) ?? {};
      } else if (_currentWindowsCreds != null) {
        return {
          'Authorization': '${_currentWindowsCreds!.accessToken.type} ${_currentWindowsCreds!.accessToken.data}'
        };
      }
    } catch (e) {
      print("Error obteniendo headers manuales: $e");
    }
    return {};
  }

  Future<List<Product>> getAllProducts() async {
    return await getLocalCache();
  }

  Future<Map<String, List<String>>> getConfig() async {
    await authenticate();
    if (_driveApi == null) return {};
    try {
      final res = await _driveApi!.files.list(
        q: "'$_rootFolderId' in parents and name='config.json' and trashed=false",
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      if (res.files == null || res.files!.isEmpty) return {};
      final response = await _driveApi!.files.get(res.files!.first.id!, downloadOptions: drive.DownloadOptions.fullMedia);
      if (response is drive.Media) {
        final List<int> bytes = [];
        await for (final chunk in response.stream) { bytes.addAll(chunk); }
        final Map<String, dynamic> json = jsonDecode(utf8.decode(bytes));
        return json.map((key, value) => MapEntry(key, List<String>.from(value)));
      }
    } catch (e) { print("Error config: $e"); }
    return {};
  }

  Future<void> saveConfig(Map<String, List<String>> config) async {
    await authenticate();
    if (_driveApi == null) return;
    try {
      final res = await _driveApi!.files.list(
        q: "'$_rootFolderId' in parents and name='config.json' and trashed=false",
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      final jsonContent = utf8.encode(jsonEncode(config));
      final media = drive.Media(Stream.fromIterable([jsonContent]), jsonContent.length, contentType: 'application/json');
      final meta = drive.File(name: 'config.json', mimeType: 'application/json');
      if (res.files != null && res.files!.isNotEmpty) {
        await _driveApi!.files.update(meta, res.files!.first.id!, uploadMedia: media);
      } else {
        meta.parents = [_rootFolderId];
        await _driveApi!.files.create(meta, uploadMedia: media);
      }
    } catch (e) { print("Error saveConfig: $e"); }
  }

  Future<List<Map<String, dynamic>>> loadUsers() async {
    await authenticate();
    if (_driveApi == null) return [];
    try {
      final dbRootId = await _getOrCreateFolder("NOVALED-BASE-DE-DATOS", _rootFolderId);
      final res = await _driveApi!.files.list(
        q: "'$dbRootId' in parents and name='users.json' and trashed=false",
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      if (res.files == null || res.files!.isEmpty) {
        // Inicializar con los usuarios por defecto si no existe el archivo en la nube
        final defaultList = [
          {"username": "Almir", "passwordHash": "8705589bfb1e156ce82ffa2cbc9a2199faf7ca38287bc2a9902f9183e017611a", "role": "developer", "createdAt": DateTime.now().toIso8601String()},
          {"username": "Joel", "passwordHash": "60a17bff3ae55cd213357b7ee72e29526cc8b0403f1a9a6139f8a5a501b50b3c", "role": "developer", "createdAt": DateTime.now().toIso8601String()},
          {"username": "Victor", "passwordHash": "89dc8dae72704d08ec537e9ad97145ac915225b7509dade9bdc5a701daa66aaf", "role": "designer", "createdAt": DateTime.now().toIso8601String()},
          {"username": "Gustavo", "passwordHash": "4cb84e8f8162613a30347c28c1f2c4e1a3bcb81edef09d70524c7d59a00a96bf", "role": "seller", "createdAt": DateTime.now().toIso8601String()},
          {"username": "Dani", "passwordHash": "6cd3e30b0df83c623fb6a602a34979d0f1a1d438efd43c0cf98157b599a7b4c9", "role": "seller", "createdAt": DateTime.now().toIso8601String()}
        ];
        await saveUsers(defaultList);
        return defaultList;
      }
      final response = await _driveApi!.files.get(res.files!.first.id!, downloadOptions: drive.DownloadOptions.fullMedia);
      if (response is drive.Media) {
        final List<int> bytes = [];
        await for (final chunk in response.stream) { bytes.addAll(chunk); }
        final List<dynamic> jsonList = jsonDecode(utf8.decode(bytes));
        final list = List<Map<String, dynamic>>.from(jsonList);

        // MIGRACIÓN: Si el archivo ya existía pero no contiene al usuario 'almir',
        // significa que es una base de datos antigua que no tenía los usuarios por defecto.
        // Los agregamos y guardamos en la nube.
        final hasAlmir = list.any((u) => u['username']?.toString().toLowerCase().trim() == 'almir');
        if (!hasAlmir) {
          final defaultList = [
            {"username": "Almir", "passwordHash": "8705589bfb1e156ce82ffa2cbc9a2199faf7ca38287bc2a9902f9183e017611a", "role": "developer", "createdAt": DateTime.now().toIso8601String()},
            {"username": "Joel", "passwordHash": "60a17bff3ae55cd213357b7ee72e29526cc8b0403f1a9a6139f8a5a501b50b3c", "role": "developer", "createdAt": DateTime.now().toIso8601String()},
            {"username": "Victor", "passwordHash": "89dc8dae72704d08ec537e9ad97145ac915225b7509dade9bdc5a701daa66aaf", "role": "designer", "createdAt": DateTime.now().toIso8601String()},
            {"username": "Gustavo", "passwordHash": "4cb84e8f8162613a30347c28c1f2c4e1a3bcb81edef09d70524c7d59a00a96bf", "role": "seller", "createdAt": DateTime.now().toIso8601String()},
            {"username": "Dani", "passwordHash": "6cd3e30b0df83c623fb6a602a34979d0f1a1d438efd43c0cf98157b599a7b4c9", "role": "seller", "createdAt": DateTime.now().toIso8601String()}
          ];
          for (var defUser in defaultList) {
            final exists = list.any((u) => u['username']?.toString().toLowerCase().trim() == defUser['username']);
            if (!exists) {
              list.add(defUser);
            }
          }
          await saveUsers(list);
        }
        return list;
      }
    } catch (e) { 
      print("Error cargando usuarios: $e"); 
    }
    return [];
  }

  Future<void> saveUsers(List<Map<String, dynamic>> users) async {
    await authenticate();
    if (_driveApi == null) return;
    try {
      final dbRootId = await _getOrCreateFolder("NOVALED-BASE-DE-DATOS", _rootFolderId);
      final res = await _driveApi!.files.list(
        q: "'$dbRootId' in parents and name='users.json' and trashed=false",
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      final jsonContent = utf8.encode(jsonEncode(users));
      final media = drive.Media(Stream.fromIterable([jsonContent]), jsonContent.length, contentType: 'application/json');
      final meta = drive.File(name: 'users.json', mimeType: 'application/json');
      if (res.files != null && res.files!.isNotEmpty) {
        await _driveApi!.files.update(meta, res.files!.first.id!, uploadMedia: media);
      } else {
        meta.parents = [dbRootId];
        await _driveApi!.files.create(meta, uploadMedia: media);
      }
    } catch (e) { 
      print("Error guardando usuarios: $e"); 
    }
  }

  // --- MÉTODOS DE SINCRONIZACIÓN POR CARPETAS INDIVIDUALES ---

  Future<String?> _getFolderIdForTable(String tableName) async {
    try {
      final dbRootId = await _getOrCreateFolder("NOVALED-BASE-DE-DATOS", _rootFolderId);
      return await _getOrCreateFolder(tableName.toUpperCase(), dbRootId);
    } catch (e) {
      print("Error obteniendo carpeta para tabla $tableName: $e");
      return null;
    }
  }

  Future<String?> _findFileInFolder(String folderId, String fileName) async {
    try {
      final escapedName = fileName.replaceAll("'", "\\'");
      final res = await _driveApi!.files.list(
        q: "'$folderId' in parents and name='$escapedName' and trashed=false",
        pageSize: 1,
        $fields: "files(id)",
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      if (res.files != null && res.files!.isNotEmpty) {
        return res.files!.first.id;
      }
    } catch (e) {
      print("Error buscando $fileName en $folderId: $e");
    }
    return null;
  }

  Future<void> _ensureProductFolder(Product product) async {
    if (product.folderId != null && product.folderId!.isNotEmpty) {
      try {
        await _driveApi!.files.get(product.folderId!, $fields: 'id');
        return;
      } catch (e) {
        if (!(e.toString().contains('404') || (e is drive.DetailedApiRequestError && e.status == 404))) {
          rethrow;
        }
      }
    }
    final folder = await _driveApi!.files.create(
      drive.File(name: product.titulo, parents: [_rootFolderId], mimeType: 'application/vnd.google-apps.folder'),
      $fields: 'id'
    );
    product.folderId = folder.id;
    product.dataFileId = null;
    product.infoDocId = null;
  }

  Future<String?> syncItemToDrive(String table, Map<String, dynamic> item, {List<XFile>? files}) async {
    await authenticate();
    if (_driveApi == null) return null;

    try {
      final moduleFolderId = await _getFolderIdForTable(table);
      if (moduleFolderId == null) return null;

      String? folderId = item['folderId'];
      String itemName = _getItemName(table, item);

      // Si tiene folderId, verificar que exista y no esté en la papelera
      if (folderId != null && folderId.isNotEmpty) {
        try {
          final f = await _driveApi!.files.get(folderId, $fields: 'id, trashed') as drive.File;
          if (f.trashed == true) {
            return "DELETED_ON_DRIVE";
          }
        } catch (e) {
          // Manejo robusto de 404 para carpetas eliminadas manualmente en Drive
          if (e.toString().contains('404') || (e is drive.DetailedApiRequestError && e.status == 404)) {
            return "DELETED_ON_DRIVE";
          } else {
            rethrow;
          }
        }
      }

      try {
        // Crear carpeta si no existe o fue eliminada
        if (folderId == null || folderId.isEmpty) {
          final existingFolderId = await _findFileInFolder(moduleFolderId, itemName);
          if (existingFolderId != null) {
            folderId = existingFolderId;
          } else {
            final folder = await _driveApi!.files.create(
              drive.File(
                name: itemName,
                parents: [moduleFolderId],
                mimeType: 'application/vnd.google-apps.folder',
              ),
              $fields: 'id',
            );
            folderId = folder.id;
          }
        } else {
          // Actualizar nombre por si cambió el dato principal (nombre o compañía)
          // Excepto para documentos de venta (cotizaciones, notas de entrega, proformas)
          // para evitar bucles de renombrado infinito por diferencias de IDs autoincrementales locales.
          if (table != 'cotizaciones' && table != 'notas_entrega' && table != 'proformas') {
            await _driveApi!.files.update(drive.File(name: itemName), folderId);
          }
        }

        if (folderId == null) return null;

        // Subir archivos adjuntos si los hay (Documentos/Imágenes)
        if (files != null && files.isNotEmpty) {
          for (var file in files) {
            try {
              final bytes = await file.readAsBytes();
              final media = drive.Media(Stream.fromIterable([bytes]), bytes.length);
              final driveFile = drive.File(
                name: file.name,
                parents: [folderId],
              );
              await _driveApi!.files.create(driveFile, uploadMedia: media);
            } catch (e) {
              print("Error subiendo archivo adjunto ${file.name}: $e");
            }
          }
        }

        // Subir o actualizar data.json con toda la información del registro
        final mutableItem = Map<String, dynamic>.from(item);
        mutableItem['folderId'] = folderId;
        // Para documentos comerciales (cotizaciones, notas_entrega, proformas), conservamos el ID para sincronizar el número de documento.
        // Para otras tablas (clientes, tiendas, articulos), removemos el ID para evitar colisiones indeseadas y usar matching local.
        if (table != 'cotizaciones' && table != 'notas_entrega' && table != 'proformas') {
          mutableItem.remove('id');
        }
        
        final jsonContent = utf8.encode(jsonEncode(mutableItem));
        final media = drive.Media(Stream.fromIterable([jsonContent]), jsonContent.length, contentType: 'application/json');
        
        final res = await _driveApi!.files.list(
          q: "'$folderId' in parents and name='data.json' and trashed=false",
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
        );
        if (res.files != null && res.files!.isNotEmpty) {
          await _driveApi!.files.update(drive.File(name: 'data.json'), res.files!.first.id!, uploadMedia: media);
        } else {
          await _driveApi!.files.create(
            drive.File(name: 'data.json', parents: [folderId], mimeType: 'application/json'),
            uploadMedia: media,
          );
        }
        return folderId;
      } catch (e) {
        // Si hay un error 404 durante cualquiera de las llamadas secundarias, la carpeta no es válida
        if (e.toString().contains('404') || (e is drive.DetailedApiRequestError && e.status == 404)) {
          print("FolderId $folderId inválido/borrado detectado durante la subida (404). Reintentando con nueva carpeta...");
          final newItem = Map<String, dynamic>.from(item)..['folderId'] = null;
          return syncItemToDrive(table, newItem, files: files);
        } else {
          rethrow;
        }
      }
    } catch (e) {
      // Manejo de expiración de sesión (401)
      if (e.toString().contains('401') || e.toString().contains('invalid_token')) {
        _driveApi = null;
        if (await authenticate()) {
          return syncItemToDrive(table, item, files: files);
        }
      }
      print("Error syncItemToDrive ($table): $e");
      return null;
    }
  }

  String _getItemName(String table, Map<String, dynamic> item) {
    if (table == 'articulos') return item['nombre'] ?? 'Sin nombre';
    if (table == 'clientes') return item['nombreCompania'] ?? 'Sin nombre';
    if (table == 'proveedores') return item['nombre'] ?? 'Sin nombre';
    if (table == 'tiendas') return item['nombre'] ?? 'Sin nombre';
    if (table == 'unidades_medida') return item['nombre'] ?? 'Sin nombre';
    
    final uuid = item['uuid'];
    if (uuid != null && uuid.toString().isNotEmpty) {
      return "${table.toUpperCase()}_${uuid}_${item['fecha'] ?? ''}";
    }
    return "${table.toUpperCase()}_${item['id']}_${item['fecha'] ?? ''}";
  }
  Future<List<Map<String, dynamic>>> downloadAllFromTable(String table) async {
    await authenticate();
    if (_driveApi == null) return [];

    try {
      final moduleFolderId = await _getFolderIdForTable(table);
      if (moduleFolderId == null) return [];

      // 0. INTENTAR PRIMERO DESCARGAR EL index.json EN UN SOLO PASO (Optimizador de velocidad y rate-limiting)
      try {
        final indexRes = await _driveApi!.files.list(
          q: "'$moduleFolderId' in parents and name='index.json' and trashed=false",
          $fields: "files(id, name)",
          pageSize: 1,
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
        );
        if (indexRes.files != null && indexRes.files!.isNotEmpty) {
          final fileId = indexRes.files!.first.id!;
          final response = await _driveApi!.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia)
              .timeout(const Duration(seconds: 15));
          if (response is drive.Media) {
            final List<int> dataBytes = [];
            await for (final chunk in response.stream) { dataBytes.addAll(chunk); }
            final List<dynamic> jsonList = jsonDecode(utf8.decode(dataBytes));
            print("Carga rápida exitosa: ${jsonList.length} artículos leídos de index.json para tabla $table.");
            return jsonList.cast<Map<String, dynamic>>();
          }
        }
      } catch (e) {
        print("Error en carga rápida de index.json (se usará carga clásica): $e");
      }

      // 1. Obtener carpetas secundarias con paginación y timeout
      final List<drive.File> folders = [];
      String? pageToken;
      do {
        final res = await _driveApi!.files.list(
          q: "'$moduleFolderId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false",
          $fields: "nextPageToken, files(id, name)",
          pageSize: 1000,
          pageToken: pageToken,
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
        ).timeout(const Duration(seconds: 15));
        
        if (res.files != null) {
          folders.addAll(res.files!);
        }
        pageToken = res.nextPageToken;
      } while (pageToken != null);

      if (folders.isEmpty) return [];

      final Map<String, String> folderMap = {
        for (var f in folders)
          if (!_recentlyDeleted.contains(f.id!))
            f.id!: f.name!
      };

      final List<Map<String, dynamic>> results = [];
      final List<Future<void> Function()> downloadTasks = [];

      for (final folder in folders) {
        if (_recentlyDeleted.contains(folder.id!)) continue;
        final String parentId = folder.id!;

        downloadTasks.add(() async {
          try {
            // Consulta directa del archivo data.json dentro de esta carpeta (robusta para carpetas compartidas)
            final res = await _driveApi!.files.list(
              q: "name='data.json' and '$parentId' in parents and trashed=false",
              $fields: "files(id, name)",
              pageSize: 1,
              supportsAllDrives: true,
              includeItemsFromAllDrives: true,
            ).timeout(const Duration(seconds: 10));
            
            final files = res.files ?? [];
            if (files.isNotEmpty) {
              final fileId = files.first.id!;
              final response = await _driveApi!.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia)
                  .timeout(const Duration(seconds: 8));
              if (response is drive.Media) {
                final List<int> dataBytes = [];
                await for (final chunk in response.stream) { dataBytes.addAll(chunk); }
                final Map<String, dynamic> item = jsonDecode(utf8.decode(dataBytes));
                item['folderId'] = parentId;
                results.add(item);
              }
            }
          } catch (e) {
            print("Error descargando data.json de ${folder.name}: $e");
          }
        });
      }

      // Procesar en paralelo con límite de concurrencia de 5 para evitar 403 Rate Limit
      const int concurrencyLimit = 5;
      int activeCount = 0;
      int completedCount = 0;
      final Completer<void> completer = Completer<void>();

      void runNext() {
        if (completedCount == downloadTasks.length) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        while (activeCount < concurrencyLimit && completedCount + activeCount < downloadTasks.length) {
          final currentTaskIndex = completedCount + activeCount;
          activeCount++;
          downloadTasks[currentTaskIndex]().then((_) {
            activeCount--;
            completedCount++;
            runNext();
          }).catchError((e) {
            activeCount--;
            completedCount++;
            runNext();
          });
        }
      }

      if (downloadTasks.isNotEmpty) {
        runNext();
        await completer.future;
      }

      return results;
    } catch (e) {
      print("Error downloadAllFromTable ($table): $e");
      if (e.toString().contains('401') || e.toString().contains('403') || e.toString().contains('invalid_token') || e.toString().contains('permission')) {
        _driveApi = null;
      }
      return [];
    }
  }
  // --- MÉTODOS DE SINCRONIZACIÓN COMERCIAL ---

  Future<void> uploadCommercialData(Map<String, dynamic> data) async {
    await authenticate();
    if (_driveApi == null) return;
    try {
      final res = await _driveApi!.files.list(q: "'$_rootFolderId' in parents and name='commercial_data.json' and trashed=false");
      final jsonContent = utf8.encode(jsonEncode(data));
      final media = drive.Media(Stream.fromIterable([jsonContent]), jsonContent.length, contentType: 'application/json');
      final meta = drive.File(name: 'commercial_data.json', mimeType: 'application/json');

      if (res.files != null && res.files!.isNotEmpty) {
        await _driveApi!.files.update(meta, res.files!.first.id!, uploadMedia: media);
        print("Datos comerciales actualizados en Drive");
      } else {
        meta.parents = [_rootFolderId];
        await _driveApi!.files.create(meta, uploadMedia: media);
        print("Datos comerciales creados en Drive");
      }
    } catch (e) {
      print("Error al subir datos comerciales: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> downloadCommercialData() async {
    await authenticate();
    if (_driveApi == null) return null;
    try {
      final res = await _driveApi!.files.list(q: "'$_rootFolderId' in parents and name='commercial_data.json' and trashed=false");
      if (res.files == null || res.files!.isEmpty) return null;

      final response = await _driveApi!.files.get(res.files!.first.id!, downloadOptions: drive.DownloadOptions.fullMedia);
      if (response is drive.Media) {
        final List<int> bytes = [];
        await for (final chunk in response.stream) { bytes.addAll(chunk); }
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      }
    } catch (e) {
      print("Error al descargar datos comerciales: $e");
    }
    return null;
  }

  Future<List<String>> getProductImages(String folderId) async {
    await authenticate();
    if (_driveApi == null) return [];
    try {
      final res = await _driveApi!.files.list(
        q: "'$folderId' in parents and trashed=false",
        $fields: "files(id, name, mimeType)",
        orderBy: 'createdTime',
      );
      
      final images = res.files?.where((f) {
        final mime = f.mimeType?.toLowerCase() ?? "";
        final name = f.name?.toLowerCase() ?? "";
        return mime.startsWith("image/") || 
               name.endsWith(".jpg") || 
               name.endsWith(".jpeg") || 
               name.endsWith(".png") || 
               name.endsWith(".webp");
      }).map((f) => f.id!).toList();

      return images ?? [];
    } catch (e) {
      print("Error obteniendo imágenes de carpeta $folderId: $e");
      return [];
    }
  }

  Future<Uint8List?> getFileThumbnail(String fileId) async {
    if (_thumbnailCache.containsKey(fileId)) return _thumbnailCache[fileId];
    
    await authenticate();
    if (_driveApi == null) return null;
    
    // Cliente temporal cerrado inmediatamente para evitar "Unexpected response"
    final tempClient = http.Client();
    try {
      await Future.delayed(Duration(milliseconds: 10 + (fileId.hashCode % 150)));

      final fileMeta = await _driveApi!.files.get(fileId, $fields: "thumbnailLink") as drive.File;
      if (fileMeta.thumbnailLink != null) {
        final headers = await _getManualAuthHeaders();
        final thumbRes = await tempClient.get(Uri.parse(fileMeta.thumbnailLink!), headers: headers).timeout(const Duration(seconds: 10));
        
        if (thumbRes.statusCode == 200) {
          _thumbnailCache[fileId] = thumbRes.bodyBytes;
          return thumbRes.bodyBytes;
        }
      }
    } catch (e) {
      print("Error obteniendo miniatura para $fileId: $e");
    } finally {
      tempClient.close();
    }
    return null;
  }

  Future<List<int>> getFileBytes(String fileId) async {
    await authenticate();
    if (_driveApi == null) return [];
    final response = await _driveApi!.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia);
    if (response is drive.Media) {
      final List<int> bytes = [];
      await for (final chunk in response.stream) { bytes.addAll(chunk); }
      return bytes;
    }
    return [];
  }

  Future<void> createProduct(Product product, List<XFile> images) async {
    if (_driveApi == null) throw Exception("No autenticado");
    
    final folder = await _driveApi!.files.create(
      drive.File(name: product.titulo, parents: [_rootFolderId], mimeType: 'application/vnd.google-apps.folder'),
      $fields: 'id'
    );
    product.folderId = folder.id;

    final List<String> uploadedIds = [];
    for (var img in images) {
      final bytes = await img.readAsBytes();
      final ext = img.name.split('.').last.toLowerCase();
      String mime = 'image/jpeg';
      if (ext == 'png') mime = 'image/png';
      if (ext == 'webp') mime = 'image/webp';

      final file = await _driveApi!.files.create(
        drive.File(
          name: img.name, 
          parents: [product.folderId!],
          mimeType: mime,
        ),
        uploadMedia: drive.Media(Stream.fromIterable([bytes]), bytes.length, contentType: mime)
      );
      if (file.id != null) uploadedIds.add(file.id!);
    }
    product.imageIds = uploadedIds;
    
    try {
      final docContent = _generateDocContent(product);
      final htmlBytes = utf8.encode(docContent);
      final docFile = await _driveApi!.files.create(
        drive.File(name: product.titulo, parents: [product.folderId!], mimeType: 'application/vnd.google-apps.document'),
        uploadMedia: drive.Media(Stream.fromIterable([htmlBytes]), htmlBytes.length, contentType: 'text/html')
      );
      product.infoDocId = docFile.id;
    } catch (e) { print("Error creando doc: $e"); }

    final jsonContent = utf8.encode(jsonEncode(product.toJson()));
    final dataFile = await _driveApi!.files.create(
      drive.File(name: 'data.json', parents: [product.folderId!], mimeType: 'application/json'),
      uploadMedia: drive.Media(Stream.fromIterable([jsonContent]), jsonContent.length, contentType: 'application/json')
    );
    product.dataFileId = dataFile.id;
  }

  String _generateDocContent(Product product) {
    StringBuffer buffer = StringBuffer();
    buffer.write('<html><body style="font-family: Arial; padding: 20px; background-color: #ffffff; color: #000;">');

    // Categoría
    String catStr = "";
    if (product.familia.trim().isNotEmpty) catStr = product.familia;
    if (product.subcategoria.trim().isNotEmpty) {
      if (catStr.isNotEmpty) catStr += " / ";
      catStr += product.subcategoria;
    }
    if (catStr.isNotEmpty) {
      buffer.write('<p style="margin: 0; font-size: 14px;"><b>categoría:</b> $catStr</p>');
    }

    // Título
    buffer.write('<h1 style="margin: 15px 0 10px 0; font-size: 32px; font-weight: bold;">${product.titulo.toUpperCase()}</h1>');

    // Especificaciones Técnica (Todo en Mayúsculas)
    if (product.detalles.trim().isNotEmpty) {
      buffer.write('<p style="margin: 8px 0; font-size: 14px;"><b>ESPECIFICACIONES TÉCNICA:</b> ${product.detalles}</p>');
    }

    // Watts
    if (product.watts.trim().isNotEmpty) {
      buffer.write('<p style="margin: 4px 0; font-size: 14px;"><b>watts:</b> ${product.watts}</p>');
    }

    // Marca
    if (product.marca.trim().isNotEmpty) {
      buffer.write('<p style="margin: 4px 0; font-size: 14px;">${product.marca}</p>');
    }

    // Medidas (Etiquetas y encabezado en minúscula)
    List<String> validMeds = [];
    product.medidas.forEach((key, value) {
      final numericPart = value.split(' ').first.trim();
      if (numericPart.isNotEmpty) {
        validMeds.add("<b>${key.toLowerCase()}</b> $value");
      }
    });
    if (validMeds.isNotEmpty) {
      buffer.write('<p style="margin: 8px 0; font-size: 14px;"><b>medidas:</b> ${validMeds.join("   ")}</p>');
    }

    // Precio (Muestra el valor real y elimina la etiqueta "precio:")
    if (product.precio.trim().isNotEmpty) {
      buffer.write('<p style="margin: 8px 0; font-size: 14px;">Bs. ${product.precio}</p>');
    }

    // Tienda
    if (product.codTienda.trim().isNotEmpty) {
      buffer.write('<p style="margin: 8px 0; font-size: 14px;"><b>tienda:</b> ${product.codTienda}</p>');
    }

    // Caja
    if (product.codCaja.trim().isNotEmpty) {
      buffer.write('<p style="margin: 8px 0; font-size: 14px;"><b>caja:</b> ${product.codCaja}</p>');
    }

    buffer.write('</body></html>');
    return buffer.toString();
  }

  Future<String> _getOrCreateFolder(String name, String parentId) async {
    // 1. Buscar con el nombre exacto
    var res = await _driveApi!.files.list(
      q: "'$parentId' in parents and name='$name' and mimeType='application/vnd.google-apps.folder' and trashed=false",
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    );
    if (res.files != null && res.files!.isNotEmpty) return res.files!.first.id!;
    
    // 2. Buscar variaciones con espacios si contiene guiones o guiones bajos
    if (name.contains('-') || name.contains('_')) {
      final nameWithSpaces = name.replaceAll('-', ' ').replaceAll('_', ' ');
      res = await _driveApi!.files.list(
        q: "'$parentId' in parents and name='$nameWithSpaces' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      if (res.files != null && res.files!.isNotEmpty) return res.files!.first.id!;
      
      final nameWithHyphens = name.replaceAll('_', '-');
      res = await _driveApi!.files.list(
        q: "'$parentId' in parents and name='$nameWithHyphens' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      if (res.files != null && res.files!.isNotEmpty) return res.files!.first.id!;
    }
    
    // 3. Si sigue sin encontrarse, crearlo con el nombre original
    final f = await _driveApi!.files.create(drive.File(name: name, parents: [parentId], mimeType: 'application/vnd.google-apps.folder'));
    return f.id!;
  }

  Future<void> uploadFinalArt(XFile image, Product product) async {
    await authenticate();
    if (_driveApi == null) return;

    await _ensureProductFolder(product);

    if (product.finalArtId != null) {
      try { await deleteFile(product.finalArtId!); } catch (e) { print("Error eliminando: $e"); }
    }

    // Estructura: ARTES FINALES / FAMILIA / SUBCATEGORIA / PRODUCTO #CODIGO
    String rootId = await _getOrCreateFolder("ARTES FINALES", _rootFolderId);
    String fId = await _getOrCreateFolder(product.familia.trim().isEmpty ? "SIN_CAT" : product.familia.trim(), rootId);
    String sId = await _getOrCreateFolder(product.subcategoria.trim().isEmpty ? "SIN_SUB" : product.subcategoria.trim(), fId);

    String folderName = product.titulo.trim();
    if (product.codTienda.trim().isNotEmpty) {
      folderName += " #${product.codTienda.trim()}";
    }
    String pId = await _getOrCreateFolder(folderName, sId);

    final bytes = await image.readAsBytes();
    final ext = image.name.split('.').last;
    final name = product.codTienda.trim().isEmpty ? "ARTE_${DateTime.now().millisecondsSinceEpoch}" : product.codTienda.trim();
    
    final file = await _driveApi!.files.create(
      drive.File(name: "$name.$ext", parents: [pId]),
      uploadMedia: drive.Media(Stream.fromIterable([bytes]), bytes.length, contentType: 'image/jpeg')
    );

    await _driveApi!.files.create(
      drive.File(name: "ARTE_FINAL_${image.name}", parents: [product.folderId!]),
      uploadMedia: drive.Media(Stream.fromIterable([bytes]), bytes.length, contentType: 'image/jpeg')
    );

    product.estado = 'listo';
    product.finalArtId = file.id;

    // Limpiar caché de miniatura para que el catálogo muestre el nuevo arte inmediatamente
    if (product.folderId != null) _thumbnailCache.remove(product.folderId);

    await updateProduct(product, []);
  }

  Future<void> updateProduct(Product product, List<XFile> newImages) async {
    await authenticate();
    if (_driveApi == null || product.folderId == null) return;
    
    await _ensureProductFolder(product);

    // 1. Renombrar carpeta principal del producto en Drive
    if (product.folderId != null) {
      try {
        await _driveApi!.files.update(drive.File(name: product.titulo), product.folderId!);
      } catch (e) {
        print("Error renombrando carpeta del producto: $e");
      }
    }

    // 2. Si es un producto LISTO, sincronizar su ubicación en ARTES FINALES
    if (product.estado.toLowerCase().trim() == 'listo') {
      try {
        String rootId = await _getOrCreateFolder("ARTES FINALES", _rootFolderId);
        String fId = await _getOrCreateFolder(product.familia.trim().isEmpty ? "SIN_CAT" : product.familia.trim(), rootId);
        String sId = await _getOrCreateFolder(product.subcategoria.trim().isEmpty ? "SIN_SUB" : product.subcategoria.trim(), fId);

        String folderName = product.titulo.trim();
        if (product.codTienda.trim().isNotEmpty) {
          folderName += " #${product.codTienda.trim()}";
        }

        // Buscar si ya tiene carpeta en Artes Finales y moverla/renombrarla
        if (product.finalArtId != null) {
          final artFile = await _driveApi!.files.get(product.finalArtId!, $fields: "parents") as drive.File;
          if (artFile.parents != null && artFile.parents!.isNotEmpty) {
            String oldParentId = artFile.parents!.first;
            // Renombrar la carpeta contenedora del arte final
            await _driveApi!.files.update(drive.File(name: folderName), oldParentId);
            // Mover a la nueva subcategoría si cambió
            if (oldParentId != sId) {
              await _driveApi!.files.update(drive.File(), oldParentId, addParents: sId, removeParents: oldParentId);
            }
          }
        }
      } catch (e) {
        print("Error sincronizando carpeta de Artes Finales: $e");
      }
    }

    // 3. Actualizar o crear Documento de info (Google Docs HTML)
    final docContent = _generateDocContent(product);
    final htmlBytes = utf8.encode(docContent);
    final docMedia = drive.Media(Stream.fromIterable([htmlBytes]), htmlBytes.length, contentType: 'text/html');
    final docMeta = drive.File(name: product.titulo);

    if (product.infoDocId != null && product.infoDocId!.isNotEmpty) {
      try {
        await _driveApi!.files.update(docMeta, product.infoDocId!, uploadMedia: docMedia);
      } catch (e) {
        if (e.toString().contains('404') || (e is drive.DetailedApiRequestError && e.status == 404)) {
          final foundId = await _findFileInFolder(product.folderId!, product.titulo);
          if (foundId != null) {
            product.infoDocId = foundId;
            await _driveApi!.files.update(docMeta, foundId, uploadMedia: docMedia);
          } else {
            docMeta.parents = [product.folderId!];
            docMeta.mimeType = 'application/vnd.google-apps.document';
            final docFile = await _driveApi!.files.create(docMeta, uploadMedia: docMedia);
            product.infoDocId = docFile.id;
          }
        } else {
          print("Error actualizando documento de información: $e");
        }
      }
    } else {
      try {
        final foundId = await _findFileInFolder(product.folderId!, product.titulo);
        if (foundId != null) {
          product.infoDocId = foundId;
          await _driveApi!.files.update(docMeta, foundId, uploadMedia: docMedia);
        } else {
          docMeta.parents = [product.folderId!];
          docMeta.mimeType = 'application/vnd.google-apps.document';
          final docFile = await _driveApi!.files.create(docMeta, uploadMedia: docMedia);
          product.infoDocId = docFile.id;
        }
      } catch (e) {
        print("Error creando documento de información: $e");
      }
    }

    // 4. Actualizar o crear data.json (Metadatos del producto)
    final jsonContent = utf8.encode(jsonEncode(product.toJson()));
    final dataMedia = drive.Media(Stream.fromIterable([jsonContent]), jsonContent.length, contentType: 'application/json');
    final dataMeta = drive.File(name: 'data.json', mimeType: 'application/json');

    if (product.dataFileId != null && product.dataFileId!.isNotEmpty) {
      try {
        await _driveApi!.files.update(dataMeta, product.dataFileId!, uploadMedia: dataMedia);
      } catch (e) {
        if (e.toString().contains('404') || (e is drive.DetailedApiRequestError && e.status == 404)) {
          final foundId = await _findFileInFolder(product.folderId!, 'data.json');
          if (foundId != null) {
            product.dataFileId = foundId;
            await _driveApi!.files.update(dataMeta, foundId, uploadMedia: dataMedia);
          } else {
            dataMeta.parents = [product.folderId!];
            final dataFile = await _driveApi!.files.create(dataMeta, uploadMedia: dataMedia);
            product.dataFileId = dataFile.id;
          }
        } else {
          rethrow;
        }
      }
    } else {
      final foundId = await _findFileInFolder(product.folderId!, 'data.json');
      if (foundId != null) {
        product.dataFileId = foundId;
        await _driveApi!.files.update(dataMeta, foundId, uploadMedia: dataMedia);
      } else {
        dataMeta.parents = [product.folderId!];
        final dataFile = await _driveApi!.files.create(dataMeta, uploadMedia: dataMedia);
        product.dataFileId = dataFile.id;
      }
    }

    // 5. Invalidar caché de miniatura para forzar refresco visual
    if (product.folderId != null) {
      _thumbnailCache.remove(product.folderId);
      _thumbnailCache.remove("${product.folderId}_raw");
    }

    // 6. Si se cargó un arte final, forzar la descarga de su miniatura para actualizar caché
    if (product.finalArtId != null) {
      try {
        await getProductThumbnail(product.folderId!, product.finalArtId, preferFinalArt: true);
      } catch (e) {
        print("Error precargando miniatura: $e");
      }
    }

    // 7. Sincronizar Caché Local Inmediatamente y proteger contra sobreescritura
    _recentlyUpdated[product.folderId!] = DateTime.now();
    final cache = await getLocalCache();
    final idx = cache.indexWhere((item) => item.folderId == product.folderId);
    if (idx != -1) {
      cache[idx] = product;
    } else {
      cache.add(product);
    }

    // 8. Subir nuevas imágenes si las hay
    for (var img in newImages) {
      final b = await img.readAsBytes();
      final ext = img.name.split('.').last.toLowerCase();
      String mime = 'image/jpeg';
      if (ext == 'png') mime = 'image/png';
      if (ext == 'webp') mime = 'image/webp';

      final file = await _driveApi!.files.create(
        drive.File(
          name: img.name, 
          parents: [product.folderId!],
          mimeType: mime,
        ), 
        uploadMedia: drive.Media(Stream.fromIterable([b]), b.length, contentType: mime)
      );
      if (file.id != null) product.imageIds.add(file.id!);
    }
    
    // Volver a guardar el data.json si se agregaron imágenes para persistir sus IDs
    if (newImages.isNotEmpty) {
      final updatedJson = utf8.encode(jsonEncode(product.toJson()));
      final updatedMedia = drive.Media(Stream.fromIterable([updatedJson]), updatedJson.length, contentType: 'application/json');
      if (product.dataFileId != null) {
        try {
          await _driveApi!.files.update(dataMeta, product.dataFileId!, uploadMedia: updatedMedia);
        } catch (e) {
          print("Error actualizando data.json final con imágenes: $e");
        }
      }
    }

    // 9. Guardar caché final (ahora con imageIds actualizados)
    await _saveToLocalCache(cache);
  }

  Future<void> deleteFile(String folderId) async {
    _recentlyDeleted.add(folderId);
    await authenticate();
    if (_driveApi == null) return;
    try {
      // 1. Borrar de la Memoria RAM inmediatamente para reactividad instantánea
      _inMemoryProducts.removeWhere((p) => p.folderId == folderId);
      _thumbnailCache.remove(folderId);
      
      // 2. Borrar de Drive (Nube) - Ignorar si no existe (404)
      try {
        await _driveApi!.files.delete(folderId);
      } catch (e) {
        final errStr = e.toString();
        final is404 = errStr.contains('404') || 
                      (e is drive.DetailedApiRequestError && e.status == 404);
        if (!is404) {
          print("Error al eliminar archivo de Drive: $e");
        }
      }
      
      // 3. Sincronizar Caché Local (Disco)
      await _saveToLocalCache(_inMemoryProducts);
    } catch (e) {
      final errStr = e.toString();
      final is404 = errStr.contains('404') || 
                    (e is drive.DetailedApiRequestError && e.status == 404);
      if (!is404) {
        print("Error al eliminar archivo: $e");
      }
    }
  }

  Future<void> deleteMultipleFiles(List<String> folderIds) async {
    _recentlyDeleted.addAll(folderIds);
    await authenticate();
    if (_driveApi == null) return;
    
    // 1. Limpieza instantánea de Memoria RAM
    _inMemoryProducts.removeWhere((p) => folderIds.contains(p.folderId));
    for (var id in folderIds) { _thumbnailCache.remove(id); }
    
    // 2. Actualización de disco inmediata
    await _saveToLocalCache(_inMemoryProducts);

    // 3. Borrado en paralelo en Drive - Ignorar 404s
    final tasks = folderIds.map((id) => _driveApi!.files.delete(id).catchError((e) {
      if (!e.toString().contains('404')) {
        print("Error eliminando archivo múltiple de Drive: $e");
      }
    }));
    await Future.wait(tasks);
  }

  Future<void> clearAllNotasEntrega() async {
    await authenticate();
    if (_driveApi == null) return;
    try {
      final dbRootId = await _getOrCreateFolder("NOVALED-BASE-DE-DATOS", _rootFolderId);
      // Buscar la carpeta NOTAS_ENTREGA
      final res = await _driveApi!.files.list(
        q: "'$dbRootId' in parents and name='NOTAS_ENTREGA' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        $fields: "files(id)",
      );
      if (res.files != null && res.files!.isNotEmpty) {
        for (var f in res.files!) {
          try {
            await _driveApi!.files.delete(f.id!);
          } catch (e) {
            // Ignorar 404
          }
        }
      }
    } catch (e) {
      print("Error clearing Notas de Entrega in Drive: $e");
    }
  }

  Future<void> deleteImageFromProduct(String fileId, String productFolderId) async {
    await authenticate();
    if (_driveApi == null) return;
    try {
      // 1. Invalidar caché de miniatura del producto para que se regenere con la siguiente imagen
      _thumbnailCache.remove(productFolderId);
      
      // 2. Borrar archivo de Drive
      await _driveApi!.files.delete(fileId);
    } catch (e) {
      print("Error eliminando imagen de producto: $e");
    }
  }

  Future<Uint8List?> getProductHighRes(String folderId, String? finalArtId) async {
    try {
      // 1. Intentar cargar desde Hostinger MySQL usando el nombre de la imagen guardada en SQLite
      try {
        final db = await DatabaseHelper.instance.database;
        final res = await db.query('articulos', columns: ['imagen'], where: 'folderId = ?', whereArgs: [folderId]);
        if (res.isNotEmpty && res.first['imagen'] != null && res.first['imagen'].toString().isNotEmpty) {
          final imagenFilename = res.first['imagen'].toString();
          final url = 'https://novaledbolivia.com/sistema/api/uploads/$imagenFilename';
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            return response.bodyBytes;
          }
        }
      } catch (sqError) {
        print("Error al intentar obtener imagen de SQLite/Hostinger en HighRes: $sqError");
      }

      // 2. Fallback a Google Drive
      String? targetId = finalArtId;
      if (targetId == null || targetId.isEmpty) {
        final folderImages = await getProductImages(folderId);
        if (folderImages.isNotEmpty) targetId = folderImages.first;
      }
      
      if (targetId != null && targetId.isNotEmpty) {
        final bytes = await getFileBytes(targetId);
        if (bytes.isNotEmpty) return Uint8List.fromList(bytes);
      }
    } catch (e) { 
      print("Error descargando alta resolución: $e"); 
    }
    return null;
  }

  Future<Uint8List?> getProductThumbnail(String folderId, String? finalArtId, {bool preferFinalArt = true}) async {
    final cacheKey = preferFinalArt ? folderId : "${folderId}_raw";
    
    // Throttling: Pequeño retraso aleatorio para evitar saturar el pool de conexiones
    // Excepto si es una petición de refresco explícita (poca concurrencia)
    if (_thumbnailCache.containsKey(cacheKey)) {
      final cached = _thumbnailCache[cacheKey];
      if (cached != null && cached.isEmpty) return null; // Sentinel para indicar que no hay imagen
      return cached;
    }

    try {
      // 1. Intentar cargar desde Hostinger MySQL usando el nombre de la imagen guardada en SQLite
      try {
        final db = await DatabaseHelper.instance.database;
        final res = await db.query('articulos', columns: ['imagen'], where: 'folderId = ?', whereArgs: [folderId]);
        if (res.isNotEmpty && res.first['imagen'] != null && res.first['imagen'].toString().isNotEmpty) {
          final imagenFilename = res.first['imagen'].toString();
          final url = 'https://novaledbolivia.com/sistema/api/uploads/$imagenFilename';
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            _thumbnailCache[cacheKey] = response.bodyBytes;
            return response.bodyBytes;
          }
        }
      } catch (sqError) {
        print("Error al intentar obtener imagen de SQLite/Hostinger en Thumbnail: $sqError");
      }

      // 2. Fallback a Google Drive
      await Future.delayed(Duration(milliseconds: 50 + (folderId.hashCode % 300)));
      
      await authenticate();
      if (_driveApi == null) return null;

      String? targetId;
      String? thumbLink;

      if (preferFinalArt && finalArtId != null && finalArtId.isNotEmpty) {
        targetId = finalArtId;
      } else {
        // REQUERIMIENTO INICIO: La miniatura es siempre la PRIMERA imagen cargada cronológicamente
        final res = await _driveApi!.files.list(
          q: "'$folderId' in parents and trashed=false and mimeType contains 'image/'",
          $fields: "files(id, thumbnailLink)",
          orderBy: 'createdTime',
          pageSize: 1,
        );

        if (res.files != null && res.files!.isNotEmpty) {
          targetId = res.files!.first.id;
          thumbLink = res.files!.first.thumbnailLink;
        } else {
          // Fallback al Arte Final si no hay fotos originales
          targetId = finalArtId;
        }
      }
      
      if (targetId != null && targetId.isNotEmpty) {
        // Si ya tenemos el thumbnailLink de la consulta anterior, lo usamos
        if (thumbLink == null) {
          final drive.File fileMeta = await _driveApi!.files.get(targetId, $fields: "thumbnailLink") as drive.File;
          thumbLink = fileMeta.thumbnailLink;
        }
        
        if (thumbLink != null) {
          final tempClient = http.Client();
          try {
            final headers = await _getManualAuthHeaders();
            final thumbRes = await tempClient.get(Uri.parse(thumbLink), headers: headers).timeout(const Duration(seconds: 10));
            if (thumbRes.statusCode == 200) {
              _thumbnailCache[cacheKey] = thumbRes.bodyBytes;
              return thumbRes.bodyBytes;
            }
          } catch (e) {
            print("Error en petición thumbnailLink: $e");
          } finally {
            tempClient.close();
          }
        }

        // Fallback robusto: Descarga directa si el link de miniatura falla
        final bytes = await getFileBytes(targetId);
        if (bytes.isNotEmpty) {
          final uint8 = Uint8List.fromList(bytes);
          _thumbnailCache[cacheKey] = uint8;
          return uint8;
        }
      }
      
      // Cachear la ausencia de la imagen usando un buffer vacío como centinela
      _thumbnailCache[cacheKey] = Uint8List(0);
    } catch (e) { 
      print("Error crítico cargando miniatura para $folderId: $e");
    }
    return null;
  }

  Future<String> testConnection() async {
    try {
      final bool authResult = await authenticate();
      if (!authResult) {
        return "Fallo en autenticación: lastError = $lastError";
      }
      if (_driveApi == null) {
        return "Fallo: _driveApi es nulo";
      }
      
      // 1. Listar subcarpetas en la raíz
      final res = await _driveApi!.files.list(
        q: "'$_rootFolderId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false",
        pageSize: 40,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      final folders = res.files ?? [];
      if (folders.isEmpty) {
        // Mostrar también archivos sueltos en la raíz por si acaso
        final rootFilesRes = await _driveApi!.files.list(
          q: "'$_rootFolderId' in parents and trashed=false",
          pageSize: 20,
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
        );
        final rootFiles = rootFilesRes.files ?? [];
        final fileList = rootFiles.map((f) => "${f.name} (${f.id})").join(", ");
        return "Éxito en conexión, pero no hay subcarpetas en la raíz. Archivos encontrados en raíz: $fileList";
      }
      
      // Pruebas comparativas de búsqueda
      final List<String> folderIds = folders.map((f) => f.id!).toList();
      
      // Prueba 1: Búsqueda por lotes (OR parents)
      int chunkedCount = 0;
      String chunkedError = "Ninguno";
      if (folderIds.isNotEmpty) {
        try {
          final String parentQuery = folderIds.take(30).map((id) => "'$id' in parents").join(" or ");
          final String chunkQuery = "name='data.json' and trashed=false and ($parentQuery)";
          final resChunk = await _driveApi!.files.list(
            q: chunkQuery,
            $fields: "files(id, name, parents)",
            pageSize: 100,
            supportsAllDrives: true,
            includeItemsFromAllDrives: true,
          );
          chunkedCount = resChunk.files?.length ?? 0;
        } catch (e) {
          chunkedError = e.toString();
        }
      }
      
      // Prueba 2: Búsqueda global con filtro en memoria
      int globalCount = 0;
      int globalFilteredCount = 0;
      String globalError = "Ninguno";
      try {
        final resGlobal = await _driveApi!.files.list(
          q: "name='data.json' and trashed=false",
          $fields: "files(id, name, parents)",
          pageSize: 1000,
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
        );
        final gFiles = resGlobal.files ?? [];
        globalCount = gFiles.length;
        final folderMap = {for (var f in folders) f.id!: f.name!};
        for (var file in gFiles) {
          final parentId = (file.parents != null && file.parents!.isNotEmpty) ? file.parents!.first : null;
          if (parentId != null && folderMap.containsKey(parentId)) {
            globalFilteredCount++;
          }
        }
      } catch (e) {
        globalError = e.toString();
      }

      StringBuffer diagnostics = StringBuffer();
      diagnostics.writeln("=== COMPARATIVA DE BÚSQUEDA ===");
      diagnostics.writeln("1. Búsqueda por lotes (OR parents):");
      diagnostics.writeln("   - Encontrados: $chunkedCount archivos (lim 30)");
      diagnostics.writeln("   - Error: $chunkedError");
      diagnostics.writeln("2. Búsqueda global (in-memory filter):");
      diagnostics.writeln("   - Encontrados en total: $globalCount");
      diagnostics.writeln("   - Filtrados que coinciden: $globalFilteredCount");
      diagnostics.writeln("   - Error: $globalError");
      diagnostics.writeln("=================================\n");

      diagnostics.writeln("Conexión exitosa. Encontradas ${folders.length} subcarpetas (primeras 40):");
      
      for (var folder in folders) {
        diagnostics.writeln("- Carpeta: ${folder.name} (ID: ${folder.id})");
        
        // Listar archivos dentro de esta subcarpeta
        try {
          final filesRes = await _driveApi!.files.list(
            q: "'${folder.id}' in parents and trashed=false",
            supportsAllDrives: true,
            includeItemsFromAllDrives: true,
          );
          final files = filesRes.files ?? [];
          if (files.isEmpty) {
            diagnostics.writeln("  -> VACÍA");
          } else {
            final fileNames = files.map((f) => "${f.name} (${f.id})").join(", ");
            diagnostics.writeln("  -> Contiene: $fileNames");
            
            // Buscar data.json
            final dataJsonFile = files.firstWhere((f) => f.name == 'data.json', orElse: () => drive.File());
            if (dataJsonFile.id != null) {
              try {
                final response = await _driveApi!.files.get(dataJsonFile.id!, downloadOptions: drive.DownloadOptions.fullMedia);
                if (response is drive.Media) {
                  final List<int> bytes = [];
                  await for (final chunk in response.stream) { bytes.addAll(chunk); }
                  final content = utf8.decode(bytes);
                  final preview = content.length > 100 ? "${content.substring(0, 100)}..." : content;
                  diagnostics.writeln("  -> data.json: $preview");
                } else {
                  diagnostics.writeln("  -> data.json no es tipo Media");
                }
              } catch (e) {
                diagnostics.writeln("  -> Error leyendo data.json: $e");
              }
            } else {
              diagnostics.writeln("  -> NO TIENE data.json");
            }
          }
        } catch (e) {
          diagnostics.writeln("  -> Error listando archivos de esta carpeta: $e");
        }
      }
      return diagnostics.toString();
    } catch (e) {
      lastError = "testConnection error: $e";
      return "Fallo en consulta general: $e";
    }
  }
}
