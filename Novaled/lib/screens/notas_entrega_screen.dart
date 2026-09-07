import 'package:flutter/material.dart';
import '../database_helper.dart';

class NotasEntregaScreen extends StatefulWidget {
  const NotasEntregaScreen({super.key});

  @override
  State<NotasEntregaScreen> createState() => _NotasEntregaScreenState();
}

class _NotasEntregaScreenState extends State<NotasEntregaScreen> {
  List<Map<String, dynamic>> _notas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshNotas();
  }

  Future<void> _refreshNotas() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.queryAllNotasEntrega();
    setState(() {
      _notas = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("NOTAS DE ENTREGA"), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Lógica para crear nueva nota de entrega
        },
        label: const Text("Nueva Nota", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.black),
        backgroundColor: const Color(0xFFFFC107),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
        : _notas.isEmpty
          ? const Center(child: Text("No hay notas de entrega registradas", style: TextStyle(color: Colors.grey)))
          : RepaintBoundary(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _notas.length,
                itemBuilder: (context, index) {
                  final nota = _notas[index];
                  return Card(
                    color: const Color(0xFF1F1F1F),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text("Nota #${nota['id']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text("Cliente: ${nota['clienteNombre']}\nFecha: ${nota['fecha']}", style: const TextStyle(color: Colors.grey)),
                      trailing: Text("${nota['total']?.toStringAsFixed(2)} Bs", style: const TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.bold)),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
