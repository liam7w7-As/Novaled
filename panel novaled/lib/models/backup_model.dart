class BackupModel {
  final String id;
  final String nombreArchivo;
  final String rutaCompleta;
  final int tamanoBytes;
  final DateTime fechaCreacion;
  final String tipo; // 'SQLite Base de Datos', 'JSON Historial', 'Excel CSV', 'Volcado SQL'
  final String estado; // 'Exitoso', 'Completado'

  BackupModel({
    required this.id,
    required this.nombreArchivo,
    required this.rutaCompleta,
    required this.tamanoBytes,
    required this.fechaCreacion,
    required this.tipo,
    this.estado = 'Exitoso',
  });

  String get tamanoFormateado {
    if (tamanoBytes < 1024) return '$tamanoBytes B';
    if (tamanoBytes < 1024 * 1024) return '${(tamanoBytes / 1024).toStringAsFixed(1)} KB';
    return '${(tamanoBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get fechaFormateada {
    final y = fechaCreacion.year.toString().padLeft(4, '0');
    final m = fechaCreacion.month.toString().padLeft(2, '0');
    final d = fechaCreacion.day.toString().padLeft(2, '0');
    final h = fechaCreacion.hour.toString().padLeft(2, '0');
    final min = fechaCreacion.minute.toString().padLeft(2, '0');
    final s = fechaCreacion.second.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min:$s';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombreArchivo': nombreArchivo,
      'rutaCompleta': rutaCompleta,
      'tamanoBytes': tamanoBytes,
      'fechaCreacion': fechaCreacion.toIso8601String(),
      'tipo': tipo,
      'estado': estado,
    };
  }

  factory BackupModel.fromMap(Map<String, dynamic> map) {
    return BackupModel(
      id: map['id'] ?? '',
      nombreArchivo: map['nombreArchivo'] ?? '',
      rutaCompleta: map['rutaCompleta'] ?? '',
      tamanoBytes: (map['tamanoBytes'] as num?)?.toInt() ?? 0,
      fechaCreacion: DateTime.tryParse(map['fechaCreacion'] ?? '') ?? DateTime.now(),
      tipo: map['tipo'] ?? 'SQLite Base de Datos',
      estado: map['estado'] ?? 'Exitoso',
    );
  }
}
