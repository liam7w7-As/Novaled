class PlanModel {
  final String id;
  final String nombre;
  final double precio;
  final String moneda;
  final String descripcion;

  // Límites por categoría
  final int limiteCotizaciones; // -1 para ilimitado
  final int limiteNotasVenta; // -1 para ilimitado (Punto de venta)
  final int limiteNotasEntrega; // -1 para ilimitado
  final int limiteEscaneosMagicos; // -1 para ilimitado
  final int limiteUsuarios; // -1 para ilimitado

  // Características
  final bool permiteInfoLogo;
  final bool permiteModoEdicion;
  final bool permitePaletaColores;
  final bool permiteSincronizacionNube;
  final bool activo;

  PlanModel({
    required this.id,
    required this.nombre,
    required this.precio,
    this.moneda = 'Bs.',
    this.descripcion = '',
    required this.limiteCotizaciones,
    required this.limiteNotasVenta,
    required this.limiteNotasEntrega,
    required this.limiteEscaneosMagicos,
    required this.limiteUsuarios,
    this.permiteInfoLogo = true,
    this.permiteModoEdicion = false,
    this.permitePaletaColores = false,
    this.permiteSincronizacionNube = true,
    this.activo = true,
  });

  bool get esIlimitadoCotizaciones => limiteCotizaciones == -1;
  bool get esIlimitadoNotasVenta => limiteNotasVenta == -1;
  bool get esIlimitadoNotasEntrega => limiteNotasEntrega == -1;
  bool get esIlimitadoEscaneos => limiteEscaneosMagicos == -1;
  bool get esIlimitadoUsuarios => limiteUsuarios == -1 || limiteUsuarios >= 999;
  bool get esIlimitadoDocs => esIlimitadoCotizaciones && esIlimitadoNotasVenta && esIlimitadoNotasEntrega;

  int get limiteDocumentosMes {
    if (esIlimitadoDocs) return -1;
    return (limiteCotizaciones > 0 ? limiteCotizaciones : 0) +
        (limiteNotasVenta > 0 ? limiteNotasVenta : 0) +
        (limiteNotasEntrega > 0 ? limiteNotasEntrega : 0);
  }

  bool get esFree => id == 'free' || id == 'gratis';
  bool get esPro => id == 'pro' || id == 'pro_mensual';
  bool get esPlus => id == 'plus' || id == 'pro_anual';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'precio': precio,
      'moneda': moneda,
      'descripcion': descripcion,
      'limiteCotizaciones': limiteCotizaciones,
      'limiteNotasVenta': limiteNotasVenta,
      'limiteNotasEntrega': limiteNotasEntrega,
      'limiteEscaneosMagicos': limiteEscaneosMagicos,
      'limiteUsuarios': limiteUsuarios,
      'permiteInfoLogo': permiteInfoLogo,
      'permiteModoEdicion': permiteModoEdicion,
      'permitePaletaColores': permitePaletaColores,
      'permiteSincronizacionNube': permiteSincronizacionNube,
      'activo': activo,
    };
  }

  factory PlanModel.fromMap(Map<String, dynamic> map) {
    return PlanModel(
      id: map['id'] ?? 'free',
      nombre: map['nombre'] ?? 'Gratis',
      precio: (map['precio'] as num?)?.toDouble() ?? 0.0,
      moneda: map['moneda'] ?? 'Bs.',
      descripcion: map['descripcion'] ?? '',
      limiteCotizaciones: map['limiteCotizaciones'] ?? (map['id'] == 'free' ? 5 : -1),
      limiteNotasVenta: map['limiteNotasVenta'] ?? (map['id'] == 'free' ? 5 : -1),
      limiteNotasEntrega: map['limiteNotasEntrega'] ?? (map['id'] == 'free' ? 5 : -1),
      limiteEscaneosMagicos: map['limiteEscaneosMagicos'] ?? (map['id'] == 'free' ? 5 : (map['id'] == 'pro' ? 50 : 200)),
      limiteUsuarios: map['limiteUsuarios'] ?? (map['id'] == 'free' ? 2 : (map['id'] == 'pro' ? 6 : -1)),
      permiteInfoLogo: map['permiteInfoLogo'] ?? true,
      permiteModoEdicion: map['permiteModoEdicion'] ?? (map['id'] != 'free'),
      permitePaletaColores: map['permitePaletaColores'] ?? (map['id'] != 'free'),
      permiteSincronizacionNube: map['permiteSincronizacionNube'] ?? true,
      activo: map['activo'] == true || map['activo'] == 1,
    );
  }

  // Plan 1: Gratis (Bs. 0)
  static PlanModel get planFreeDefault => PlanModel(
        id: 'free',
        nombre: 'Gratis',
        precio: 0.0,
        moneda: 'Bs.',
        descripcion: 'Para comenzar y probar Novaled.',
        limiteCotizaciones: 5,
        limiteNotasVenta: 5,
        limiteNotasEntrega: 5,
        limiteEscaneosMagicos: 5,
        limiteUsuarios: 2,
        permiteInfoLogo: true,
        permiteModoEdicion: false,
        permitePaletaColores: false,
        permiteSincronizacionNube: true,
        activo: true,
      );

  // Plan 2: Pro (Bs. 95 / mes) - Más popular
  static PlanModel get planProDefault => PlanModel(
        id: 'pro',
        nombre: 'Pro',
        precio: 95.0,
        moneda: 'Bs.',
        descripcion: 'Para negocios que venden todos los días.',
        limiteCotizaciones: -1, // ilimitado
        limiteNotasVenta: -1, // ilimitado
        limiteNotasEntrega: -1, // ilimitado
        limiteEscaneosMagicos: 50,
        limiteUsuarios: 6,
        permiteInfoLogo: true,
        permiteModoEdicion: true,
        permitePaletaColores: true,
        permiteSincronizacionNube: true,
        activo: true,
      );

  // Plan 3: Plus (Bs. 170 / mes)
  static PlanModel get planPlusDefault => PlanModel(
        id: 'plus',
        nombre: 'Plus',
        precio: 170.0,
        moneda: 'Bs.',
        descripcion: 'Para negocios con mayor volumen y equipos.',
        limiteCotizaciones: -1, // ilimitado
        limiteNotasVenta: -1, // ilimitado
        limiteNotasEntrega: -1, // ilimitado
        limiteEscaneosMagicos: 200,
        limiteUsuarios: -1, // ilimitados
        permiteInfoLogo: true,
        permiteModoEdicion: true,
        permitePaletaColores: true,
        permiteSincronizacionNube: true,
        activo: true,
      );
}
