class Tienda {
  final int? id;
  final String nombre;
  final String ubicacion;
  final String? folderId;

  Tienda({this.id, required this.nombre, this.ubicacion = '', this.folderId});

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nombre': nombre,
      'ubicacion': ubicacion,
      'folderId': folderId,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory Tienda.fromMap(Map<String, dynamic> map) {
    return Tienda(
      id: map['id'],
      nombre: map['nombre'] ?? '',
      ubicacion: map['ubicacion'] ?? '',
      folderId: map['folderId'],
    );
  }

  Tienda copyWith({
    int? id,
    String? nombre,
    String? ubicacion,
    String? folderId,
  }) {
    return Tienda(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      ubicacion: ubicacion ?? this.ubicacion,
      folderId: folderId ?? this.folderId,
    );
  }
}
