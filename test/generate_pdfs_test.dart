import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novaled_app/local_module/models/articulo.dart';
import 'package:novaled_app/local_module/models/item_cotizacion.dart';
import 'package:novaled_app/local_module/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Generate PDFs for visual comparison', () async {
    SharedPreferences.setMockInitialValues({});

    final List<ItemCotizacion> items8 = List<ItemCotizacion>.generate(
      8,
      (i) => ItemCotizacion(
        articulo: Articulo(
          id: i + 1,
          nombre: "Cable HDMI 3 METROS",
          precio: 62.0,
          unidad: "Unidad",
          descripcion: "",
        ),
        cantidad: 2,
        precioOriginal: 62.0,
      ),
    );

    final List<ItemCotizacion> items16 = List<ItemCotizacion>.generate(
      16,
      (i) => ItemCotizacion(
        articulo: Articulo(
          id: i + 1,
          nombre: "Cable HDMI 3 METROS",
          precio: 62.0,
          unidad: "Unidad",
          descripcion: "",
        ),
        cantidad: 2,
        precioOriginal: 62.0,
      ),
    );

    // 1. Proforma
    final proformaBytes = await PdfService.generateCotizacionBytes(
      clienteNombre: "Miguel Angel",
      items: items8,
      subtotalOriginal: 22050.0,
      ahorroItems: 0.0,
      descuentoGlobal: 0.0,
      total: 22050.0,
      docId: 60,
      tituloDocumento: "PROFORMA",
      fecha: "07/07/2026",
    );
    await File('test_proforma.pdf').writeAsBytes(proformaBytes);

    // 2. Cotizacion
    final cotizacionBytes = await PdfService.generateCotizacionBytes(
      clienteNombre: "Miguel Angel",
      items: items8,
      subtotalOriginal: 22050.0,
      ahorroItems: 0.0,
      descuentoGlobal: 0.0,
      total: 22050.0,
      docId: 60,
      tituloDocumento: "COTIZACIÓN",
      fecha: "07/07/2026",
      incluyeFirmaEmpresa: true,
    );
    await File('test_cotizacion.pdf').writeAsBytes(cotizacionBytes);

    // 3. Nota de Entrega
    final notaBytes = await PdfService.generateCotizacionBytes(
      clienteNombre: "Miguel Angel",
      items: items16,
      subtotalOriginal: 22050.0,
      ahorroItems: 0.0,
      descuentoGlobal: 0.0,
      total: 22050.0,
      docId: 102,
      tituloDocumento: "NOTA DE ENTREGA",
      fecha: "12/07/2026",
    );
    await File('test_nota_entrega.pdf').writeAsBytes(notaBytes);

    print("PDFs generated successfully!");
  });
}
