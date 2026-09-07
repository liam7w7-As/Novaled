class Articulo {
  final int? id;
  final String nombre;
  final double precio;
  final double precioCaja;
  final String descripcion;
  final String? folderId;
  final String? finalArtId;
  final String? proveedor;
  final String? codCaja;
  final String? stockJson;
  final String familia;
  final String subcategoria;
  final String unidad;
  final String unidadDetalle;
  final String? imagen;
  final String fecha;

  Articulo({
    this.id,
    required this.nombre,
    required this.precio,
    this.precioCaja = 0.0,
    required this.descripcion,
    this.folderId,
    this.finalArtId,
    this.proveedor,
    this.codCaja,
    this.stockJson,
    this.familia = '',
    this.subcategoria = '',
    this.unidad = 'Unidad',
    this.unidadDetalle = '',
    this.imagen,
    this.fecha = '',
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nombre': nombre,
      'precio': precio,
      'precioCaja': precioCaja,
      'descripcion': descripcion,
      'folderId': folderId,
      'finalArtId': finalArtId,
      'proveedor': proveedor,
      'codCaja': codCaja,
      'stockJson': stockJson,
      'familia': familia,
      'subcategoria': subcategoria,
      'unidad': unidad,
      'unidadDetalle': unidadDetalle,
      'imagen': imagen,
      'fecha': fecha,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory Articulo.fromMap(Map<String, dynamic> map) {
    return Articulo(
      id: map['id'],
      nombre: map['nombre'] ?? "Sin Nombre",
      precio: (map['precio'] as num?)?.toDouble() ?? 0.0,
      precioCaja: (map['precioCaja'] as num?)?.toDouble() ?? 0.0,
      descripcion: map['descripcion'] ?? "",
      folderId: map['folderId'],
      finalArtId: map['finalArtId'],
      proveedor: map['proveedor'],
      codCaja: map['codCaja'],
      stockJson: map['stockJson'],
      familia: map['familia'] ?? "",
      subcategoria: map['subcategoria'] ?? "",
      unidad: map['unidad'] ?? "Unidad",
      unidadDetalle: map['unidadDetalle'] ?? "",
      imagen: map['imagen'],
      fecha: map['fecha'] ?? "",
    );
  }

  Articulo copyWith({
    int? id,
    String? nombre,
    double? precio,
    double? precioCaja,
    String? descripcion,
    String? folderId,
    String? finalArtId,
    String? proveedor,
    String? codCaja,
    String? stockJson,
    String? familia,
    String? subcategoria,
    String? unidad,
    String? unidadDetalle,
    String? imagen,
    String? fecha,
  }) {
    return Articulo(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      precio: precio ?? this.precio,
      precioCaja: precioCaja ?? this.precioCaja,
      descripcion: descripcion ?? this.descripcion,
      folderId: folderId ?? this.folderId,
      finalArtId: finalArtId ?? this.finalArtId,
      proveedor: proveedor ?? this.proveedor,
      codCaja: codCaja ?? this.codCaja,
      stockJson: stockJson ?? this.stockJson,
      familia: familia ?? this.familia,
      subcategoria: subcategoria ?? this.subcategoria,
      unidad: unidad ?? this.unidad,
      unidadDetalle: unidadDetalle ?? this.unidadDetalle,
      imagen: imagen ?? this.imagen,
      fecha: fecha ?? this.fecha,
    );
  }

  Articulo copyWithId(int newId) {
    return copyWith(id: newId);
  }
}
