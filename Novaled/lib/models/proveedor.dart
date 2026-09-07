class Proveedor {
  final int? id;
  final String nombre;
  final String telefono;
  final String correo;
  final String direccion;

  Proveedor({
    this.id,
    required this.nombre,
    required this.telefono,
    required this.correo,
    required this.direccion,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'telefono': telefono,
      'correo': correo,
      'direccion': direccion,
    };
  }

  factory Proveedor.fromMap(Map<String, dynamic> map) {
    return Proveedor(
      id: map['id'],
      nombre: map['nombre'],
      telefono: map['telefono'] ?? "",
      correo: map['correo'] ?? "",
      direccion: map['direccion'] ?? "",
    );
  }
}
