class LogAuditoriaModel {
  final String id;
  final String? empresaId;
  final String? empresaNombre;
  final String usuarioSuperadmin;
  final String accion; // 'CREAR_EMPRESA', 'UPGRADE_PRO', 'SUSPENDER', 'EXTENDER_FECHA', 'ELIMINAR'
  final String descripcion;
  final Map<String, dynamic>? detalles;
  final DateTime fecha;

  LogAuditoriaModel({
    required this.id,
    this.empresaId,
    this.empresaNombre,
    required this.usuarioSuperadmin,
    required this.accion,
    required this.descripcion,
    this.detalles,
    required this.fecha,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'empresaId': empresaId,
      'empresaNombre': empresaNombre,
      'usuarioSuperadmin': usuarioSuperadmin,
      'accion': accion,
      'descripcion': descripcion,
      'detalles': detalles,
      'fecha': fecha.toIso8601String(),
    };
  }

  factory LogAuditoriaModel.fromMap(Map<String, dynamic> map) {
    return LogAuditoriaModel(
      id: map['id'] ?? '',
      empresaId: map['empresaId'],
      empresaNombre: map['empresaNombre'],
      usuarioSuperadmin: map['usuarioSuperadmin'] ?? 'SuperAdmin',
      accion: map['accion'] ?? 'ACCION',
      descripcion: map['descripcion'] ?? '',
      detalles: map['detalles'] != null ? Map<String, dynamic>.from(map['detalles']) : null,
      fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
    );
  }
}
