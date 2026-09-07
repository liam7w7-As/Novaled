import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../models/item_cotizacion.dart';
import '../services/pdf_service.dart';

class CotizacionVistaPreviaScreen extends StatefulWidget {
  final String titulo;
  final String clienteNombre;
  final List<ItemCotizacion> items;
  final double subtotalOriginal;
  final double ahorroItems;
  final double descuentoGlobal;
  final double total;
  final String? notas;
  final String? terminos;
  final int? docId;
  final bool incluyeFirmaEmpresa;
  final bool incluyeFirmaCliente;
  final String tituloDocumento;
  final String? fecha;
  final VoidCallback? onEdit;
  final String returnButtonText;

  const CotizacionVistaPreviaScreen({
    Key? key,
    this.titulo = "Vista previa",
    required this.clienteNombre,
    required this.items,
    required this.subtotalOriginal,
    this.ahorroItems = 0.0,
    this.descuentoGlobal = 0.0,
    required this.total,
    this.notas,
    this.terminos,
    this.docId,
    this.incluyeFirmaEmpresa = false,
    this.incluyeFirmaCliente = false,
    this.tituloDocumento = "COTIZACIÓN",
    this.fecha,
    this.sucursal,
    this.vendedor,
    this.onEdit,
    this.returnButtonText = "Volver a cotizaciones",
  }) : super(key: key);

  final String? sucursal;
  final String? vendedor;

  @override
  State<CotizacionVistaPreviaScreen> createState() => _CotizacionVistaPreviaScreenState();
}

class _CotizacionVistaPreviaScreenState extends State<CotizacionVistaPreviaScreen> {
  bool _isColor = true;

  Future<Uint8List> _obtenerPdfBytes() async {
    return await PdfService.generateCotizacionBytes(
      clienteNombre: widget.clienteNombre,
      items: widget.items,
      subtotalOriginal: widget.subtotalOriginal,
      ahorroItems: widget.ahorroItems,
      descuentoGlobal: widget.descuentoGlobal,
      total: widget.total,
      notas: widget.notas,
      terminos: widget.terminos,
      docId: widget.docId ?? 60,
      incluyeFirmaEmpresa: widget.incluyeFirmaEmpresa,
      incluyeFirmaCliente: widget.incluyeFirmaCliente,
      tituloDocumento: widget.tituloDocumento,
      fecha: widget.fecha,
      isColor: _isColor,
      sucursal: widget.sucursal,
      vendedor: widget.vendedor,
    );
  }

  Future<void> _descargarComoPDF() async {
    try {
      final bytes = await _obtenerPdfBytes();
      final String formattedId = (widget.docId ?? 60).toString().padLeft(5, '0');
      final prefix = widget.tituloDocumento.toUpperCase() == "NOTA DE ENTREGA"
          ? "NotaEntrega_NE"
          : ((widget.tituloDocumento.toUpperCase() == "PROFORMA" || widget.tituloDocumento.toUpperCase() == "NOTA DE VENTA") ? "NotaDeVenta_NV" : "Cotizacion_COT");
      final filename = "${prefix}-$formattedId.pdf";

      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception("No se pudo acceder al directorio de descargas");
      }

      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("PDF guardado en: ${directory.path.split('/').last}/$filename"),
            backgroundColor: Theme.of(context).primaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al guardar PDF: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (widget.onEdit != null) {
          widget.onEdit!();
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF131510) : const Color(0xFFF3F6FD),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF131510) : const Color(0xFFF3F6FD),
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: Image.asset(
              'Iconos/Nuevo/nuevo/3/atras.png',
              width: 20,
              height: 20,
              color: textColor,
              errorBuilder: (_, __, ___) => Icon(Icons.arrow_back, color: textColor),
            ),
            onPressed: () {
              if (widget.onEdit != null) {
                widget.onEdit!();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            "Vista previa",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: textColor,
              fontSize: 19,
            ),
          ),
          actions: [
            IconButton(
              icon: Image.asset(
                'Iconos/Nuevo/nuevo/3/impresiones.png',
                width: 22,
                height: 22,
                color: textColor,
                errorBuilder: (_, __, ___) => Icon(Icons.print_outlined, color: textColor),
              ),
              onPressed: () async {
                final bytes = await _obtenerPdfBytes();
                await Printing.layoutPdf(onLayout: (format) async => bytes);
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Instant zoomable Full-Screen PDF Preview
              Expanded(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: PdfPreview(
                    build: (format) => _obtenerPdfBytes(),
                    useActions: false,
                    previewPageMargin: EdgeInsets.zero,
                    padding: EdgeInsets.zero,
                    pdfPreviewPageDecoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: [],
                    ),
                    scrollViewDecoration: BoxDecoration(
                      color: isDark ? const Color(0xFF131510) : Theme.of(context).scaffoldBackgroundColor,
                    ),
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    loadingWidget: const Center(
                      child: CircularProgressIndicator(color: Color(0xFF5842F4)),
                    ),
                  ),
                ),
              ),

              // Compact 44px buttons positioned higher up
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCircleActionButton(
                      iconAsset: 'Iconos/Nuevo/nuevo/3/descargar.png',
                      label: "Descargar",
                      onTap: () => _descargarComoPDF(),
                      isDark: isDark,
                    ),
                    _buildCircleActionButton(
                      iconAsset: 'Iconos/Nuevo/nuevo/3/compartir.png',
                      label: "Compartir",
                      onTap: () async {
                        final bytes = await _obtenerPdfBytes();
                        final String formattedId = (widget.docId ?? 60).toString().padLeft(5, '0');
                        final prefix = widget.tituloDocumento.toUpperCase() == "NOTA DE ENTREGA"
                            ? "NotaEntrega_NE"
                            : ((widget.tituloDocumento.toUpperCase() == "PROFORMA" || widget.tituloDocumento.toUpperCase() == "NOTA DE VENTA") ? "NotaDeVenta_NV" : "Cotizacion_COT");
                        await Printing.sharePdf(
                          bytes: bytes,
                          filename: "$prefix-$formattedId.pdf",
                        );
                      },
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleActionButton({
    required String iconAsset,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Image.asset(
                iconAsset,
                width: 20,
                height: 20,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                errorBuilder: (_, __, ___) => Icon(
                  iconAsset.contains('descargar') ? Icons.file_download_outlined : Icons.share_outlined,
                  size: 20,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.white70 : const Color(0xFF909CB5),
          ),
        ),
      ],
    );
  }
}
