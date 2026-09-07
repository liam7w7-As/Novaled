import 'dart:io';
import 'package:flutter/material.dart';
import '../../login_screen.dart'; // Session
import '../tenant_helper.dart';

class GestionarPagosPage extends StatefulWidget {
  final Map<String, dynamic> doc;
  final Future<String?> Function() onImagePicker;
  final Future<void> Function(
    double finalSaldoCancelado,
    String? currentComprobanteImg,
    int currentComprobado,
    String currentMetodoPago,
  ) onSave;

  const GestionarPagosPage({
    super.key,
    required this.doc,
    required this.onImagePicker,
    required this.onSave,
  });

  @override
  State<GestionarPagosPage> createState() => _GestionarPagosPageState();
}

class _GestionarPagosPageState extends State<GestionarPagosPage> {
  late double total;
  late double initialSaldoCancelado;
  String? currentComprobanteImg;
  late int currentComprobado;
  late String currentMetodoPago;
  late TextEditingController textController;
  late FocusNode focusNode;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    total = (widget.doc['total'] as num?)?.toDouble() ?? 0.0;
    initialSaldoCancelado = (widget.doc['saldo_cancelado'] as num?)?.toDouble() ?? 0.0;
    currentComprobanteImg = widget.doc['comprobante_img']?.toString();
    currentComprobado = (widget.doc['comprobado'] as int?) ?? 0;
    
    // Mapear métodos antiguos para evitar crashes con la nueva lista de opciones
    currentMetodoPago = widget.doc['metodo_pago'] ?? 'Transferencia';
    if (currentMetodoPago == 'Transferencia Bancaria') {
      currentMetodoPago = 'Transferencia';
    } else if (currentMetodoPago == 'Tarjeta de Crédito/Débito') {
      currentMetodoPago = 'Tarjeta';
    } else if (currentMetodoPago == 'Cheque') {
      currentMetodoPago = 'Transferencia';
    }
    
    textController = TextEditingController(text: initialSaldoCancelado.toStringAsFixed(2));
    focusNode = FocusNode();
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        // Seleccionar todo el texto para permitir sobreescribir de inmediato
        textController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: textController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCotizacion = widget.doc['tipo'] == 'cotizacion' || widget.doc['tipo'] == null;
    final cliente = widget.doc['clienteNombre'] ?? 'SIN CLIENTE';

    double saldoCancelado = double.tryParse(textController.text) ?? 0.0;
    double saldoPendiente = total - saldoCancelado;
    if (saldoPendiente < 0) saldoPendiente = 0;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
        title: Text(
          isCotizacion ? "Pagos - Cotización" : "Pagos - Proforma",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00ADEF)),
                ),
              ),
            )
          else
            TextButton(
              onPressed: () async {
                setState(() => isSaving = true);
                try {
                  await widget.onSave(
                    saldoCancelado,
                    currentComprobanteImg,
                    currentComprobado,
                    currentMetodoPago,
                  );
                } finally {
                  if (mounted) setState(() => isSaving = false);
                }
              },
              child: const Text(
                "GUARDAR",
                style: TextStyle(
                  color: Color(0xFF00ADEF),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card de información del cliente
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "CLIENTE",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white30 : Colors.black38,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cliente.toString().toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Total a pagar:",
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        "Bs. ${total.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: isDark ? const Color(0xFF00ADEF) : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Sección de Saldos
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Saldo Cancelado",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: textController,
                        focusNode: focusNode,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          prefixText: "Bs. ",
                          prefixStyle: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFF00ADEF), width: 1.5),
                          ),
                        ),
                        onTap: () {
                          // Seleccionar todo el texto al pulsar sobre él
                          textController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: textController.text.length,
                          );
                        },
                        onChanged: (value) {
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Saldo Pendiente",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white10 : Colors.black12,
                          ),
                        ),
                        child: Text(
                          "Bs. ${saldoPendiente.toStringAsFixed(2)}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: saldoPendiente > 0 
                                ? Colors.orange[800] 
                                : const Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Método de Pago
            Text(
              "Método de Pago",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: currentMetodoPago,
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF00ADEF), width: 1.5),
                ),
              ),
              items: const [
                DropdownMenuItem(value: "QR", child: Text("QR")),
                DropdownMenuItem(value: "Efectivo", child: Text("Efectivo")),
                DropdownMenuItem(value: "Transferencia", child: Text("Transferencia")),
                DropdownMenuItem(value: "Tarjeta", child: Text("Tarjeta")),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    currentMetodoPago = val;
                  });
                }
              },
            ),
            const SizedBox(height: 24),

            // Comprobante de Pago
            Text(
              "Comprobante de Pago",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            if (currentComprobanteImg != null && currentComprobanteImg!.isNotEmpty)
              Stack(
                children: [
                  Container(
                    height: 240,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: TenantHelper.buildReceiptImage(currentComprobanteImg!),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: CircleAvatar(
                      backgroundColor: Colors.redAccent,
                      radius: 20,
                      child: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.white, size: 18),
                        onPressed: () {
                          setState(() {
                            currentComprobanteImg = null;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              )
            else
              InkWell(
                onTap: () async {
                  final path = await widget.onImagePicker();
                  if (path != null) {
                    setState(() {
                      currentComprobanteImg = path;
                    });
                  }
                },
                child: Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black12,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_upload_outlined, color: isDark ? Colors.white30 : Colors.black38, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        "Cargar imagen / comprobante",
                        style: TextStyle(
                          color: isDark ? Colors.white30 : Colors.black38,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 32),

            // Botón Comprobar / Comprobado
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: currentComprobado == 1
                          ? const Color(0xFF10B981) // Green
                          : const Color(0xFFEFA820), // Orange
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                    ),
                    onPressed: () {
                      if (Session().isAdmin) {
                        setState(() {
                          currentComprobado = (currentComprobado == 1) ? 0 : 1;
                        });
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Solo administradores pueden comprobar pagos"),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          currentComprobado == 1 ? Icons.check_circle : Icons.pending_actions,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          currentComprobado == 1 ? "COMPROBADO" : "COMPROBAR",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!Session().isAdmin) ...[
                  const SizedBox(height: 8),
                  const Text(
                    "Solo administradores pueden comprobar pagos",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
