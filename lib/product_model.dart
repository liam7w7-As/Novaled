class Product {
  String? folderId;
  String? dataFileId;
  String titulo;
  String detalles;
  String precio;
  String estado;
  Map<String, String> medidas;
  String familia;
  String subcategoria;
  String codTienda;
  String codCaja;
  String watts;
  String marca;
  String? finalArtId;
  String? infoDocId;
  String? verificadoPor;
  List<String> camposModificados;
  List<String> imageIds;
  String fecha;
  double precioCaja;
  int cantidad;
  String unidad;
  String unidadDetalle;

  Product({
    this.folderId,
    this.dataFileId,
    required this.titulo,
    this.detalles = '',
    this.precio = '',
    this.estado = 'pendiente',
    required this.medidas,
    this.familia = '',
    this.subcategoria = '',
    this.codTienda = '',
    this.codCaja = '',
    this.watts = '',
    this.marca = '',
    this.finalArtId,
    this.infoDocId,
    this.verificadoPor,
    this.camposModificados = const [],
    this.imageIds = const [],
    this.fecha = '',
    this.precioCaja = 0.0,
    this.cantidad = 0,
    this.unidad = 'Unidad',
    this.unidadDetalle = '',
  });

  factory Product.fromJson(Map<String, dynamic> json, String folderId, String fileId) {
    return Product(
      folderId: folderId,
      dataFileId: fileId,
      titulo: json['titulo'] ?? '',
      detalles: json['detalles'] ?? '',
      precio: json['precio']?.toString() ?? '',
      estado: (json['estado']?.toString() ?? 'pendiente').trim().toLowerCase(),
      medidas: Map<String, String>.from(json['medidas'] ?? {}),
      familia: json['familia'] ?? '',
      subcategoria: json['subcategoria'] ?? '',
      codTienda: json['codigo_tienda'] ?? '',
      codCaja: json['codigo_caja'] ?? '',
      watts: json['watts'] ?? '',
      marca: json['marca'] ?? '',
      finalArtId: json['final_art_id'],
      infoDocId: json['info_doc_id'],
      verificadoPor: json['verificado_por'],
      camposModificados: List<String>.from(json['campos_modificados'] ?? []),
      imageIds: List<String>.from(json['image_ids'] ?? []),
      fecha: json['fecha']?.toString() ?? json['fecha_registro']?.toString() ?? '',
      precioCaja: (json['precio_caja'] as num?)?.toDouble() ?? 0.0,
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
      unidad: json['unidad'] ?? 'Unidad',
      unidadDetalle: json['unidad_detalle'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'titulo': titulo,
    'detalles': detalles,
    'precio': precio,
    'estado': estado,
    'medidas': medidas,
    'familia': familia,
    'subcategoria': subcategoria,
    'codigo_tienda': codTienda,
    'codigo_caja': codCaja,
    'watts': watts,
    'marca': marca,
    'final_art_id': finalArtId,
    'info_doc_id': infoDocId,
    'verificado_por': verificadoPor,
    'campos_modificados': camposModificados,
    'image_ids': imageIds,
    'fecha': fecha,
    'precio_caja': precioCaja,
    'cantidad': cantidad,
    'unidad': unidad,
    'unidad_detalle': unidadDetalle,
  };
}
