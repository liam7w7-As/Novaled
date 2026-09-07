import 'articulo.dart';

class ItemCotizacion {
  final Articulo articulo;
  int cantidad;

  ItemCotizacion({
    required this.articulo,
    this.cantidad = 1,
  });

  double get total => articulo.precio * cantidad;

  Map<String, dynamic> toMap() {
    return {
      'articulo': articulo.toMap(),
      'cantidad': cantidad,
    };
  }

  factory ItemCotizacion.fromMap(Map<String, dynamic> map) {
    return ItemCotizacion(
      articulo: Articulo.fromMap(map['articulo']),
      cantidad: map['cantidad'],
    );
  }
}
