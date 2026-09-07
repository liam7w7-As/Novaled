import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/item_cotizacion.dart';
import '../tenant_helper.dart';
import '../../login_screen.dart';

class PdfService {
  static PdfColor primaryPurple = PdfColor.fromInt(0xFF5842F4);
  static const PdfColor rowGray = PdfColor.fromInt(0xFFE2E2E2);
  static const PdfColor textGray = PdfColor.fromInt(0xFF666666);

  static pw.Font? _arimoRegular;
  static pw.Font? _arimoBold;
  static pw.Font? _arimoItalic;
  static pw.Font? _arimoBoldItalic;
  static pw.Font? _poppinsExtraBold;
  static pw.Font? _poppinsBlack;

  static pw.MemoryImage? _logoHeaderImage;
  static pw.MemoryImage? _banderaImage;
  static pw.MemoryImage? _firmaImage;
  static pw.MemoryImage? _selloImage;
  static pw.MemoryImage? _selloFirmaComboImage;
  static pw.MemoryImage? _facebookImage;
  static pw.MemoryImage? _tiktokImage;
  static pw.MemoryImage? _instagramImage;
  static pw.MemoryImage? _linkedinImage;
  static pw.MemoryImage? _urlImage;
  static pw.MemoryImage? _mapsImage;

