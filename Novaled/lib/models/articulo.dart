class Articulo {
  final int? id;
  final String nombre;
  final double precio;
  final String descripcion;

  Articulo({
    this.id,
    required this.nombre,
    required this.precio,
    required this.descripcion,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'precio': precio,
      'descripcion': descripcion,
    };
  }

  factory Articulo.fromMap(Map<String, dynamic> map) {
    return Articulo(
      id: map['id'],
      nombre: map['nombre'],
      precio: map['precio'],
      descripcion: map['descripcion'] ?? "",
    );
  }
}
