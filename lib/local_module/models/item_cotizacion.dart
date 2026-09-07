import 'articulo.dart';

class ItemCotizacion {
  static int _counter = 0;

  final Articulo articulo;
  final double precioOriginal;
  int cantidad;
  final String uniqueId;

  ItemCotizacion({
    required this.articulo,
    required this.precioOriginal,
    this.cantidad = 1,
    String? uniqueId,
  }) : uniqueId = uniqueId ?? "item_${_counter++}_${DateTime.now().microsecondsSinceEpoch}";

  double get total => articulo.precio * cantidad;
  double get totalOriginal => (precioOriginal > 0 ? precioOriginal : articulo.precio) * cantidad;
  double get ahorro => totalOriginal - total;

  ItemCotizacion copyWith({
    Articulo? articulo,
    double? precioOriginal,
    int? cantidad,
    String? uniqueId,
  }) {
    return ItemCotizacion(
      articulo: articulo ?? this.articulo,
      precioOriginal: precioOriginal ?? this.precioOriginal,
      cantidad: cantidad ?? this.cantidad,
      uniqueId: uniqueId ?? this.uniqueId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'articulo': articulo.toMap(),
      'precioOriginal': precioOriginal,
      'cantidad': cantidad,
    };
  }

  factory ItemCotizacion.fromMap(Map<String, dynamic> map) {
    return ItemCotizacion(
      articulo: Articulo.fromMap(map['articulo']),
      precioOriginal: (map['precioOriginal'] as num?)?.toDouble() ?? (Articulo.fromMap(map['articulo']).precio),
      cantidad: map['cantidad'],
    );
  }
}
