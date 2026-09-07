class Cliente {
  final int? id;
  final String nombreCompania;
  final String telefono;
  final String correo;
  final String rn;
  final String direccion1;
  final String direccion2;
  final String direccion3;
  final String direccionEnvio1;
  final String direccionEnvio2;
  final String direccionEnvio3;
  final String infoAdicional;
  final String? folderId;

  Cliente({
    this.id,
    required this.nombreCompania,
    required this.telefono,
    required this.correo,
    this.rn = "",
    this.direccion1 = "",
    this.direccion2 = "",
    this.direccion3 = "",
    this.direccionEnvio1 = "",
    this.direccionEnvio2 = "",
    this.direccionEnvio3 = "",
    this.infoAdicional = "",
    this.folderId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombreCompania': nombreCompania,
      'telefono': telefono,
      'correo': correo,
      'rn': rn,
      'direccion1': direccion1,
      'direccion2': direccion2,
      'direccion3': direccion3,
      'direccionEnvio1': direccionEnvio1,
      'direccionEnvio2': direccionEnvio2,
      'direccionEnvio3': direccionEnvio3,
      'infoAdicional': infoAdicional,
      'folderId': folderId,
    };
  }

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      id: map['id'],
      nombreCompania: map['nombreCompania'] ?? "",
      telefono: map['telefono'] ?? "",
      correo: map['correo'] ?? "",
      rn: map['rn'] ?? "",
      direccion1: map['direccion1'] ?? "",
      direccion2: map['direccion2'] ?? "",
      direccion3: map['direccion3'] ?? "",
      direccionEnvio1: map['direccionEnvio1'] ?? "",
      direccionEnvio2: map['direccionEnvio2'] ?? "",
      direccionEnvio3: map['direccionEnvio3'] ?? "",
      infoAdicional: map['infoAdicional'] ?? "",
      folderId: map['folderId'],
    );
  }
}
