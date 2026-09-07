import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models/cliente.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<Cliente> _clientes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshClientes();
  }

  Future<void> _refreshClientes() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.queryAllClientes();
    setState(() {
      _clientes = data.map((e) => Cliente.fromMap(e)).toList();
      _isLoading = false;
    });
  }

  void _showClientDialog([Cliente? cliente]) {
    final nombreController = TextEditingController(text: cliente?.nombreCompania ?? "");
    final tlfController = TextEditingController(text: cliente?.telefono ?? "");
    final correoController = TextEditingController(text: cliente?.correo ?? "");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: Text(cliente == null ? "Nuevo Cliente" : "Editar Cliente", 
                   style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField("Nombre/Compañía", nombreController),
              const SizedBox(height: 12),
              _buildField("Teléfono", tlfController),
              const SizedBox(height: 12),
              _buildField("Correo", correoController),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC107)),
            onPressed: () async {
              if (nombreController.text.isEmpty) return;
              final c = Cliente(
                id: cliente?.id,
                nombreCompania: nombreController.text,
                telefono: tlfController.text,
                correo: correoController.text,
              );
              if (cliente == null) {
                await DatabaseHelper.instance.insertCliente(c.toMap());
              } else {
                await DatabaseHelper.instance.updateCliente(c.toMap());
              }
              _refreshClientes();
              Navigator.pop(context);
            },
            child: Text(cliente == null ? "AGREGAR" : "GUARDAR", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFFFFC107)),
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFC107))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("CLIENTES"), centerTitle: true),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showClientDialog(),
        backgroundColor: const Color(0xFFFFC107),
        child: const Icon(Icons.person_add, color: Colors.black),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
        : _clientes.isEmpty
          ? const Center(child: Text("No hay clientes registrados", style: TextStyle(color: Colors.grey)))
          : RepaintBoundary(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _clientes.length,
                itemBuilder: (context, index) {
                  final cli = _clientes[index];
                  return Card(
                    color: const Color(0xFF1F1F1F),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => _showClientDialog(cli),
                      title: Text(cli.nombreCompania, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text("${cli.telefono} | ${cli.correo}", style: const TextStyle(color: Colors.grey)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () async {
                          await DatabaseHelper.instance.deleteCliente(cli.id!);
                          _refreshClientes();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
