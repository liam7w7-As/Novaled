import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/item_cotizacion.dart';

class PdfService {
  static Future<void> generateCotizacion({
    required String clienteNombre,
    required List<ItemCotizacion> items,
    required double subtotal,
    required double impuesto,
    required double descuento,
    required double total,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("NOVALED", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Cotización", style: pw.TextStyle(fontSize: 20)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text("Cliente: $clienteNombre"),
              pw.Text("Fecha: ${DateTime.now().toString().split(' ')[0]}"),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headers: ['Articulo', 'Precio', 'Cant.', 'Total'],
                data: items.map((item) => [
                  item.articulo.nombre,
                  "${item.articulo.precio.toStringAsFixed(2)}",
                  "${item.cantidad}",
                  "${item.total.toStringAsFixed(2)}"
                ]).toList(),
              ),
              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("Subtotal: ${subtotal.toStringAsFixed(2)} Bs"),
                      pw.Text("IVA (13%): ${impuesto.toStringAsFixed(2)} Bs"),
                      pw.Text("Descuento: ${descuento.toStringAsFixed(2)} Bs"),
                      pw.Divider(),
                      pw.Text("TOTAL: ${total.toStringAsFixed(2)} Bs",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
