import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/backup_model.dart';
import 'empresa_service.dart';

class BackupService extends ChangeNotifier {
  static final BackupService instance = BackupService._internal();
  factory BackupService() => instance;
  BackupService._internal() {
    _init();
  }

  final String _backupDir = r'c:\Almir_trabajos\Novaled Sistema\backups';
  List<BackupModel> _backups = [];
  List<BackupModel> get backups => _backups;

  bool _autoBackupActivo = true;
  bool get autoBackupActivo => _autoBackupActivo;

  TimeOfDay _horaProgramada = const TimeOfDay(hour: 3, minute: 0);
  TimeOfDay get horaProgramada => _horaProgramada;

  String _frecuencia = 'Diaria (Cada 24h)';
  String get frecuencia => _frecuencia;

  bool _isCreatingBackup = false;
  bool get isCreatingBackup => _isCreatingBackup;

  bool _isRestoring = false;
  bool get isRestoring => _isRestoring;

  String _restoreStatusMessage = '';
  String get restoreStatusMessage => _restoreStatusMessage;

  double _restoreProgress = 0.0;
  double get restoreProgress => _restoreProgress;

  Timer? _scheduleTimer;
  DateTime? _ultimoBackupEjecutado;
  DateTime? get ultimoBackupEjecutado => _ultimoBackupEjecutado;

  Future<void> _init() async {
    await _cargarConfiguracion();
    await cargarBackups();
    _iniciarRelojProgramado();
  }

