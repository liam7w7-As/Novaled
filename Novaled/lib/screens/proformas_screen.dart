import 'package:flutter/material.dart';
import '../database_helper.dart';

class ProformasScreen extends StatefulWidget {
  const ProformasScreen({super.key});

  @override
  State<ProformasScreen> createState() => _ProformasScreenState();
}

class _ProformasScreenState extends State<ProformasScreen> {
  List<Map<String, dynamic>> _proformas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshProformas();
  }

  Future<void> _refreshProformas() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.queryAllProformas();
    setState(() {
      _proformas = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PROFORMAS (Ventas)"), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Lógica para crear nueva proforma
        },
        label: const Text("Nueva Proforma", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.black),
        backgroundColor: const Color(0xFFFFC107),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
        : _proformas.isEmpty
          ? const Center(child: Text("No hay proformas registradas", style: TextStyle(color: Colors.grey)))
          : RepaintBoundary(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _proformas.length,
                itemBuilder: (context, index) {
                  final item = _proformas[index];
                  return Card(
                    color: const Color(0xFF1F1F1F),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text("Proforma #${item['id']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text("Cliente: ${item['clienteNombre']}\nFecha: ${item['fecha']}", style: const TextStyle(color: Colors.grey)),
                      trailing: Text("${item['total']?.toStringAsFixed(2)} Bs", style: const TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.bold)),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
