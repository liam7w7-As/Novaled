import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('novaled.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 8,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE articulos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        precio REAL NOT NULL,
        descripcion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE clientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombreCompania TEXT NOT NULL,
        telefono TEXT,
        correo TEXT
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
        total REAL,
        itemsJson TEXT
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

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
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
    final db = await instance.database;
    return await db.insert('articulos', row);
  }

  Future<List<Map<String, dynamic>>> queryAllArticulos() async {
    final db = await instance.database;
    return await db.query('articulos');
  }

  Future<int> updateArticulo(Map<String, dynamic> row) async {
    final db = await instance.database;
    int id = row['id'];
    return await db.update('articulos', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteArticulo(int id) async {
    final db = await instance.database;
    return await db.delete('articulos', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD Clientes
  Future<int> insertCliente(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('clientes', row);
  }

  Future<List<Map<String, dynamic>>> queryAllClientes() async {
    final db = await instance.database;
    return await db.query('clientes');
  }

  Future<int> updateCliente(Map<String, dynamic> row) async {
    final db = await instance.database;
    int id = row['id'];
    return await db.update('clientes', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCliente(int id) async {
    final db = await instance.database;
    return await db.delete('clientes', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD Cotizaciones
  Future<int> insertCotizacion(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('cotizaciones', row);
  }

  Future<List<Map<String, dynamic>>> queryAllCotizaciones() async {
    final db = await instance.database;
    return await db.query('cotizaciones');
  }

  Future<int> deleteCotizacion(int id) async {
    final db = await instance.database;
    return await db.delete('cotizaciones', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD Proveedores
  Future<int> insertProveedor(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('proveedores', row);
  }

  Future<List<Map<String, dynamic>>> queryAllProveedores() async {
    final db = await instance.database;
    return await db.query('proveedores');
  }

  Future<int> updateProveedor(Map<String, dynamic> row) async {
    final db = await instance.database;
    int id = row['id'];
    return await db.update('proveedores', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteProveedor(int id) async {
    final db = await instance.database;
    return await db.delete('proveedores', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD Notas de Entrega
  Future<int> insertNotaEntrega(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('notas_entrega', row);
  }

  Future<List<Map<String, dynamic>>> queryAllNotasEntrega() async {
    final db = await instance.database;
    return await db.query('notas_entrega');
  }

  // CRUD Proformas
  Future<int> insertProforma(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('proformas', row);
  }

  Future<List<Map<String, dynamic>>> queryAllProformas() async {
    final db = await instance.database;
    return await db.query('proformas');
  }
}
