class Cliente {
  final int? id;
  final String nombreCompania;
  final String telefono;
  final String correo;

  Cliente({
    this.id,
    required this.nombreCompania,
    required this.telefono,
    required this.correo,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombreCompania': nombreCompania,
      'telefono': telefono,
      'correo': correo,
    };
  }

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      id: map['id'],
      nombreCompania: map['nombreCompania'],
      telefono: map['telefono'] ?? "",
      correo: map['correo'] ?? "",
    );
  }
}
