import 'dart:typed_data';
import 'package:docx_creator/docx_creator.dart';
import '../models/item_cotizacion.dart';

class DocxService {
  static Future<Uint8List> generateCotizacionDocx({
    required String clienteNombre,
    required List<ItemCotizacion> items,
    required double subtotalOriginal,
    required double ahorroItems,
    required double descuentoGlobal,
    required double total,
    String? notas,
    String? terminos,
    int? docId,
    bool incluyeFirmaEmpresa = false,
    bool incluyeFirmaCliente = false,
    bool mostrarAhorro = true,
    bool mostrarTerminos = true,
    String tituloDocumento = "COTIZACIÓN",
    String? fecha,
  }) async {
    final formattedId = docId?.toString().padLeft(5, '0') ?? '00000';
    final cleanFecha = fecha ?? DateTime.now().toIso8601String().substring(0, 10);

    final builder = docx()
      .h1(tituloDocumento)
      .p("Documento #: COT-$formattedId")
      .p("Fecha: $cleanFecha")
      .p("Cliente: $clienteNombre")
      .hr();

    // Table Data
    final List<List<String>> tableData = [];
    tableData.add(["#", "Detalle / Artículo", "Cant.", "Unidad", "Precio Unit.", "Total"]);

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      tableData.add([
        (i + 1).toString(),
        item.articulo.nombre,
        item.cantidad.toString(),
        item.articulo.unidad,
        "${item.precioOriginal.toStringAsFixed(2)} Bs",
        "${item.total.toStringAsFixed(2)} Bs"
      ]);
    }

    builder.table(
      tableData,
      style: const DocxTableStyle(
        headerFill: 'EFA820', // Corporate Orange
        borderColor: 'CCCCCC',
        borderWidth: 4,
        evenRowFill: 'FFFBF2', // Zebra stripe (soft orange/yellow)
        cellPadding: 140, // Nice cell padding
      ),
    );

    builder.p("").p(""); // Spacing

    // Totals Section
    builder.p("Subtotal: ${subtotalOriginal.toStringAsFixed(2)} Bs", align: DocxAlign.right);
    if (descuentoGlobal > 0) {
      builder.p("Descuento: -${descuentoGlobal.toStringAsFixed(2)} Bs", align: DocxAlign.right);
    }
    builder.p("Total: ${total.toStringAsFixed(2)} Bs", align: DocxAlign.right);

    builder.hr();

    // Notes and Terms
    if (notas != null && notas.trim().isNotEmpty) {
      builder.h3("Notas").p(notas);
    }

    if (mostrarTerminos && terminos != null && terminos.trim().isNotEmpty) {
      builder.h3("Términos y Condiciones").p(terminos);
    }

    // Signature lines if requested
    if (incluyeFirmaEmpresa || incluyeFirmaCliente) {
      builder.p("").p("");
      if (incluyeFirmaEmpresa && incluyeFirmaCliente) {
        builder.p("Firma Autorizada: ___________________________");
        builder.p("Firma Cliente: ___________________________");
      } else if (incluyeFirmaEmpresa) {
        builder.p("Firma Autorizada: ___________________________");
      } else if (incluyeFirmaCliente) {
        builder.p("Firma Cliente: ___________________________");
      }
    }

    final doc = builder.build();
    return await DocxExporter().exportToBytes(doc);
  }
}
