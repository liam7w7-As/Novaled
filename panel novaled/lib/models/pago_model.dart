class PagoModel {
  final String id;
  final String empresaId;
  final String empresaNombre;
  final double monto;
  final String moneda;
  final String planId;
  final String planNombre;
  final int mesesPagados;
  final String metodoPago; // 'transferencia', 'qr', 'efectivo', 'tarjeta'
  final String referenciaTransaccion;
  final String? comprobanteUrl;
  final DateTime fechaPago;
  final DateTime fechaCoberturaDesde;
  final DateTime fechaCoberturaHasta;
  final String registradoPor;

  PagoModel({
    required this.id,
    required this.empresaId,
    required this.empresaNombre,
    required this.monto,
    this.moneda = 'Bs',
    required this.planId,
    required this.planNombre,
    required this.mesesPagados,
    required this.metodoPago,
    required this.referenciaTransaccion,
    this.comprobanteUrl,
    required this.fechaPago,
    required this.fechaCoberturaDesde,
    required this.fechaCoberturaHasta,
    required this.registradoPor,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'empresaId': empresaId,
      'empresaNombre': empresaNombre,
      'monto': monto,
      'moneda': moneda,
      'planId': planId,
      'planNombre': planNombre,
      'mesesPagados': mesesPagados,
      'metodoPago': metodoPago,
      'referenciaTransaccion': referenciaTransaccion,
      'comprobanteUrl': comprobanteUrl,
      'fechaPago': fechaPago.toIso8601String(),
      'fechaCoberturaDesde': fechaCoberturaDesde.toIso8601String(),
      'fechaCoberturaHasta': fechaCoberturaHasta.toIso8601String(),
      'registradoPor': registradoPor,
    };
  }

  factory PagoModel.fromMap(Map<String, dynamic> map) {
    return PagoModel(
      id: map['id'] ?? '',
      empresaId: map['empresaId'] ?? '',
      empresaNombre: map['empresaNombre'] ?? '',
      monto: (map['monto'] as num?)?.toDouble() ?? 0.0,
      moneda: map['moneda'] ?? 'Bs',
      planId: map['planId'] ?? 'pro_mensual',
      planNombre: map['planNombre'] ?? 'Plan PRO',
      mesesPagados: map['mesesPagados'] ?? 1,
      metodoPago: map['metodoPago'] ?? 'Transferencia Bancaria',
      referenciaTransaccion: map['referenciaTransaccion'] ?? '',
      comprobanteUrl: map['comprobanteUrl'],
      fechaPago: DateTime.tryParse(map['fechaPago'] ?? '') ?? DateTime.now(),
      fechaCoberturaDesde: DateTime.tryParse(map['fechaCoberturaDesde'] ?? '') ?? DateTime.now(),
      fechaCoberturaHasta: DateTime.tryParse(map['fechaCoberturaHasta'] ?? '') ?? DateTime.now().add(const Duration(days: 30)),
      registradoPor: map['registradoPor'] ?? 'SuperAdmin',
    );
  }
}