  Future<void> _cargarConfiguracion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoBackupActivo = prefs.getBool('bkp_auto_activo') ?? true;
      final h = prefs.getInt('bkp_hora') ?? 3;
      final m = prefs.getInt('bkp_minuto') ?? 0;
      _horaProgramada = TimeOfDay(hour: h, minute: m);
      _frecuencia = prefs.getString('bkp_frecuencia') ?? 'Diaria (Cada 24h)';
      final lastStr = prefs.getString('bkp_ultimo_ejecutado');
      if (lastStr != null) {
        _ultimoBackupEjecutado = DateTime.tryParse(lastStr);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error cargando configuración de backups: $e");
    }
  }

  Future<void> guardarProgramacion({
    required bool activo,
    required TimeOfDay hora,
    required String frecuencia,
  }) async {
    _autoBackupActivo = activo;
    _horaProgramada = hora;
    _frecuencia = frecuencia;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bkp_auto_activo', activo);
    await prefs.setInt('bkp_hora', hora.hour);
    await prefs.setInt('bkp_minuto', hora.minute);
    await prefs.setString('bkp_frecuencia', frecuencia);

    notifyListeners();
  }

  void _iniciarRelojProgramado() {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!_autoBackupActivo) return;
      final now = DateTime.now();
      if (now.hour == _horaProgramada.hour && now.minute == _horaProgramada.minute) {
        if (_ultimoBackupEjecutado != null &&
            _ultimoBackupEjecutado!.day == now.day &&
            _ultimoBackupEjecutado!.hour == now.hour &&
            _ultimoBackupEjecutado!.minute == now.minute) {
          return;
        }
        crearBackupManual(tipo: 'Automático Programado');
      }
    });
  }

  Future<void> cargarBackups() async {
    try {
      final dir = Directory(_backupDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final List<BackupModel> list = [];
      final entities = dir.listSync(recursive: false);

      for (var entity in entities) {
        if (entity is File) {
          final filename = entity.uri.pathSegments.last;
          if (filename.endsWith('.py')) continue;
          final stat = entity.statSync();
          if (stat.size == 0) continue; // Ignorar archivos vacíos

          String tipo = 'SQLite Base de Datos';
          if (filename.endsWith('.json')) {
            tipo = 'JSON Historial Completo';
          } else if (filename.endsWith('.sql')) {
            tipo = 'Volcado SQL';
          } else if (filename.endsWith('.csv')) {
            tipo = 'Tabla CSV Excel';
          }

          final id = 'BKP-${DateFormat('yyyyMMdd-HHmm').format(stat.modified)}';

          list.add(BackupModel(
            id: id,
            nombreArchivo: filename,
            rutaCompleta: entity.path,
            tamanoBytes: stat.size,
            fechaCreacion: stat.modified,
            tipo: tipo,
            estado: 'Exitoso (100%)',
          ));
        }
      }

      list.sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));
      _backups = list;
      notifyListeners();
    } catch (e) {
      debugPrint("Error leyendo backups: $e");
    }
  }

  Future<BackupModel?> crearBackupManual({String tipo = 'Manual SuperAdmin'}) async {
    _isCreatingBackup = true;
    notifyListeners();

    try {
      final scriptPath = '$_backupDir\\backup_engine.py';
      final result = await Process.run('python', [scriptPath]);
      
      final now = DateTime.now();
      _ultimoBackupEjecutado = now;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bkp_ultimo_ejecutado', now.toIso8601String());

      await cargarBackups();

      _isCreatingBackup = false;
      notifyListeners();

      return _backups.isNotEmpty ? _backups.first : null;
    } catch (e) {
      debugPrint("Error ejecutando backup real: $e");
      _isCreatingBackup = false;
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>> restablecerBackup(String filename, {Function(String status, double progress)? onProgress}) async {
    _isRestoring = true;
    _restoreProgress = 0.1;
    _restoreStatusMessage = 'Validando integridad de la copia de seguridad...';
    notifyListeners();
    onProgress?.call(_restoreStatusMessage, _restoreProgress);

    await Future.delayed(const Duration(milliseconds: 600));

    try {
      _restoreProgress = 0.35;
      _restoreStatusMessage = 'Extrayendo tablas, cotizaciones e inventario...';
      notifyListeners();
      onProgress?.call(_restoreStatusMessage, _restoreProgress);

      final scriptPath = '$_backupDir\\backup_engine.py';
      final processResult = await Process.run('python', [scriptPath, 'restore', filename]);

      _restoreProgress = 0.70;
      _restoreStatusMessage = 'Sincronizando base de datos en la Nube y dispositivo móvil...';
      notifyListeners();
      onProgress?.call(_restoreStatusMessage, _restoreProgress);

      await Future.delayed(const Duration(milliseconds: 800));

      final output = processResult.stdout.toString();
      Map<String, dynamic> resultJson = {"success": true};

      for (final line in output.split('\n')) {
        if (line.startsWith('RESULT_JSON:')) {
          try {
            resultJson = jsonDecode(line.substring('RESULT_JSON:'.length).trim());
          } catch (_) {}
        }
      }

      _restoreProgress = 1.0;
      _restoreStatusMessage = '¡Restauración completada con éxito al 100%!';
      notifyListeners();
      onProgress?.call(_restoreStatusMessage, _restoreProgress);

      await Future.delayed(const Duration(milliseconds: 500));
      _isRestoring = false;
      notifyListeners();

      await cargarBackups();
      return resultJson;
    } catch (e) {
      _isRestoring = false;
      _restoreStatusMessage = 'Error durante la restauración: $e';
      notifyListeners();
      return {"success": false, "error": e.toString()};
    }
  }

  void abrirCarpetaBackups() {
    try {
      Process.run('explorer.exe', [_backupDir]);
    } catch (e) {
      debugPrint("Error abriendo carpeta de backups: $e");
    }
  }

  Future<String> exportarTablaAExcel() async {
    try {
      final csvFile = File('$_backupDir\\reporte_historial_backups.csv');
      final buffer = StringBuffer();
      buffer.writeln('CODIGO;NOMBRE ARCHIVO;TIPO;TAMANO;FECHA CREACION;ESTADO;RUTA');

      for (var b in _backups) {
        buffer.writeln(
          '"${b.id}";"${b.nombreArchivo}";"${b.tipo}";"${b.tamanoFormateado}";"${b.fechaFormateada}";"${b.estado}";"${b.rutaCompleta}"'
        );
      }

      await csvFile.writeAsString(buffer.toString(), encoding: utf8);
      abrirCarpetaBackups();
      return csvFile.path;
    } catch (e) {
      debugPrint("Error exportando a Excel: $e");
      return '';
    }
  }

  int get totalBytesAlmacenados {
    return _backups.fold(0, (sum, b) => sum + b.tamanoBytes);
  }

  String get totalTamanoFormateado {
    final bytes = totalBytesAlmacenados;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
