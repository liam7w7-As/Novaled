import 'dart:io';
import 'dart:async';
import '../drive_service.dart';
import '../login_screen.dart';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tenant_helper.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static Completer<Database>? _initCompleter;
  static String _currentTenantDb = 'novaled.db';

  DatabaseHelper._init();

  static String resolveTenantDb(String? identifier) {
    if (TenantHelper.isNovaled(identifier)) {
      return 'novaled.db';
    }
    final clean = identifier!.toLowerCase().trim();
    final safe = clean.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    return 'tenant_$safe.db';
  }

  Future<void> switchTenant(String identifier) async {
    final targetDb = resolveTenantDb(identifier);
    DriveService().clearMemoryCaches();
    if (_currentTenantDb != targetDb || _database == null || !_database!.isOpen) {
      if (_database != null && _database!.isOpen) {
        await _database!.close();
      }
      _database = null;
      _initCompleter = null;
      _currentTenantDb = targetDb;
      debugPrint("[MULTI-TENANT] Base de datos cambiada a: $_currentTenantDb para usuario/empresa: $identifier");
    }
  }

  Future<void> closeDatabase() async {
    DriveService().clearMemoryCaches();
    if (_database != null && _database!.isOpen) {
      await _database!.close();
    }
    _database = null;
    _initCompleter = null;
  }

  Future<Database> get database async {
    try {
      final sessionUser = Session().userName;
      final prefs = await SharedPreferences.getInstance();
      final activeUser = (sessionUser != null && sessionUser.isNotEmpty)
          ? sessionUser
          : (prefs.getString('last_user') ?? prefs.getString('saved_user') ?? '');
      final targetDb = resolveTenantDb(activeUser);

      if (_currentTenantDb != targetDb) {
        DriveService().clearMemoryCaches();
        if (_database != null && _database!.isOpen) {
          await _database!.close();
        }
        _database = null;
        _initCompleter = null;
        _currentTenantDb = targetDb;
        debugPrint("[MULTI-TENANT] Switch reactivo a: $_currentTenantDb para usuario activo: $activeUser");
      }
    } catch (_) {}

    if (_database != null && _database!.isOpen) return _database!;
    
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<Database>();
    try {
      _database = await _initDB(_currentTenantDb);
      _initCompleter!.complete(_database!);
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      String path;
      if (kIsWeb) {
        path = filePath;
      } else if (Platform.isWindows) {
        final appDir = await getApplicationSupportDirectory();
        if (!await appDir.exists()) {
          await appDir.create(recursive: true);
        }
        path = join(appDir.path, filePath);
      } else {
        final dbPath = await getDatabasesPath();
        path = join(dbPath, filePath);
      }

      final db = await openDatabase(
        path,
        version: 20, // Incrementar a 20 para agregar pagos y comprobante
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          await _repairDatabase(db);
        },
      );

      // Limpieza de claves de sincronización post-apertura para evitar deadlocks
      try {
        final prefs = await SharedPreferences.getInstance();
        final currentVer = prefs.getInt('db_version_synced') ?? 0;
        if (currentVer < 19) {
          final keys = prefs.getKeys();
          for (var key in keys) {
            if (key.startsWith('last_sync_')) {
              await prefs.remove(key);
            }
          }
          await prefs.setInt('db_version_synced', 19);
        }
        debugPrint("Limpieza de caché de sincronización (last_sync_*) completada para migración a v19.");
      } catch (e) {
        debugPrint("Error al limpiar claves last_sync en post-inicialización: $e");
      }

      return db;
    } catch (e) {
      debugPrint("Error crítico inicializando DB: $e");
      rethrow;
    }
  }

  Future<void> _repairDatabase(Database db) async {
    debugPrint("Iniciando reparación de esquema si es necesario...");
    final bool isNovaledDb = _currentTenantDb == 'novaled.db';
    
    final artColumns = {
      'precioCaja': 'REAL DEFAULT 0.0',
      'folderId': 'TEXT',
      'finalArtId': 'TEXT',
      'proveedor': 'TEXT',
      'codCaja': 'TEXT',
      'stockJson': 'TEXT',
      'familia': 'TEXT DEFAULT ""',
      'subcategoria': 'TEXT DEFAULT ""',
      'unidad': 'TEXT DEFAULT "Unidad"',
      'unidadDetalle': 'TEXT DEFAULT ""',
      'imagen': 'TEXT',
      'fecha': 'TEXT DEFAULT ""',
    };

    for (var col in artColumns.entries) {
      try {
        await db.execute('ALTER TABLE articulos ADD COLUMN ${col.key} ${col.value}');
      } catch (e) {}
    }

    final docColumns = {
      'subtotal': 'REAL DEFAULT 0.0',
      'impuesto': 'REAL DEFAULT 0.0',
      'descuento': 'REAL DEFAULT 0.0',
      'descuentoPorcentaje': 'REAL DEFAULT 0.0',
      'notas': 'TEXT',
      'terminos': 'TEXT',
      'incluyeFirmaEmpresa': 'INTEGER DEFAULT 0',
      'incluyeFirmaCliente': 'INTEGER DEFAULT 0',
      'mostrarTerminos': 'INTEGER DEFAULT 1',
      'mostrarAhorro': 'INTEGER DEFAULT 0',
      'folderId': 'TEXT',
      'uuid': 'TEXT',
      'displayId': 'INTEGER',
      'clienteTelefono': 'TEXT',
      'clienteCorreo': 'TEXT',
      'tipo_venta': "TEXT DEFAULT 'punto_venta'",
      'tipo_documento': "TEXT DEFAULT 'proforma'",
      'vendedor': isNovaledDb ? "TEXT DEFAULT 'JOEL'" : "TEXT DEFAULT ''",
      'sucursal': isNovaledDb ? "TEXT DEFAULT 'C. Isaac Tamayo #840 La Paz - Bolivia'" : "TEXT DEFAULT ''",
      'metodo_pago': "TEXT DEFAULT 'Transferencia Bancaria'",
      'estado_pago': "TEXT DEFAULT 'por_cobrar'",
      'estado': "TEXT DEFAULT 'pendiente'",
      'comprobante_img': 'TEXT',
      'comprobado': 'INTEGER DEFAULT 0',
      'saldo_cancelado': 'REAL DEFAULT 0.0',
    };

    final tables = ['cotizaciones', 'notas_entrega', 'proformas'];

    for (var table in tables) {
      for (var col in docColumns.entries) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN ${col.key} ${col.value}');
        } catch (e) {}
      }
      if (isNovaledDb) {
        try {
          await db.execute("UPDATE $table SET vendedor = 'JOEL' WHERE vendedor IS NULL OR vendedor = 'Dueño' OR vendedor = '' OR vendedor = 'null'");
        } catch (e) {}
        try {
          await db.execute("UPDATE $table SET sucursal = 'C. Isaac Tamayo #840 La Paz - Bolivia' WHERE sucursal IS NULL OR sucursal = '' OR sucursal = '#818' OR sucursal = '#840' OR sucursal = 'null'");
        } catch (e) {}
      }
    }

    // Asegurar folderId en otras tablas
    final otherTables = ['clientes', 'proveedores', 'tiendas'];
    for (var table in otherTables) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN folderId TEXT');
      } catch (e) {}
    }

    // Columnas adicionales para clientes (CSV Import)
    final cliColumns = {
      'rn': 'TEXT DEFAULT ""',
      'direccion1': 'TEXT DEFAULT ""',
      'direccion2': 'TEXT DEFAULT ""',
      'direccion3': 'TEXT DEFAULT ""',
      'direccionEnvio1': 'TEXT DEFAULT ""',
      'direccionEnvio2': 'TEXT DEFAULT ""',
      'direccionEnvio3': 'TEXT DEFAULT ""',
      'infoAdicional': 'TEXT DEFAULT ""',
    };

    for (var col in cliColumns.entries) {
      try {
        await db.execute('ALTER TABLE clientes ADD COLUMN ${col.key} ${col.value}');
      } catch (e) {}
    }

    // Retro-compatibilidad/Relleno de UUIDs antiguos
    for (var table in tables) {
      try {
        final List<Map<String, dynamic>> rows = await db.query(table, columns: ['id'], where: "uuid IS NULL OR uuid = ''");
        for (var row in rows) {
          final id = row['id'];
          final uuid = _generateUUID();
          await db.update(table, {'uuid': uuid}, where: 'id = ?', whereArgs: [id]);
        }
      } catch (e) {
        debugPrint("Error backpopulating UUIDs on $table: $e");
      }
    }

    // Crear tabla de unidades de medida si no existe y poblarla por defecto
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS unidades_medida (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nombre TEXT UNIQUE NOT NULL,
          folderId TEXT
        )
      ''');
      final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM unidades_medida')) ?? 0;
      if (count == 0) {
        final defaultUnits = ["Unidad", "Metros", "Kg", "Rollo", "Barra", "Caja", "Par"];
        for (var unit in defaultUnits) {
          await db.insert('unidades_medida', {'nombre': unit});
        }
        debugPrint("Tabla unidades_medida pre-populada exitosamente.");
      }
    } catch (e) {
      debugPrint("Error inicializando/reparando tabla unidades_medida: $e");
    }

    // Crear tabla de sub_ubicaciones si no existe
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sub_ubicaciones (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nombre TEXT NOT NULL,
          tienda_nombre TEXT NOT NULL,
          folderId TEXT,
          imagen TEXT
        )
      ''');
    } catch (e) {
      debugPrint("Error inicializando/reparando tabla sub_ubicaciones: $e");
    }

    // Agregar columna imagen a sub_ubicaciones si no existe
    try {
      await db.execute('ALTER TABLE sub_ubicaciones ADD COLUMN imagen TEXT');
    } catch (e) {}

    // Crear tabla de registros eliminados para sincronización
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS deleted_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tabla TEXT NOT NULL,
          uuid TEXT NOT NULL,
          deleted_at TEXT NOT NULL
        )
      ''');
    } catch (e) {
      debugPrint("Error creando tabla deleted_records: $e");
    }

    // Crear índices para mejorar velocidad de consultas y evitar Table Scans
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_articulos_folderId ON articulos(folderId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_articulos_nombre ON articulos(nombre)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_cotizaciones_uuid ON cotizaciones(uuid)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_notas_entrega_uuid ON notas_entrega(uuid)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_proformas_uuid ON proformas(uuid)');
      debugPrint("Índices de base de datos creados/verificados con éxito.");
    } catch (e) {
      debugPrint("Error creando índices de base de datos: $e");
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE articulos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        precio REAL NOT NULL,
        precioCaja REAL DEFAULT 0.0,
        descripcion TEXT,
        folderId TEXT,
        finalArtId TEXT,
        proveedor TEXT,
        codCaja TEXT,
        stockJson TEXT,
        familia TEXT DEFAULT "",
        subcategoria TEXT DEFAULT "",
        unidad TEXT DEFAULT "Unidad",
        unidadDetalle TEXT DEFAULT "",
        imagen TEXT,
        fecha TEXT DEFAULT ""
      )
    ''');

    await db.execute('''
      CREATE TABLE clientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombreCompania TEXT NOT NULL,
        telefono TEXT,
        correo TEXT,
        rn TEXT DEFAULT "",
        direccion1 TEXT DEFAULT "",
        direccion2 TEXT DEFAULT "",
        direccion3 TEXT DEFAULT "",
        direccionEnvio1 TEXT DEFAULT "",
        direccionEnvio2 TEXT DEFAULT "",
        direccionEnvio3 TEXT DEFAULT "",
        infoAdicional TEXT DEFAULT "",
        folderId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cotizaciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clienteNombre TEXT,
        fecha TEXT,
        subtotal REAL,
        impuesto REAL,
        descuento REAL,
        descuentoPorcentaje REAL DEFAULT 0.0,
        total REAL,
        itemsJson TEXT,
        notas TEXT,
        terminos TEXT,
        incluyeFirmaEmpresa INTEGER DEFAULT 0,
        incluyeFirmaCliente INTEGER DEFAULT 0,
        mostrarTerminos INTEGER DEFAULT 1,
        mostrarAhorro INTEGER DEFAULT 0,
        tipo_venta TEXT DEFAULT 'punto_venta',
        vendedor TEXT DEFAULT '',
        estado TEXT DEFAULT 'pendiente',
        metodo_pago TEXT DEFAULT 'Transferencia Bancaria',
        estado_pago TEXT DEFAULT 'por_cobrar',
        comprobante_img TEXT,
        comprobado INTEGER DEFAULT 0,
        saldo_cancelado REAL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE proveedores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        telefono TEXT,
        correo TEXT,
        direccion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE notas_entrega (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clienteNombre TEXT,
        fecha TEXT,
        subtotal REAL,
        impuesto REAL,
        descuento REAL,
        descuentoPorcentaje REAL DEFAULT 0.0,
        total REAL,
        itemsJson TEXT,
        notas TEXT,
        terminos TEXT,
        incluyeFirmaEmpresa INTEGER DEFAULT 0,
        incluyeFirmaCliente INTEGER DEFAULT 0,
        mostrarTerminos INTEGER DEFAULT 1,
        mostrarAhorro INTEGER DEFAULT 0,
        tipo_venta TEXT DEFAULT 'punto_venta',
        vendedor TEXT DEFAULT '',
        metodo_pago TEXT DEFAULT 'Transferencia Bancaria',
        estado_pago TEXT DEFAULT 'por_cobrar',
        comprobante_img TEXT,
        comprobado INTEGER DEFAULT 0,
        saldo_cancelado REAL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE proformas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clienteNombre TEXT,
        fecha TEXT,
        subtotal REAL,
        impuesto REAL,
        descuento REAL,
        descuentoPorcentaje REAL DEFAULT 0.0,
        total REAL,
        itemsJson TEXT,
        notas TEXT,
        terminos TEXT,
        incluyeFirmaEmpresa INTEGER DEFAULT 0,
        incluyeFirmaCliente INTEGER DEFAULT 0,
        mostrarTerminos INTEGER DEFAULT 1,
        mostrarAhorro INTEGER DEFAULT 0,
        tipo_venta TEXT DEFAULT 'punto_venta',
        tipo_documento TEXT DEFAULT 'proforma',
        vendedor TEXT DEFAULT '',
        metodo_pago TEXT DEFAULT 'Transferencia Bancaria',
        estado_pago TEXT DEFAULT 'por_cobrar',
        comprobante_img TEXT,
        comprobado INTEGER DEFAULT 0,
        saldo_cancelado REAL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE tiendas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        ubicacion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sub_ubicaciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        tienda_nombre TEXT NOT NULL,
        folderId TEXT,
        imagen TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE unidades_medida (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT UNIQUE NOT NULL,
        folderId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS deleted_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tabla TEXT NOT NULL,
        uuid TEXT NOT NULL,
        deleted_at TEXT NOT NULL
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("Actualizando base de datos de $oldVersion a $newVersion");
    
    if (oldVersion < 20) {
      final tables = ['cotizaciones', 'notas_entrega', 'proformas'];
      for (var table in tables) {
        try {
          await db.execute("ALTER TABLE $table ADD COLUMN comprobante_img TEXT");
        } catch (e) {}
        try {
          await db.execute("ALTER TABLE $table ADD COLUMN comprobado INTEGER DEFAULT 0");
        } catch (e) {}
        try {
          await db.execute("ALTER TABLE $table ADD COLUMN saldo_cancelado REAL DEFAULT 0.0");
        } catch (e) {}
      }
    }
    
    if (oldVersion < 19) {
      final tables = ['cotizaciones', 'notas_entrega', 'proformas'];
      for (var table in tables) {
        try {
          await db.execute("ALTER TABLE $table ADD COLUMN metodo_pago TEXT DEFAULT 'Transferencia Bancaria'");
        } catch (e) {}
        try {
          await db.execute("ALTER TABLE $table ADD COLUMN estado_pago TEXT DEFAULT 'por_cobrar'");
        } catch (e) {}
      }
    }

    if (oldVersion < 18) {
      try {
        await db.execute('ALTER TABLE cotizaciones ADD COLUMN estado TEXT DEFAULT "pendiente"');
      } catch (e) {
        debugPrint("Error migrating db to v18: $e");
      }
    }
    
    if (oldVersion < 16) {
      final tables = ['cotizaciones', 'notas_entrega', 'proformas'];
      for (var table in tables) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN mostrarAhorro INTEGER DEFAULT 0');
        } catch (e) {}
      }
    }

    if (oldVersion < 15) {
      final tables = ['cotizaciones', 'notas_entrega', 'proformas'];
      for (var table in tables) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN mostrarTerminos INTEGER DEFAULT 1');
        } catch (e) {}
      }
    }

    if (oldVersion < 14) {
      try {
        await db.execute('ALTER TABLE cotizaciones ADD COLUMN terminos TEXT');
      } catch (e) {
        // Ignorar si ya existe
      }
    }

    if (oldVersion < 13) {
      try {
        await db.execute('ALTER TABLE cotizaciones ADD COLUMN notas TEXT');
        await db.execute('ALTER TABLE cotizaciones ADD COLUMN incluyeFirmaEmpresa INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE cotizaciones ADD COLUMN incluyeFirmaCliente INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE cotizaciones ADD COLUMN descuentoPorcentaje REAL DEFAULT 0.0');
      } catch (e) {
        // Ignorar si ya existen
      }
    }

    if (oldVersion < 12) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tiendas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nombre TEXT NOT NULL,
          ubicacion TEXT
        )
      ''');
    }

    if (oldVersion < 11) {
      await _repairDatabase(db);
    }

    // Migraciones históricas críticas
    if (oldVersion < 8) {
      await db.execute('DROP TABLE IF EXISTS notas_entrega');
      await db.execute('DROP TABLE IF EXISTS proformas');
      await db.execute('''
        CREATE TABLE notas_entrega (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          clienteNombre TEXT,
          fecha TEXT,
          total REAL,
          itemsJson TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE proformas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          clienteNombre TEXT,
          fecha TEXT,
          total REAL,
          itemsJson TEXT
        )
      ''');
    }
  }

  // CRUD Artículos
  Future<int> insertArticulo(Map<String, dynamic> row) async {
    debugPrint("Intentando insertar artículo: ${row['nombre']}");
    final db = await instance.database;
    await setTableDirty('articulos');
    DriveService().clearMemoryCaches();
    final id = await db.insert('articulos', row);
    debugPrint("Artículo insertado con éxito. ID: $id");
    return id;
  }

  Future<List<Map<String, dynamic>>> queryAllArticulos() async {
    final db = await instance.database;
    return await db.query('articulos');
  }

  Future<int> updateArticulo(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('articulos');
    DriveService().clearMemoryCaches();
    int id = row['id'];
    return await db.update('articulos', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteArticulo(int id) async {
    final db = await instance.database;
    await setTableDirty('articulos');
    DriveService().clearMemoryCaches();
    await _logDeletion('articulos', 'id', 'folderId', id);
    return await db.delete('articulos', where: 'id = ?', whereArgs: [id]);
  }

  Future<int?> getArticuloIdByFolderId(String folderId) async {
    final db = await instance.database;
    final res = await db.query('articulos', where: 'folderId = ?', whereArgs: [folderId]);
    return res.isNotEmpty ? res.first['id'] as int : null;
  }

  Future<void> _logDeletion(String table, String idColumn, String uuidColumn, int id) async {
    try {
      final db = await instance.database;
      final res = await db.query(table, where: '$idColumn = ?', whereArgs: [id]);
      if (res.isNotEmpty) {
        final row = res.first;
        String? uuid = row[uuidColumn]?.toString();
        final String? nombre = row['nombre']?.toString() ?? row['nombreCompania']?.toString();
        if (uuid == null || uuid.isEmpty) {
          uuid = "DEL_${table.toUpperCase()}_${DateTime.now().millisecondsSinceEpoch}";
        }
        await recordDeletion(table, uuid, nombre: nombre);
      }
    } catch (e) {
      debugPrint("Error logging deletion for $table ($id): $e");
    }
  }

  // Métodos para registros eliminados (sincronización)
  Future<void> recordDeletion(String table, String uuid, {String? nombre}) async {
    final db = await instance.database;
    await setTableDirty(table);
    try {
      await db.execute('ALTER TABLE deleted_records ADD COLUMN nombre TEXT');
    } catch (_) {}
    await db.insert('deleted_records', {
      'tabla': table,
      'uuid': uuid,
      'nombre': nombre,
      'deleted_at': DateTime.now().toIso8601String()
    });
  }

  Future<List<Map<String, dynamic>>> getDeletedRecords(String table) async {
    final db = await instance.database;
    try {
      await db.execute('ALTER TABLE deleted_records ADD COLUMN nombre TEXT');
    } catch (_) {}
    return await db.query('deleted_records', where: 'tabla = ?', whereArgs: [table]);
  }

  Future<void> clearDeletedRecords(String table, List<String> uuids) async {
    final db = await instance.database;
    for (var uuid in uuids) {
      await db.delete('deleted_records', where: 'tabla = ? AND uuid = ?', whereArgs: [table, uuid]);
    }
  }

  // CRUD Clientes
  Future<int> insertCliente(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('clientes');
    return await db.insert('clientes', row);
  }

  Future<List<Map<String, dynamic>>> queryAllClientes() async {
    final db = await instance.database;
    return await db.query('clientes');
  }

  Future<int> updateCliente(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('clientes');
    int id = row['id'];
    return await db.update('clientes', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCliente(int id) async {
    final db = await instance.database;
    await setTableDirty('clientes');
    await _logDeletion('clientes', 'id', 'folderId', id);
    return await db.delete('clientes', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>> _sanitizeRowForTable(Database db, String table, Map<String, dynamic> row) async {
    try {
      final columnsInfo = await db.rawQuery('PRAGMA table_info($table)');
      final validColumns = columnsInfo.map((c) => c['name'] as String).toSet();
      final sanitized = Map<String, dynamic>.from(row);
      sanitized.removeWhere((key, value) => !validColumns.contains(key));
      return sanitized;
    } catch (e) {
      debugPrint("Error sanitizing row for $table: $e");
      return row;
    }
  }

  // CRUD Cotizaciones
  Future<int> insertCotizacion(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('cotizaciones');
    final mutable = Map<String, dynamic>.from(row);
    if (mutable['uuid'] == null || mutable['uuid'].toString().isEmpty) {
      mutable['uuid'] = _generateUUID();
    }
    final sanitized = await _sanitizeRowForTable(db, 'cotizaciones', mutable);
    final id = await db.insert('cotizaciones', sanitized);
    PlanLimitHelper.registerCotizacionCreated();
    return id;
  }

  Future<List<Map<String, dynamic>>> queryAllCotizaciones({String? tipoVenta}) async {
    final db = await instance.database;
    if (tipoVenta != null && tipoVenta.isNotEmpty && tipoVenta != 'cotizacion') {
      return await db.query('cotizaciones', where: "tipo_venta = ? OR tipo_venta IS NULL", whereArgs: [tipoVenta]);
    }
    return await db.query('cotizaciones');
  }

  Future<int> deleteCotizacion(int id) async {
    final db = await instance.database;
    await setTableDirty('cotizaciones');
    
    // Obtener UUID antes de borrar
    String? uuid;
    try {
      final res = await db.query('cotizaciones', columns: ['uuid'], where: 'id = ?', whereArgs: [id]);
      if (res.isNotEmpty) {
        uuid = res.first['uuid']?.toString();
      }
    } catch (e) {
      debugPrint("Error fetching uuid for deletion: $e");
    }

    await _logDeletion('cotizaciones', 'id', 'uuid', id);
    final result = await db.delete('cotizaciones', where: 'id = ?', whereArgs: [id]);
    
    // Eliminar nota de entrega vinculada con el mismo UUID
    if (uuid != null && uuid.isNotEmpty) {
      try {
        final existing = await db.query('notas_entrega', columns: ['id'], where: 'uuid = ?', whereArgs: [uuid]);
        if (existing.isNotEmpty) {
          final notaId = existing.first['id'] as int;
          await _logDeletion('notas_entrega', 'id', 'uuid', notaId);
          await db.delete('notas_entrega', where: 'id = ?', whereArgs: [notaId]);
          debugPrint("Nota de Entrega vinculada eliminada automáticamente.");
        }
      } catch (e) {
        debugPrint("Error eliminando Nota de Entrega vinculada: $e");
      }
    }
    
    return result;
  }

  Future<int> updateCotizacion(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('cotizaciones');
    int id = row['id'];
    final sanitized = await _sanitizeRowForTable(db, 'cotizaciones', row);
    
    // Actualizar cotización
    final result = await db.update('cotizaciones', sanitized, where: 'id = ?', whereArgs: [id]);
    
    // Actualizar nota de entrega vinculada si existe con el mismo UUID
    try {
      final String? uuid = row['uuid']?.toString();
      if (uuid != null && uuid.isNotEmpty) {
        final notaRow = Map<String, dynamic>.from(row);
        notaRow.remove('id');
        final existing = await db.query('notas_entrega', columns: ['id'], where: 'uuid = ?', whereArgs: [uuid]);
        if (existing.isNotEmpty) {
          final notaId = existing.first['id'];
          await db.update('notas_entrega', notaRow, where: 'id = ?', whereArgs: [notaId]);
          debugPrint("Nota de Entrega vinculada actualizada automáticamente.");
        }
      }
    } catch (e) {
      debugPrint("Error actualizando Nota de Entrega vinculada: $e");
    }
    
    return result;
  }

  Future<int> updateCotizacionEstado(int id, String estado) async {
    final db = await instance.database;
    await setTableDirty('cotizaciones');
    return await db.update(
      'cotizaciones',
      {'estado': estado},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // CRUD Proveedores
  Future<int> insertProveedor(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('proveedores');
    return await db.insert('proveedores', row);
  }

  Future<List<Map<String, dynamic>>> queryAllProveedores() async {
    final db = await instance.database;
    return await db.query('proveedores');
  }

  Future<int> updateProveedor(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('proveedores');
    int id = row['id'];
    return await db.update('proveedores', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteProveedor(int id) async {
    final db = await instance.database;
    await setTableDirty('proveedores');
    await _logDeletion('proveedores', 'id', 'folderId', id);
    return await db.delete('proveedores', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD Notas de Entrega
  Future<int> insertNotaEntrega(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('notas_entrega');
    final mutable = Map<String, dynamic>.from(row);
    if (mutable['uuid'] == null || mutable['uuid'].toString().isEmpty) {
      mutable['uuid'] = _generateUUID();
    }
    
    // Guardar nota de entrega
    final sanitized = await _sanitizeRowForTable(db, 'notas_entrega', mutable);
    final id = await db.insert('notas_entrega', sanitized);
    PlanLimitHelper.registerNotaEntregaCreated();
    
    // Crear cotización vinculada automáticamente
    try {
      final cotizacionRow = Map<String, dynamic>.from(mutable);
      cotizacionRow.remove('id');
      final existing = await db.query('cotizaciones', columns: ['id'], where: 'uuid = ?', whereArgs: [mutable['uuid']]);
      if (existing.isEmpty) {
        final sanitizedCot = await _sanitizeRowForTable(db, 'cotizaciones', cotizacionRow);
        await db.insert('cotizaciones', sanitizedCot);
        debugPrint("Cotización vinculada creada automáticamente para Nota de Entrega.");
      }
    } catch (e) {
      debugPrint("Error creando cotización vinculada: $e");
    }
    
    return id;
  }

  Future<List<Map<String, dynamic>>> queryAllNotasEntrega({String? tipoVenta}) async {
    final db = await instance.database;
    if (tipoVenta != null) {
      if (tipoVenta == 'punto_venta') {
        return await db.query('notas_entrega', where: 'tipo_venta = ?', whereArgs: ['punto_venta']);
      } else if (tipoVenta == 'cotizacion' || tipoVenta == 'cotizaciones') {
        return await db.query('notas_entrega', where: "tipo_venta = 'cotizacion' OR tipo_venta = 'cotizaciones' OR tipo_venta IS NULL OR tipo_venta = ''");
      }
      return await db.query('notas_entrega', where: 'tipo_venta = ?', whereArgs: [tipoVenta]);
    }
    return await db.query('notas_entrega');
  }

  Future<int> updateNotaEntrega(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('notas_entrega');
    int id = row['id'];
    
    // Actualizar nota de entrega
    final sanitized = await _sanitizeRowForTable(db, 'notas_entrega', row);
    final result = await db.update('notas_entrega', sanitized, where: 'id = ?', whereArgs: [id]);
    
    // Actualizar cotización vinculada si existe con el mismo UUID
    try {
      final String? uuid = row['uuid']?.toString();
      if (uuid != null && uuid.isNotEmpty) {
        final cotizacionRow = Map<String, dynamic>.from(row);
        cotizacionRow.remove('id');
        final existing = await db.query('cotizaciones', columns: ['id'], where: 'uuid = ?', whereArgs: [uuid]);
        if (existing.isNotEmpty) {
          final cotId = existing.first['id'];
          final sanitizedCot = await _sanitizeRowForTable(db, 'cotizaciones', cotizacionRow);
          await db.update('cotizaciones', sanitizedCot, where: 'id = ?', whereArgs: [cotId]);
          debugPrint("Cotización vinculada actualizada automáticamente.");
        } else {
          // Si por alguna razón no existe (ej. borrado manual anterior), se crea
          final sanitizedCot = await _sanitizeRowForTable(db, 'cotizaciones', cotizacionRow);
          await db.insert('cotizaciones', sanitizedCot);
          debugPrint("Cotización vinculada recreada automáticamente en actualización.");
        }
      }
    } catch (e) {
      debugPrint("Error actualizando cotización vinculada: $e");
    }
    
    return result;
  }

  Future<int> deleteNotaEntrega(int id) async {
    final db = await instance.database;
    await setTableDirty('notas_entrega');
    
    // Obtener UUID antes de borrar
    String? uuid;
    try {
      final res = await db.query('notas_entrega', columns: ['uuid'], where: 'id = ?', whereArgs: [id]);
      if (res.isNotEmpty) {
        uuid = res.first['uuid']?.toString();
      }
    } catch (e) {
      debugPrint("Error fetching uuid for deletion: $e");
    }

    await _logDeletion('notas_entrega', 'id', 'uuid', id);
    final result = await db.delete('notas_entrega', where: 'id = ?', whereArgs: [id]);
    
    // Eliminar cotización vinculada con el mismo UUID
    if (uuid != null && uuid.isNotEmpty) {
      try {
        final existing = await db.query('cotizaciones', columns: ['id'], where: 'uuid = ?', whereArgs: [uuid]);
        if (existing.isNotEmpty) {
          final cotId = existing.first['id'] as int;
          await _logDeletion('cotizaciones', 'id', 'uuid', cotId);
          await db.delete('cotizaciones', where: 'id = ?', whereArgs: [cotId]);
          debugPrint("Cotización vinculada eliminada automáticamente.");
        }
      } catch (e) {
        debugPrint("Error eliminando cotización vinculada: $e");
      }
    }
    
    return result;
  }

  // CRUD Proformas
  Future<int> insertProforma(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('proformas');
    final mutable = Map<String, dynamic>.from(row);
    if (mutable['uuid'] == null || mutable['uuid'].toString().isEmpty) {
      mutable['uuid'] = _generateUUID();
    }
    final sanitized = await _sanitizeRowForTable(db, 'proformas', mutable);
    final id = await db.insert('proformas', sanitized);
    PlanLimitHelper.registerNotaVentaCreated();
    return id;
  }

  Future<List<Map<String, dynamic>>> queryAllProformas({String? tipoVenta}) async {
    final db = await instance.database;
    if (tipoVenta != null) {
      return await db.query('proformas', where: 'tipo_venta = ?', whereArgs: [tipoVenta]);
    }
    return await db.query('proformas', where: "tipo_venta != 'cotizacion' OR tipo_venta IS NULL");
  }

  Future<int> updateProforma(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('proformas');
    int id = row['id'];
    final sanitized = await _sanitizeRowForTable(db, 'proformas', row);
    return await db.update('proformas', sanitized, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateProformaPago(int id, String estadoPago, {String? metodoPago}) async {
    final db = await instance.database;
    await setTableDirty('proformas');
    final Map<String, dynamic> values = {'estado_pago': estadoPago};
    if (metodoPago != null) {
      values['metodo_pago'] = metodoPago;
    }
    return await db.update(
      'proformas',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateProformaComprobado(int id, int comprobado) async {
    final db = await instance.database;
    await setTableDirty('proformas');
    return await db.update(
      'proformas',
      {'comprobado': comprobado},
      where: 'id = ?',
      whereArgs: [id],
    );
  }


  Future<int> deleteProforma(int id) async {
    final db = await instance.database;
    await setTableDirty('proformas');
    await _logDeletion('proformas', 'id', 'uuid', id);
    return await db.delete('proformas', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD Tiendas
  Future<int> insertTienda(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('tiendas');
    return await db.insert('tiendas', row);
  }

  Future<List<Map<String, dynamic>>> queryAllTiendas() async {
    final db = await instance.database;
    return await db.query('tiendas');
  }

  Future<int> updateTienda(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('tiendas');
    int id = row['id'];
    return await db.update('tiendas', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteTienda(int id) async {
    final db = await instance.database;
    await setTableDirty('tiendas');
    await _logDeletion('tiendas', 'id', 'folderId', id);
    return await db.delete('tiendas', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD Sub-ubicaciones
  Future<int> insertSubUbicacion(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('sub_ubicaciones');
    return await db.insert('sub_ubicaciones', row);
  }

  Future<List<Map<String, dynamic>>> queryAllSubUbicaciones() async {
    final db = await instance.database;
    return await db.query('sub_ubicaciones');
  }

  Future<int> updateSubUbicacion(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('sub_ubicaciones');
    int id = row['id'];
    return await db.update('sub_ubicaciones', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteSubUbicacion(int id) async {
    final db = await instance.database;
    await setTableDirty('sub_ubicaciones');
    await _logDeletion('sub_ubicaciones', 'id', 'folderId', id);
    return await db.delete('sub_ubicaciones', where: 'id = ?', whereArgs: [id]);
  }

  // --- MÉTODOS DE EXPORTACIÓN / IMPORTACIÓN PARA NUBE ---
  Future<int?> findMatchingLocalId(String table, Map<String, dynamic> item) async {
    final db = await instance.database;
    final folderId = item['folderId'];
    
    // 1. Intentar buscar por folderId si existe
    if (folderId != null && folderId.toString().isNotEmpty) {
      final res = await db.query(table, where: 'folderId = ?', whereArgs: [folderId]);
      if (res.isNotEmpty) {
        return res.first['id'] as int;
      }
    }
    
    // 2. Si no coincide por folderId, buscar coincidencias por atributos clave
    if (table == 'clientes') {
      final name = item['nombreCompania']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        final res = await db.query('clientes', where: 'LOWER(TRIM(nombreCompania)) = ?', whereArgs: [name.toLowerCase()]);
        if (res.isNotEmpty) {
          return res.first['id'] as int;
        }
      }
    } else if (table == 'tiendas') {
      final name = item['nombre']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        final res = await db.query('tiendas', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [name.toLowerCase()]);
        if (res.isNotEmpty) {
          return res.first['id'] as int;
        }
      }
    } else if (table == 'articulos') {
      final name = item['nombre']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        final res = await db.query('articulos', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [name.toLowerCase()]);
        if (res.isNotEmpty) {
          return res.first['id'] as int;
        }
      }
    } else if (table == 'cotizaciones' || table == 'notas_entrega' || table == 'proformas') {
      final uuid = item['uuid'];
      if (uuid != null && uuid.toString().isNotEmpty) {
        final res = await db.query(table, where: 'uuid = ?', whereArgs: [uuid]);
        if (res.isNotEmpty) {
          return res.first['id'] as int;
        }
      }
      return null;
    } else if (table == 'unidades_medida') {
      final name = item['nombre']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        final res = await db.query('unidades_medida', where: 'LOWER(TRIM(nombre)) = ?', whereArgs: [name.toLowerCase()]);
        if (res.isNotEmpty) {
          return res.first['id'] as int;
        }
      }
    } else if (table == 'sub_ubicaciones') {
      final name = item['nombre']?.toString().trim();
      final storeName = item['tienda_nombre']?.toString().trim();
      if (name != null && name.isNotEmpty && storeName != null) {
        final res = await db.query('sub_ubicaciones', where: 'LOWER(TRIM(nombre)) = ? AND LOWER(TRIM(tienda_nombre)) = ?', whereArgs: [name.toLowerCase(), storeName.toLowerCase()]);
        if (res.isNotEmpty) {
          return res.first['id'] as int;
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> exportAllData() async {
    final db = await instance.database;
    return {
      'clientes': await db.query('clientes'),
      'proveedores': await db.query('proveedores'),
      'cotizaciones': await db.query('cotizaciones'),
      'notas_entrega': await db.query('notas_entrega'),
      'proformas': await db.query('proformas'),
      'tiendas': await db.query('tiendas'),
      'articulos': await db.query('articulos'), // También incluimos artículos locales por seguridad
      'unidades_medida': await db.query('unidades_medida'),
      'sub_ubicaciones': await db.query('sub_ubicaciones'),
    };
  }

  Future<void> importAllData(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final tables = ['clientes', 'proveedores', 'cotizaciones', 'notas_entrega', 'proformas', 'tiendas', 'articulos', 'unidades_medida', 'sub_ubicaciones'];
      
      for (var table in tables) {
        if (data.containsKey(table)) {
          final List<dynamic> rows = data[table];
          for (var row in rows) {
            await txn.insert(
              table, 
              Map<String, dynamic>.from(row),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    });
  }

  Future<void> saveDocumentWithSyncedId(String table, Map<String, dynamic> doc) async {
    final db = await instance.database;
    final incomingUuid = doc['uuid']?.toString();
    final incomingId = doc['id'] as int?;

    if (incomingUuid == null || incomingUuid.isEmpty) {
      if (table == 'cotizaciones') {
        await insertCotizacion(doc);
      } else if (table == 'notas_entrega') {
        await insertNotaEntrega(doc);
      } else if (table == 'proformas') {
        await insertProforma(doc);
      }
      return;
    }

    await db.transaction((txn) async {
      final List<Map<String, dynamic>> byUuid = await txn.query(
        table,
        where: 'uuid = ?',
        whereArgs: [incomingUuid],
        limit: 1,
      );

      if (byUuid.isNotEmpty) {
        final int localId = byUuid.first['id'] as int;
        if (incomingId == null || localId == incomingId) {
          final updatedDoc = Map<String, dynamic>.from(doc);
          updatedDoc['id'] = localId;
          await txn.update(
            table,
            updatedDoc,
            where: 'id = ?',
            whereArgs: [localId],
          );
        } else {
          final List<Map<String, dynamic>> occupied = await txn.query(
            table,
            where: 'id = ?',
            whereArgs: [incomingId],
            limit: 1,
          );

          if (occupied.isNotEmpty) {
            final List<Map<String, dynamic>> maxResult = await txn.rawQuery('SELECT MAX(id) as maxId FROM $table');
            final int nextId = (maxResult.first['maxId'] as int? ?? 0) + 1;
            await txn.rawUpdate(
              'UPDATE $table SET id = ? WHERE id = ?',
              [nextId, incomingId],
            );
          }

          await txn.rawUpdate(
            'UPDATE $table SET id = ? WHERE id = ?',
            [incomingId, localId],
          );

          final updatedDoc = Map<String, dynamic>.from(doc);
          updatedDoc['id'] = incomingId;
          await txn.update(
            table,
            updatedDoc,
            where: 'id = ?',
            whereArgs: [incomingId],
          );
        }
      } else {
        if (incomingId == null) {
          final updatedDoc = Map<String, dynamic>.from(doc);
          updatedDoc.remove('id');
          await txn.insert(table, updatedDoc);
        } else {
          final List<Map<String, dynamic>> occupied = await txn.query(
            table,
            where: 'id = ?',
            whereArgs: [incomingId],
            limit: 1,
          );

          if (occupied.isNotEmpty) {
            final List<Map<String, dynamic>> maxResult = await txn.rawQuery('SELECT MAX(id) as maxId FROM $table');
            final int nextId = (maxResult.first['maxId'] as int? ?? 0) + 1;
            await txn.rawUpdate(
              'UPDATE $table SET id = ? WHERE id = ?',
              [nextId, incomingId],
            );
          }

          await txn.insert(table, doc);
        }
      }
    });
  }

  String generateUUID() => _generateUUID();

  String _generateUUID() {
    final Random random = Random.secure();
    final List<int> values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // version 4
    values[8] = (values[8] & 0x3f) | 0x80; // variant 1
    
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Future<void> clearAllNotasEntrega() async {
    final db = await instance.database;
    await db.delete('notas_entrega');
  }

  // --- UNIDADES DE MEDIDA ---
  Future<List<Map<String, dynamic>>> queryAllUnidadesMedida() async {
    final db = await instance.database;
    return await db.query('unidades_medida', orderBy: 'id ASC');
  }

  Future<int> insertUnidadMedida(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('unidades_medida');
    return await db.insert('unidades_medida', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateUnidadMedida(Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty('unidades_medida');
    int id = row['id'];
    return await db.update('unidades_medida', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteUnidadMedida(int id) async {
    final db = await instance.database;
    await setTableDirty('unidades_medida');
    await _logDeletion('unidades_medida', 'id', 'folderId', id);
    return await db.delete('unidades_medida', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> syncUnidadesMedida(dynamic drive) async {
    try {
      // 1. Subir unidades locales a la nube (las que no tengan folderId asignado)
      final localUnits = await queryAllUnidadesMedida();
      for (var item in localUnits) {
        if (item['folderId'] == null || item['folderId'].toString().isEmpty) {
          final newFolderId = await drive.syncItemToDrive('unidades_medida', Map<String, dynamic>.from(item));
          if (newFolderId != null) {
            final updatedMap = Map<String, dynamic>.from(item);
            updatedMap['folderId'] = newFolderId;
            await updateUnidadMedida(updatedMap);
          }
        }
      }

      // 2. Descargar de la nube
      final cloudUnits = await drive.downloadAllFromTable('unidades_medida');
      for (var item in cloudUnits) {
        final folderId = item['folderId'];
        if (folderId != null) {
          final map = Map<String, dynamic>.from(item);
          final localId = await findMatchingLocalId('unidades_medida', map);
          if (localId != null) {
            map['id'] = localId;
            await updateUnidadMedida(map);
          } else {
            map.remove('id');
            await insertUnidadMedida(map);
          }
        }
      }
    } catch (e) {
      debugPrint("Error al sincronizar unidades de medida en DatabaseHelper: $e");
    }
  }

  // Métodos genéricos para sincronización dinámica
  Future<int> insertRecord(String table, Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty(table);
    if (table == 'articulos') DriveService().clearMemoryCaches();
    return await db.insert(table, row);
  }

  Future<int> updateRecord(String table, Map<String, dynamic> row) async {
    final db = await instance.database;
    await setTableDirty(table);
    if (table == 'articulos') DriveService().clearMemoryCaches();
    int id = row['id'];
    return await db.update(table, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteRecord(String table, int id) async {
    final db = await instance.database;
    await setTableDirty(table);
    if (table == 'articulos') DriveService().clearMemoryCaches();
    final uuidCol = (table == 'cotizaciones' || table == 'notas_entrega' || table == 'proformas') ? 'uuid' : 'folderId';
    await _logDeletion(table, 'id', uuidCol, id);
    return await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> compactAndMoveDocument(String table, int docIdToMove, int targetDisplayId) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      // 1. Obtener todos los registros de la tabla ordenados por ID de forma ascendente
      final List<Map<String, dynamic>> rows = await txn.query(table, orderBy: 'id ASC');
      if (rows.isEmpty) return;

      // 2. Re-escribir temporalmente los IDs con valores negativos consecutivos para evitar violaciones de clave única
      for (int i = 0; i < rows.length; i++) {
        final int currentId = rows[i]['id'] as int;
        await txn.rawUpdate('UPDATE $table SET id = ? WHERE id = ?', [-(i + 1), currentId]);
      }

      // 3. Encontrar la posición original en la lista compactada
      int oldIndex = -1;
      for (int i = 0; i < rows.length; i++) {
        if (rows[i]['id'] == docIdToMove) {
          oldIndex = i;
          break;
        }
      }
      if (oldIndex == -1) return;

      final int targetId = targetDisplayId;
      final int tempIdToMove = -(oldIndex + 1);
      final int currentTempIndexPositiveId = oldIndex + 1;

      // 4. Desplazar los registros intermedios y reasignar IDs positivos definitivos
      if (currentTempIndexPositiveId > targetId) {
        // Mover hacia un ID menor (ej. de 5 a 2)
        // Los registros intermedios en [targetId, currentTempIndexPositiveId - 1] aumentan su ID en 1
        for (int i = 0; i < rows.length; i++) {
          final int tempId = -(i + 1);
          if (tempId == tempIdToMove) continue;

          final int originalPosId = i + 1;
          if (originalPosId >= targetId && originalPosId < currentTempIndexPositiveId) {
            await txn.rawUpdate('UPDATE $table SET id = ? WHERE id = ?', [originalPosId + 1, tempId]);
          } else {
            await txn.rawUpdate('UPDATE $table SET id = ? WHERE id = ?', [originalPosId, tempId]);
          }
        }
      } else if (currentTempIndexPositiveId < targetId) {
        // Mover hacia un ID mayor (ej. de 2 a 5)
        // Los registros intermedios en [currentTempIndexPositiveId + 1, targetId] disminuyen su ID en 1
        for (int i = 0; i < rows.length; i++) {
          final int tempId = -(i + 1);
          if (tempId == tempIdToMove) continue;

          final int originalPosId = i + 1;
          if (originalPosId > currentTempIndexPositiveId && originalPosId <= targetId) {
            await txn.rawUpdate('UPDATE $table SET id = ? WHERE id = ?', [originalPosId - 1, tempId]);
          } else {
            await txn.rawUpdate('UPDATE $table SET id = ? WHERE id = ?', [originalPosId, tempId]);
          }
        }
      } else {
        // No hay cambio de posición, restauramos los IDs compactados ascendentes normales
        for (int i = 0; i < rows.length; i++) {
          final int tempId = -(i + 1);
          await txn.rawUpdate('UPDATE $table SET id = ? WHERE id = ?', [i + 1, tempId]);
        }
      }

      // 5. Asignar el ID destino definitivo al registro que se movió
      await txn.rawUpdate('UPDATE $table SET id = ? WHERE id = ?', [targetId, tempIdToMove]);
    });
  }

  Future<int> updateDocumentPago({
    required String table,
    required int id,
    required double saldoCancelado,
    required String? comprobanteImg,
    required int comprobado,
  }) async {
    final db = await instance.database;
    await setTableDirty(table);
    return await db.update(
      table,
      {
        'saldo_cancelado': saldoCancelado,
        'comprobante_img': comprobanteImg ?? '',
        'comprobado': comprobado,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setTableDirty(String table) async {
    try {
      final tenantKey = await TenantHelper.getActiveTenantKey();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_dirty_${tenantKey}_$table', true);
      debugPrint("Table $table marked as dirty for tenant $tenantKey");
    } catch (e) {
      debugPrint("Error setting table dirty: $e");
    }
  }
}
