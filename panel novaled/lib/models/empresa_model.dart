class EmpresaModel {
  final String id;
  final String codigoEmpresa;
  final String nombreComercial;
  final String razonSocial;
  final String nitRut;
  final String telefono;
  final String emailContacto;
  final String direccionPrincipal;
  final String ciudad;
  final String pais;
  final String monedaSimbolo;

  // Plan y Suscripción
  final String planId; // 'free', 'pro_mensual', 'pro_anual'
  final String estado; // 'activo_free', 'trial_pro', 'activo_pro', 'por_vencer', 'gracia', 'suspendido', 'eliminado'

  // Fechas Clave
  final DateTime fechaRegistro;
  final DateTime fechaInicioPlan;
  final DateTime? fechaVencimiento;
  final int diasGracia;
  final DateTime? ultimaActividad;

  // Métricas de Consumo en Tiempo Real
  final int documentosMesActual;
  final int totalCotizaciones;
  final int totalNotasVenta;
  final int totalNotasEntrega;
  final int totalProformas;
  final int totalPuntoVenta;
  final int totalEscaneos;
  final int sucursalesActivas;
  final int usuariosActivos;
  final int articulosCreados;

  // Configuraciones & Personalización
  final String? logoUrl;
  final String colorMarca;
  final String notasAdmin;
  final DateTime? eliminadoEn;

  EmpresaModel({
    required this.id,
    required this.codigoEmpresa,
    required this.nombreComercial,
    this.razonSocial = '',
    this.nitRut = '',
    this.telefono = '',
    required this.emailContacto,
    this.direccionPrincipal = '',
    this.ciudad = 'La Paz',
    this.pais = 'Bolivia',
    this.monedaSimbolo = 'Bs.',
    required this.planId,
    this.estado = 'activo_free',
    required this.fechaRegistro,
    required this.fechaInicioPlan,
    this.fechaVencimiento,
    this.diasGracia = 5,
    this.ultimaActividad,
    this.documentosMesActual = 0,
    this.totalCotizaciones = 0,
    this.totalNotasVenta = 0,
    this.totalNotasEntrega = 0,
    this.totalProformas = 0,
    this.totalPuntoVenta = 0,
    this.totalEscaneos = 0,
    this.sucursalesActivas = 1,
    this.usuariosActivos = 1,
    this.articulosCreados = 0,
    this.logoUrl,
    this.colorMarca = '#F5C842',
    this.notasAdmin = '',
    this.eliminadoEn,
  });

  bool get esFree => planId == 'free';
  bool get esPro => planId.startsWith('pro');
  bool get esTrial => estado == 'trial_pro';
  bool get estaSuspendido => estado == 'suspendido';
  bool get estaEliminado => eliminadoEn != null || estado == 'eliminado';

  int get diasRestantes {
    if (fechaVencimiento == null) return 999;
    final now = DateTime.now();
    return fechaVencimiento!.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  int get diasRestantesPapelera {
    if (eliminadoEn == null) return 30;
    final diff = DateTime.now().difference(eliminadoEn!).inDays;
    final restantes = 30 - diff;
    return restantes < 0 ? 0 : restantes;
  }

  bool get estaPorVencer {
    if (fechaVencimiento == null) return false;
    final diff = diasRestantes;
    return diff >= 0 && diff <= 5 && !estaSuspendido;
  }

  bool get estaVencido {
    if (fechaVencimiento == null) return false;
    return diasRestantes < 0;
  }

  String get estadoLabel {
    switch (estado) {
      case 'activo_free':
        return 'Activo (Free)';
      case 'trial_pro':
        return 'Trial PRO ($diasRestantes d)';
      case 'activo_pro':
        return 'Activo (PRO)';
      case 'por_vencer':
        return 'Por Vencer ($diasRestantes d)';
      case 'gracia':
        return 'Periodo Gracia';
      case 'suspendido':
        return 'Suspendido';
      case 'eliminado':
        return 'Eliminado';
      default:
        return estado.toUpperCase();
    }
  }

  EmpresaModel copyWith({
    String? id,
    String? codigoEmpresa,
    String? nombreComercial,
    String? razonSocial,
    String? nitRut,
    String? telefono,
    String? emailContacto,
    String? direccionPrincipal,
    String? ciudad,
    String? pais,
    String? monedaSimbolo,
    String? planId,
    String? estado,
    DateTime? fechaRegistro,
    DateTime? fechaInicioPlan,
    DateTime? fechaVencimiento,
    int? diasGracia,
    DateTime? ultimaActividad,
    int? documentosMesActual,
    int? totalCotizaciones,
    int? totalNotasVenta,
    int? totalNotasEntrega,
    int? totalProformas,
    int? totalPuntoVenta,
    int? totalEscaneos,
    int? sucursalesActivas,
    int? usuariosActivos,
    int? articulosCreados,
    String? logoUrl,
    String? colorMarca,
    String? notasAdmin,
    DateTime? eliminadoEn,
  }) {
    return EmpresaModel(
      id: id ?? this.id,
      codigoEmpresa: codigoEmpresa ?? this.codigoEmpresa,
      nombreComercial: nombreComercial ?? this.nombreComercial,
      razonSocial: razonSocial ?? this.razonSocial,
      nitRut: nitRut ?? this.nitRut,
      telefono: telefono ?? this.telefono,
      emailContacto: emailContacto ?? this.emailContacto,
      direccionPrincipal: direccionPrincipal ?? this.direccionPrincipal,
      ciudad: ciudad ?? this.ciudad,
      pais: pais ?? this.pais,
      monedaSimbolo: monedaSimbolo ?? this.monedaSimbolo,
      planId: planId ?? this.planId,
      estado: estado ?? this.estado,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
      fechaInicioPlan: fechaInicioPlan ?? this.fechaInicioPlan,
      fechaVencimiento: fechaVencimiento ?? this.fechaVencimiento,
      diasGracia: diasGracia ?? this.diasGracia,
      ultimaActividad: ultimaActividad ?? this.ultimaActividad,
      documentosMesActual: documentosMesActual ?? this.documentosMesActual,
      totalCotizaciones: totalCotizaciones ?? this.totalCotizaciones,
      totalNotasVenta: totalNotasVenta ?? this.totalNotasVenta,
      totalNotasEntrega: totalNotasEntrega ?? this.totalNotasEntrega,
      totalProformas: totalProformas ?? this.totalProformas,
      totalPuntoVenta: totalPuntoVenta ?? this.totalPuntoVenta,
      totalEscaneos: totalEscaneos ?? this.totalEscaneos,
      sucursalesActivas: sucursalesActivas ?? this.sucursalesActivas,
      usuariosActivos: usuariosActivos ?? this.usuariosActivos,
      articulosCreados: articulosCreados ?? this.articulosCreados,
      logoUrl: logoUrl ?? this.logoUrl,
      colorMarca: colorMarca ?? this.colorMarca,
      notasAdmin: notasAdmin ?? this.notasAdmin,
      eliminadoEn: eliminadoEn ?? this.eliminadoEn,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigoEmpresa': codigoEmpresa,
      'nombreComercial': nombreComercial,
      'razonSocial': razonSocial,
      'nitRut': nitRut,
      'telefono': telefono,
      'emailContacto': emailContacto,
      'direccionPrincipal': direccionPrincipal,
      'ciudad': ciudad,
      'pais': pais,
      'monedaSimbolo': monedaSimbolo,
      'planId': planId,
      'estado': estado,
      'fechaRegistro': fechaRegistro.toIso8601String(),
      'fechaInicioPlan': fechaInicioPlan.toIso8601String(),
      'fechaVencimiento': fechaVencimiento?.toIso8601String(),
      'diasGracia': diasGracia,
      'ultimaActividad': ultimaActividad?.toIso8601String(),
      'documentosMesActual': documentosMesActual,
      'totalCotizaciones': totalCotizaciones,
      'totalNotasVenta': totalNotasVenta,
      'totalNotasEntrega': totalNotasEntrega,
      'totalProformas': totalProformas,
      'totalPuntoVenta': totalPuntoVenta,
      'totalEscaneos': totalEscaneos,
      'sucursalesActivas': sucursalesActivas,
      'usuariosActivos': usuariosActivos,
      'articulosCreados': articulosCreados,
      'logoUrl': logoUrl,
      'colorMarca': colorMarca,
      'notasAdmin': notasAdmin,
      'eliminadoEn': eliminadoEn?.toIso8601String(),
    };
  }

  factory EmpresaModel.fromMap(Map<String, dynamic> map) {
    return EmpresaModel(
      id: map['id'] ?? '',
      codigoEmpresa: map['codigoEmpresa'] ?? 'NOV-000',
      nombreComercial: map['nombreComercial'] ?? '',
      razonSocial: map['razonSocial'] ?? '',
      nitRut: map['nitRut'] ?? '',
      telefono: map['telefono'] ?? '',
      emailContacto: map['emailContacto'] ?? '',
      direccionPrincipal: map['direccionPrincipal'] ?? '',
      ciudad: map['ciudad'] ?? 'La Paz',
      pais: map['pais'] ?? 'Bolivia',
      monedaSimbolo: map['monedaSimbolo'] ?? 'Bs.',
      planId: map['planId'] ?? 'free',
      estado: map['estado'] ?? 'activo_free',
      fechaRegistro: DateTime.tryParse(map['fechaRegistro'] ?? '') ?? DateTime.now(),
      fechaInicioPlan: DateTime.tryParse(map['fechaInicioPlan'] ?? '') ?? DateTime.now(),
      fechaVencimiento: map['fechaVencimiento'] != null ? DateTime.tryParse(map['fechaVencimiento']) : null,
      diasGracia: map['diasGracia'] ?? 5,
      ultimaActividad: map['ultimaActividad'] != null ? DateTime.tryParse(map['ultimaActividad']) : null,
      documentosMesActual: map['documentosMesActual'] ?? 0,
      totalCotizaciones: map['totalCotizaciones'] ?? 0,
      totalNotasVenta: map['totalNotasVenta'] ?? 0,
      totalNotasEntrega: map['totalNotasEntrega'] ?? 0,
      totalProformas: map['totalProformas'] ?? 0,
      totalPuntoVenta: map['totalPuntoVenta'] ?? 0,
      totalEscaneos: map['totalEscaneos'] ?? 0,
      sucursalesActivas: map['sucursalesActivas'] ?? 1,
      usuariosActivos: map['usuariosActivos'] ?? 1,
      articulosCreados: map['articulosCreados'] ?? 0,
      logoUrl: map['logoUrl'],
      colorMarca: map['colorMarca'] ?? '#F5C842',
      notasAdmin: map['notasAdmin'] ?? '',
      eliminadoEn: map['eliminadoEn'] != null ? DateTime.tryParse(map['eliminadoEn']) : null,
    );
  }
}