  static Future<void> preloadResources() async {
    try {
      try {
        _arimoRegular ??= await PdfGoogleFonts.arimoRegular();
        _arimoBold ??= await PdfGoogleFonts.arimoBold();
        _arimoItalic ??= await PdfGoogleFonts.arimoItalic();
        _arimoBoldItalic ??= await PdfGoogleFonts.arimoBoldItalic();
        _poppinsExtraBold ??= await PdfGoogleFonts.poppinsExtraBold();
        _poppinsBlack ??= await PdfGoogleFonts.poppinsBlack();
      } catch (_) {
        if (File('C:\\Windows\\Fonts\\arial.ttf').existsSync()) {
          final bytes = await File('C:\\Windows\\Fonts\\arial.ttf').readAsBytes();
          _arimoRegular = pw.Font.ttf(bytes.buffer.asByteData());
          _arimoItalic = pw.Font.ttf(bytes.buffer.asByteData());
        }
        if (File('C:\\Windows\\Fonts\\arialbd.ttf').existsSync()) {
          final bytes = await File('C:\\Windows\\Fonts\\arialbd.ttf').readAsBytes();
          _arimoBold = pw.Font.ttf(bytes.buffer.asByteData());
          _arimoBoldItalic = pw.Font.ttf(bytes.buffer.asByteData());
          _poppinsExtraBold = pw.Font.ttf(bytes.buffer.asByteData());
          _poppinsBlack = pw.Font.ttf(bytes.buffer.asByteData());
        }
      }

      if (_logoHeaderImage == null) {
        final data = await rootBundle.load('logo novaled/novaled version color.png');
        _logoHeaderImage = pw.MemoryImage(data.buffer.asUint8List());
      }
      if (_banderaImage == null) {
        final data = await rootBundle.load('logo novaled/bandera.png');
        _banderaImage = pw.MemoryImage(data.buffer.asUint8List());
      }
      if (_firmaImage == null) {
        final data = await rootBundle.load('logo novaled/firma.png');
        _firmaImage = pw.MemoryImage(data.buffer.asUint8List());
      }
      if (_selloImage == null) {
        final data = await rootBundle.load('logo novaled/sello_novaled.png');
        _selloImage = pw.MemoryImage(data.buffer.asUint8List());
      }
      if (_selloFirmaComboImage == null) {
        final data = await rootBundle.load('logo novaled/sello_firma_combo.png');
        _selloFirmaComboImage = pw.MemoryImage(data.buffer.asUint8List());
      }
      if (_facebookImage == null) {
        final data = await rootBundle.load('logo novaled/facebook_gray.png');
        _facebookImage = pw.MemoryImage(data.buffer.asUint8List());
      }
      if (_tiktokImage == null) {
        final data = await rootBundle.load('logo novaled/tiktok_gray.png');
        _tiktokImage = pw.MemoryImage(data.buffer.asUint8List());
      }
      if (_instagramImage == null) {
        final data = await rootBundle.load('logo novaled/instagram_gray.png');
        _instagramImage = pw.MemoryImage(data.buffer.asUint8List());
      }
      if (_linkedinImage == null) {
        final data = await rootBundle.load('logo novaled/indesing_gray.png');
        _linkedinImage = pw.MemoryImage(data.buffer.asUint8List());
      }
      if (_urlImage == null) {
        final data = await rootBundle.load('logo novaled/url_gray.png');
        _urlImage = pw.MemoryImage(data.buffer.asUint8List());
      }
      if (_mapsImage == null) {
        final data = await rootBundle.load('logo novaled/maps_gray.png');
        _mapsImage = pw.MemoryImage(data.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint("Warning: PdfService preload error: $e");
    }
  }

  static Future<Uint8List> generateCotizacionBytes({
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
    bool isColor = true,
    String? sucursal,
    String? vendedor,
  }) async {
    await preloadResources();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: _arimoRegular!,
        bold: _arimoBold!,
        italic: _arimoItalic!,
        boldItalic: _arimoBoldItalic!,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    final tenantKey = await TenantHelper.getActiveTenantKey();
    final isNovaled = tenantKey == 'novaled';

    final int primaryColorInt = prefs.getInt(TenantHelper.k('pdf_primary_color', tenantKey)) ?? 0xFF5842F4;
    primaryPurple = PdfColor.fromInt(primaryColorInt);

    final String companyName = prefs.getString(TenantHelper.k('pdf_company_name', tenantKey)) ?? (isNovaled ? "NOVALED" : "");
    final String companyEmail = prefs.getString(TenantHelper.k('pdf_company_email', tenantKey)) ?? (isNovaled ? "novaled.elektroshop@gmail.com" : "");
    final String companyPhone = prefs.getString(TenantHelper.k('pdf_company_phone', tenantKey)) ?? (isNovaled ? "67079501" : "");
    final String rawCompanyAddress = prefs.getString(TenantHelper.k('pdf_company_address', tenantKey)) ?? (isNovaled ? "Calle Isaac Tamayo #818 #840 La Paz- Bolivia" : "");
    final List<String> systemSucursales = prefs.getStringList(TenantHelper.k('system_sucursales', tenantKey)) ?? (isNovaled ? ["#818", "#840"] : []);
    final String companyAddress = formatAddressForSucursal(rawCompanyAddress, sucursal, systemSucursales, isNovaled);
    final String companyNit = prefs.getString(TenantHelper.k('pdf_company_nit', tenantKey)) ?? (isNovaled ? "5996871010" : "");
    final String socialHandle = prefs.getString(TenantHelper.k('pdf_social_handle', tenantKey)) ?? (isNovaled ? "@novaledbolivia" : "");
    final String website = prefs.getString(TenantHelper.k('pdf_website', tenantKey)) ?? (isNovaled ? "www.novaledbolivia.com" : "");

    final String customLogoPath = prefs.getString(TenantHelper.k('pdf_company_logo_path', tenantKey)) ?? '';
    if (customLogoPath.isNotEmpty && File(customLogoPath).existsSync()) {
      try {
        final logoBytes = await File(customLogoPath).readAsBytes();
        _logoHeaderImage = pw.MemoryImage(logoBytes);
      } catch (_) {}
    } else if (isNovaled) {
      try {
        final data = await rootBundle.load('logo novaled/novaled version color.png');
        _logoHeaderImage = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}
    } else {
      _logoHeaderImage = null;
    }

    final String customSelloPath = prefs.getString(TenantHelper.k('pdf_company_sello_path', tenantKey)) ?? '';
    if (customSelloPath.isNotEmpty && File(customSelloPath).existsSync()) {
      try {
        final selloBytes = await File(customSelloPath).readAsBytes();
        _selloImage = pw.MemoryImage(selloBytes);
        _selloFirmaComboImage = pw.MemoryImage(selloBytes);
      } catch (_) {}
    } else {
      _selloImage = null;
      _selloFirmaComboImage = null;
    }

    String formatDate(String? dateStr) {
      if (dateStr == null || dateStr.trim().isEmpty) {
        final now = DateTime.now();
        return "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
      }
      try {
        final cleanDate = dateStr.trim().split(' ')[0];
        final parts = cleanDate.split('-');
        if (parts.length == 3) {
          final year = parts[0];
          final month = parts[1];
          final day = parts[2];
          return "$day/$month/$year";
        }
      } catch (_) {}
      return dateStr;
    }

    final formattedDate = formatDate(fecha);
    final String docNumber = (docId ?? 60).toString();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 36, right: 36, top: 20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildHeader(
                      tituloDocumento: tituloDocumento,
                      docNumber: docNumber,
                      fecha: formattedDate,
                      email: companyEmail,
                      phone: companyPhone,
                      nit: companyNit,
                      clienteNombre: clienteNombre,
                      asesor: (vendedor != null && vendedor.trim().isNotEmpty)
                          ? vendedor.trim()
                          : (isNovaled ? "JOEL" : (Session().userName ?? "")),
                    ),
                    pw.SizedBox(height: 16),
                    _buildItemsTable(
                      items: items,
                      tituloDocumento: tituloDocumento,
                    ),
                    pw.SizedBox(height: 14),
                    _buildTotalsBlock(
                      subtotalOriginal: subtotalOriginal,
                      total: total,
                      tituloDocumento: tituloDocumento,
                    ),
                    if (tituloDocumento.toUpperCase() == "NOTA DE ENTREGA" || incluyeFirmaEmpresa || incluyeFirmaCliente) ...[
                      pw.Spacer(),
                      _buildSignaturesBlock(
                        tituloDocumento: tituloDocumento,
                        incluyeFirmaEmpresa: incluyeFirmaEmpresa,
                        companyName: companyName,
                      ),
                    ],
                    pw.Spacer(),
                    _buildFooterSection(
                      tituloDocumento: tituloDocumento,
                      notas: notas,
                      mostrarNotas: (notas != null && notas.trim().isNotEmpty) || mostrarTerminos,
                      socialHandle: socialHandle,
                      website: website,
                      address: companyAddress,
                    ),
                  ],
                ),
              ),
              pw.Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: pw.Container(
                  height: 10,
                  color: primaryPurple,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> generateCotizacion({
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
    bool isColor = true,
  }) async {
    final pdfBytes = await generateCotizacionBytes(
      clienteNombre: clienteNombre,
      items: items,
      subtotalOriginal: subtotalOriginal,
      ahorroItems: ahorroItems,
      descuentoGlobal: descuentoGlobal,
      total: total,
      notas: notas,
      terminos: terminos,
      docId: docId,
      incluyeFirmaEmpresa: incluyeFirmaEmpresa,
      incluyeFirmaCliente: incluyeFirmaCliente,
      mostrarAhorro: mostrarAhorro,
      mostrarTerminos: mostrarTerminos,
      isColor: isColor,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'Cotizacion_${clienteNombre.replaceAll(' ', '_')}.pdf',
    );
  }

  static pw.Widget _buildHeader({
    required String tituloDocumento,
    required String docNumber,
    required String fecha,
    required String email,
    required String phone,
    required String nit,
    required String clienteNombre,
    String? asesor,
  }) {
    final isNota = tituloDocumento.toUpperCase() == "NOTA DE ENTREGA";
    final isProforma = tituloDocumento.toUpperCase() == "PROFORMA" || tituloDocumento.toUpperCase() == "NOTA DE VENTA";
    final docLabel = isNota ? "Nota:" : (isProforma ? "Nota de Venta No:" : "Cotización No:");
    final displayHeaderTitle = isProforma ? "NOTA DE VENTA" : tituloDocumento.toUpperCase();
    final labelText = isNota ? "PARA:" : (isProforma ? "NOTA DE VENTA PARA:" : "COTIZACIÓN PARA:");

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Columna Izquierda: Logo + Nombre de Cliente (alineado horizontalmente con Cel/Asesor)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (_logoHeaderImage != null)
              pw.Container(
                width: 138.3,
                height: 70.3,
                alignment: pw.Alignment.centerLeft,
                child: pw.Image(_logoHeaderImage!, fit: pw.BoxFit.contain),
              )
            else
              pw.SizedBox(height: 70.3),
            pw.SizedBox(height: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  labelText,
                  style: pw.TextStyle(
                    fontSize: 6.8,
                    fontWeight: pw.FontWeight.bold,
                    color: textGray,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  clienteNombre,
                  style: pw.TextStyle(
                    fontSize: 14.1,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
              ],
            ),
          ],
        ),

        // Columna Derecha: Título Documento + Caja de Información (Cotización No, Fecha, NIT, Correo, Cel, Asesor)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Container(
              height: 70.3,
              alignment: pw.Alignment.bottomRight,
              child: pw.Text(
                displayHeaderTitle,
                style: pw.TextStyle(
                  font: _poppinsBlack ?? _poppinsExtraBold,
                  fontSize: 26.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeaderInfoRow(docLabel, docNumber),
                pw.SizedBox(height: 2.2),
                _buildHeaderInfoRow("Fecha:", fecha),
                if (!isNota) ...[
                  pw.SizedBox(height: 2.2),
                  _buildHeaderInfoRow("NIT:", nit),
                  pw.SizedBox(height: 2.2),
                  _buildHeaderInfoRow("Correo:", email),
                  pw.SizedBox(height: 2.2),
                  _buildHeaderInfoRow("Cel:", phone),
                  if (asesor != null && asesor.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 2.2),
                    _buildHeaderInfoRow("Asesor:", asesor.trim()),
                  ],
                ] else if (asesor != null && asesor.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2.2),
                  _buildHeaderInfoRow("Asesor:", asesor.trim()),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildHeaderInfoRow(String label, String value) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 56,
          child: pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 6.8, color: textGray),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
        ),
      ],
    );
  }

  static pw.Widget _buildClientBlock({
    required String clienteNombre,
    required String tituloDocumento,
  }) {
    final isNota = tituloDocumento.toUpperCase() == "NOTA DE ENTREGA";
    final isProforma = tituloDocumento.toUpperCase() == "PROFORMA" || tituloDocumento.toUpperCase() == "NOTA DE VENTA";
    final labelText = isNota ? "PARA:" : (isProforma ? "NOTA DE VENTA PARA:" : "COTIZACIÓN PARA:");

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          labelText,
          style: pw.TextStyle(
            fontSize: 6.8,
            fontWeight: pw.FontWeight.bold,
            color: textGray,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          clienteNombre,
          style: pw.TextStyle(
            fontSize: 14.1,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTableHeaderCell(String text, {required pw.TextAlign align}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      alignment: align == pw.TextAlign.center
          ? pw.Alignment.center
          : (align == pw.TextAlign.right ? pw.Alignment.centerRight : pw.Alignment.centerLeft),
      child: pw.Text(
        text,
        style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _buildTableCell(String text, {required pw.TextAlign align, bool isBold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      alignment: align == pw.TextAlign.center
          ? pw.Alignment.center
          : (align == pw.TextAlign.right ? pw.Alignment.centerRight : pw.Alignment.centerLeft),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: PdfColors.black,
          fontSize: 8,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _buildCurrencyCell(double amount, {bool isBold = false}) {
    final String amountText = amount.toStringAsFixed(2);

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      alignment: pw.Alignment.centerLeft,
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(width: 4),
          pw.Text(
            "Bs.",
            style: pw.TextStyle(
              color: PdfColors.black,
              fontSize: 8,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Text(
            amountText,
            style: pw.TextStyle(
              color: PdfColors.black,
              fontSize: 8,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable({
    required List<ItemCotizacion> items,
    required String tituloDocumento,
  }) {
    final isNota = tituloDocumento.toUpperCase() == "NOTA DE ENTREGA";

    if (isNota) {
      return pw.Table(
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        border: const pw.TableBorder(
          verticalInside: pw.BorderSide(color: PdfColors.white, width: 2.0),
          horizontalInside: pw.BorderSide(color: PdfColors.white, width: 1.5),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(0.4),
          1: const pw.FlexColumnWidth(6.2),
          2: const pw.FlexColumnWidth(0.9),
          3: const pw.FlexColumnWidth(1.35),
          4: const pw.FlexColumnWidth(1.1),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: primaryPurple),
            children: [
              _buildTableHeaderCell('Nº', align: pw.TextAlign.center),
              _buildTableHeaderCell('Artículo', align: pw.TextAlign.left),
              _buildTableHeaderCell('Cant.', align: pw.TextAlign.center),
              _buildTableHeaderCell('Precio unitario', align: pw.TextAlign.center),
              _buildTableHeaderCell('Sub total', align: pw.TextAlign.center),
            ],
          ),
          ...List.generate(items.length, (index) {
            final item = items[index];
            final isEven = index % 2 == 0;
            final rowBg = isEven ? PdfColors.white : rowGray;
            return pw.TableRow(
              decoration: pw.BoxDecoration(color: rowBg),
              children: [
                _buildTableCell("${index + 1}", align: pw.TextAlign.center),
                _buildTableCell(item.articulo.nombre, align: pw.TextAlign.left, isBold: true),
                _buildTableCell("${item.cantidad}", align: pw.TextAlign.center),
                _buildCurrencyCell(item.articulo.precio),
                _buildCurrencyCell(item.total),
              ],
            );
          }),
        ],
      );
    } else {
      return pw.Table(
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        border: const pw.TableBorder(
          verticalInside: pw.BorderSide(color: PdfColors.white, width: 2.0),
          horizontalInside: pw.BorderSide(color: PdfColors.white, width: 1.5),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(0.4),
          1: const pw.FlexColumnWidth(5.5),
          2: const pw.FlexColumnWidth(0.7),
          3: const pw.FlexColumnWidth(0.9),
          4: const pw.FlexColumnWidth(1.35),
          5: const pw.FlexColumnWidth(1.1),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: primaryPurple),
            children: [
              _buildTableHeaderCell('Nº', align: pw.TextAlign.center),
              _buildTableHeaderCell('Artículo', align: pw.TextAlign.left),
              _buildTableHeaderCell('Cant.', align: pw.TextAlign.center),
              _buildTableHeaderCell('Unidad', align: pw.TextAlign.center),
              _buildTableHeaderCell('Precio unitario', align: pw.TextAlign.center),
              _buildTableHeaderCell('Subtotal', align: pw.TextAlign.center),
            ],
          ),
          ...List.generate(items.length, (index) {
            final item = items[index];
            final rawUnit = item.articulo.unidad;
            final unit = rawUnit.trim().isEmpty ? 'Unidad' : rawUnit.trim();
            final isEven = index % 2 == 0;
            final rowBg = isEven ? PdfColors.white : rowGray;
            return pw.TableRow(
              decoration: pw.BoxDecoration(color: rowBg),
              children: [
                _buildTableCell("${index + 1}", align: pw.TextAlign.center),
                _buildTableCell(item.articulo.nombre, align: pw.TextAlign.left, isBold: true),
                _buildTableCell("${item.cantidad}", align: pw.TextAlign.center),
                _buildTableCell(unit, align: pw.TextAlign.center),
                _buildCurrencyCell(item.articulo.precio),
                _buildCurrencyCell(item.total),
              ],
            );
          }),
        ],
      );
    }
  }

  static pw.Widget _buildTotalsBlock({
    required double subtotalOriginal,
    required double total,
    required String tituloDocumento,
  }) {
    final isNota = tituloDocumento.toUpperCase() == "NOTA DE ENTREGA";

    final totalFormatted = total % 1 == 0
        ? total.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')
        : total.toStringAsFixed(2);

    final subtotalFormatted = subtotalOriginal % 1 == 0
        ? subtotalOriginal.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')
        : subtotalOriginal.toStringAsFixed(2);

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 200,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (!isNota) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Sub total:", style: pw.TextStyle(fontSize: 8.5, color: PdfColors.black)),
                    pw.Text("Bs. $subtotalFormatted", style: pw.TextStyle(fontSize: 8.5, color: PdfColors.black)),
                  ],
                ),
                pw.SizedBox(height: 4),
              ],
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: primaryPurple,
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "TOTAL",
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9.5,
                      ),
                    ),
                    pw.Text(
                      "Bs. $totalFormatted",
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSignaturesBlock({
    required String tituloDocumento,
    required bool incluyeFirmaEmpresa,
    String companyName = "",
  }) {
    final isNota = tituloDocumento.toUpperCase() == "NOTA DE ENTREGA";
    final isProforma = tituloDocumento.toUpperCase() == "PROFORMA";

    final pw.Widget signatureAndStampStack = incluyeFirmaEmpresa
        ? pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (_selloImage != null)
                pw.Container(
                  height: 58,
                  child: pw.Image(_selloImage!, fit: pw.BoxFit.contain),
                )
              else if (_selloFirmaComboImage != null)
                pw.Container(
                  height: 58,
                  child: pw.Image(_selloFirmaComboImage!, fit: pw.BoxFit.contain),
                ),
            ],
          )
        : pw.SizedBox.shrink();

    if (isNota) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  height: 118,
                  alignment: pw.Alignment.bottomCenter,
                  child: signatureAndStampStack,
                ),
                pw.Container(
                  width: 140,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 1.0)),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  "ENTREGUE CONFORME",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: PdfColors.black),
                ),
              ],
            ),
            pw.SizedBox(width: 50),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(height: 118),
                pw.Container(
                  width: 140,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 1.0)),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  "RECIBÍ CONFORME",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: PdfColors.black),
                ),
              ],
            ),
          ],
        ),
      );
    } else if (!isProforma) {
      final String displayName = companyName.trim().isNotEmpty
          ? companyName.trim().toUpperCase()
          : "EMPRESA";
      return pw.Center(
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            signatureAndStampStack,
            pw.Container(
              width: 165,
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 1.0)),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              displayName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.black),
            ),
          ],
        ),
      );
    }
    return pw.SizedBox.shrink();
  }

  static pw.Widget _buildFooterSection({
    required String tituloDocumento,
    required String? notas,
    bool mostrarNotas = true,
    required String socialHandle,
    required String website,
    required String address,
  }) {
    final isNota = tituloDocumento.toUpperCase() == "NOTA DE ENTREGA";
    final isProforma = tituloDocumento.toUpperCase() == "PROFORMA" || tituloDocumento.toUpperCase() == "NOTA DE VENTA";
    final isPuntoVentaDoc = isNota || isProforma;
    final bool hasExplicitNotes = notas != null && notas.trim().isNotEmpty;
    final String? notasText = hasExplicitNotes ? notas!.trim() : "Validez de cotización 10 días";

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (!isPuntoVentaDoc && mostrarNotas && notasText != null) ...[
          pw.Text(
            "Notas",
            style: const pw.TextStyle(fontSize: 6.8, color: textGray),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            notasText,
            style: const pw.TextStyle(fontSize: 6.8, color: textGray),
          ),
          pw.SizedBox(height: 10),
        ],
        pw.Container(
          height: 0.8,
          color: const PdfColor.fromInt(0xFF9B9B9B),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (socialHandle.trim().isNotEmpty)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (_facebookImage != null) pw.Container(width: 9, height: 9, child: pw.Image(_facebookImage!)),
                  pw.SizedBox(width: 2),
                  if (_tiktokImage != null) pw.Container(width: 9, height: 9, child: pw.Image(_tiktokImage!)),
                  pw.SizedBox(width: 2),
                  if (_instagramImage != null) pw.Container(width: 9, height: 9, child: pw.Image(_instagramImage!)),
                  pw.SizedBox(width: 2),
                  if (_linkedinImage != null) pw.Container(width: 9, height: 9, child: pw.Image(_linkedinImage!)),
                  pw.SizedBox(width: 4),
                  pw.Text(socialHandle.trim(), style: const pw.TextStyle(fontSize: 8.9, color: textGray)),
                ],
              )
            else
              pw.SizedBox(),
            if (website.trim().isNotEmpty)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (_urlImage != null) pw.Container(width: 9, height: 9, child: pw.Image(_urlImage!)),
                  pw.SizedBox(width: 3),
                  pw.Text(website.trim(), style: const pw.TextStyle(fontSize: 8.8, color: textGray)),
                ],
              )
            else
              pw.SizedBox(),
            if (address.trim().isNotEmpty)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (_mapsImage != null) pw.Container(width: 9, height: 9, child: pw.Image(_mapsImage!)),
                  pw.SizedBox(width: 3),
                  pw.Text(address.trim(), style: const pw.TextStyle(fontSize: 9.0, color: textGray)),
                ],
              )
            else
              pw.SizedBox(),
          ],
        ),
        pw.SizedBox(height: 16),
      ],
    );
  }

  static String formatAddressForSucursal(String baseAddress, String? selectedSucursal, [List<String>? allSucursales, bool isNovaled = false]) {
    final cleanBase = baseAddress.trim();
    final target = (selectedSucursal ?? '').trim();

    // 1. Si no es Novaled (otra empresa/Gmail)
    if (!isNovaled) {
      if (cleanBase.isNotEmpty) {
        if (target.isNotEmpty && target != cleanBase && !cleanBase.toLowerCase().contains(target.toLowerCase())) {
          return "$cleanBase ($target)";
        }
        return cleanBase;
      }
      if (target.isNotEmpty) {
        return target;
      }
      return ""; // No tiene dirección ni sucursal configurada, dejar vacío
    }

    // 2. Lógica específica para Novaled
    if (target.isEmpty) {
      return cleanBase.isNotEmpty ? cleanBase : "Calle Isaac Tamayo #818 #840 La Paz - Bolivia";
    }

    // Si la sucursal ya es una dirección completa (ej: "Calle...", "Av...", "Zona..." o longitud > 20 caracteres)
    if (target.toLowerCase().contains("calle") || 
        target.toLowerCase().contains("av") || 
        target.toLowerCase().contains("zona") || 
        target.length > 20) {
      return target;
    }

    final String rawBase = cleanBase.isNotEmpty 
        ? cleanBase 
        : "Calle Isaac Tamayo #818 #840 La Paz - Bolivia";

    final sucursales = <String>{'#818', '#840', ...?allSucursales};
    
    final matches = RegExp(r'#\w+').allMatches(rawBase);
    for (var m in matches) {
      sucursales.add(m.group(0)!);
    }

    String updated = rawBase;
    for (var s in sucursales) {
      if (s.toLowerCase() != target.toLowerCase()) {
        updated = updated.replaceAll(RegExp(r'\s*' + RegExp.escape(s) + r'\b'), '');
      }
    }

    if (!updated.toLowerCase().contains(target.toLowerCase())) {
      for (var s in sucursales) {
        if (rawBase.toLowerCase().contains(s.toLowerCase())) {
          updated = rawBase.replaceAll(s, target);
          for (var other in sucursales) {
            if (other.toLowerCase() != target.toLowerCase()) {
              updated = updated.replaceAll(RegExp(r'\s*' + RegExp.escape(other) + r'\b'), '');
            }
          }
          break;
        }
      }
    }

    updated = updated.replaceAll(RegExp(r'\s+'), ' ').trim();
    return updated.isNotEmpty ? updated : "Calle Isaac Tamayo $target La Paz - Bolivia";
  }
}
