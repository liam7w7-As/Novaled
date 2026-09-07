import 'dart:convert';
import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models/articulo.dart';
import '../models/cliente.dart';
import '../models/item_cotizacion.dart';
import '../services/pdf_service.dart';

class CrearCotizacionScreen extends StatefulWidget {
  const CrearCotizacionScreen({super.key});

  @override
  State<CrearCotizacionScreen> createState() => _CrearCotizacionScreenState();
}

class _CrearCotizacionScreenState extends State<CrearCotizacionScreen> {
  Cliente? _cliente;
  final List<ItemCotizacion> _items = [];
  double _descuento = 0.0;
  final double _iva = 0.13;
  bool _isSaved = false;

  double get _subtotal => _items.fold(0, (sum, item) => sum + item.total);
  double get _impuesto => _subtotal * _iva;
  double get _total => _subtotal + _impuesto - _descuento;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nueva Cotización")),
      body: Column(
        children: [
          ListTile(
            title: Text(_cliente?.nombreCompania ?? "Seleccionar Cliente",
                style: TextStyle(color: _cliente == null ? Colors.amber : Colors.white)),
            trailing: const Icon(Icons.person_add, color: Colors.amber),
            onTap: _seleccionarCliente,
          ),
          const Divider(color: Colors.grey),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text("Agregue artículos a la cotización"))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile(
                        title: Text(item.articulo.nombre),
                        subtitle: Text("${item.articulo.precio} Bs x ${item.cantidad}"),
                        trailing: Text("${item.total.toStringAsFixed(2)} Bs"),
                        leading: IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                          onPressed: () => setState(() => _items.removeAt(index)),
                        ),
                      );
                    },
                  ),
          ),
          _buildSummary(),
          _buildActions(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarArticulo,
        backgroundColor: Colors.amber,
        child: const Icon(Icons.add_shopping_cart, color: Colors.black),
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1F1F1F),
      child: Column(
        children: [
          _summaryRow("Subtotal", _subtotal),
          _summaryRow("IVA (13%)", _impuesto),
          _summaryRow("Total", _total, isBold: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text("${value.toStringAsFixed(2)} Bs",
              style: TextStyle(
                color: isBold ? Colors.amber : Colors.white,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              )),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _isSaved ? const Color(0xFF16A34A) : Colors.amber,
          minimumSize: const Size(double.infinity, 50),
        ),
        onPressed: _isSaved ? _generarPDF : _guardarCotizacion,
        child: Text(
          _isSaved ? "GENERAR PDF" : "GUARDAR COTIZACIÓN",
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _seleccionarCliente() async {
    final clientesRaw = await DatabaseHelper.instance.queryAllClientes();
    final clientes = clientesRaw.map((c) => Cliente.fromMap(c)).toList();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Seleccionar Cliente"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: clientes.length,
            itemBuilder: (context, index) {
              final c = clientes[index];
              return ListTile(
                title: Text(c.nombreCompania),
                onTap: () {
                  setState(() => _cliente = c);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _agregarArticulo() async {
    final articulosRaw = await DatabaseHelper.instance.queryAllArticulos();
    final articulos = articulosRaw.map((a) => Articulo.fromMap(a)).toList();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Agregar Artículo"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: articulos.length,
            itemBuilder: (context, index) {
              final a = articulos[index];
              return ListTile(
                title: Text(a.nombre),
                subtitle: Text("${a.precio} Bs"),
                onTap: () {
                  setState(() {
                    final existingIndex = _items.indexWhere((item) => item.articulo.id == a.id);
                    if (existingIndex != -1) {
                      _items[existingIndex].cantidad++;
                    } else {
                      _items.add(ItemCotizacion(articulo: a));
                    }
                  });
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _guardarCotizacion() async {
    if (_cliente == null || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Seleccione un cliente y al menos un artículo")),
      );
      return;
    }

    final cotizacion = {
      'clienteNombre': _cliente!.nombreCompania,
      'fecha': DateTime.now().toString().split(' ')[0],
      'subtotal': _subtotal,
      'impuesto': _impuesto,
      'descuento': _descuento,
      'total': _total,
      'itemsJson': jsonEncode(_items.map((i) => i.toMap()).toList()),
    };

    await DatabaseHelper.instance.insertCotizacion(cotizacion);
    
    setState(() {
      _isSaved = true;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("¡Cotización guardada! Ahora puede generar el PDF"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _generarPDF() async {
    await PdfService.generateCotizacion(
      clienteNombre: _cliente!.nombreCompania,
      items: _items,
      subtotal: _subtotal,
      impuesto: _impuesto,
      descuento: _descuento,
      total: _total,
    );

    if (!mounted) return;
    Navigator.pop(context);
  }
}
