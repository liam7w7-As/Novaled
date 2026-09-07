import 'package:flutter/material.dart';
import 'crear_cotizacion_screen.dart';
import '../database_helper.dart';

class CotizacionesScreen extends StatefulWidget {
  const CotizacionesScreen({super.key});

  @override
  State<CotizacionesScreen> createState() => _CotizacionesScreenState();
}

class _CotizacionesScreenState extends State<CotizacionesScreen> {
  List<Map<String, dynamic>> _cotizaciones = [];

  @override
  void initState() {
    super.initState();
    _refreshCotizaciones();
  }

  Future<void> _refreshCotizaciones() async {
    final data = await DatabaseHelper.instance.queryAllCotizaciones();
    setState(() {
      _cotizaciones = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Documentos")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CrearCotizacionScreen()),
        ).then((_) => _refreshCotizaciones()),
        label: const Text("Nueva Cotización", style: TextStyle(color: Colors.black)),
        icon: const Icon(Icons.add, color: Colors.black),
        backgroundColor: const Color(0xFFFFC107),
      ),
      body: _cotizaciones.isEmpty
          ? const Center(child: Text("No hay cotizaciones guardadas"))
          : ListView.builder(
              itemCount: _cotizaciones.length,
              itemBuilder: (context, index) {
                final cot = _cotizaciones[index];
                return ListTile(
                  title: Text("Cotización #${cot['id']}"),
                  subtitle: Text("Cliente: ${cot['clienteNombre']}\nFecha: ${cot['fecha']}"),
                  trailing: Text("${cot['total']?.toStringAsFixed(2)} Bs"),
                  onLongPress: () async {
                    await DatabaseHelper.instance.deleteCotizacion(cot['id']);
                    _refreshCotizaciones();
                  },
                );
              },
            ),
    );
  }
}
