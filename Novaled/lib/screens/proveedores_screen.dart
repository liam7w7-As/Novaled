import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models/proveedor.dart';

class ProveedoresScreen extends StatefulWidget {
  const ProveedoresScreen({super.key});

  @override
  State<ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends State<ProveedoresScreen> {
  List<Proveedor> _proveedores = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshProveedores();
  }

  Future<void> _refreshProveedores() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.queryAllProveedores();
    setState(() {
      _proveedores = data.map((e) => Proveedor.fromMap(e)).toList();
      _isLoading = false;
    });
  }

  void _showProveedorDialog([Proveedor? proveedor]) {
    final nombreController = TextEditingController(text: proveedor?.nombre ?? "");
    final tlfController = TextEditingController(text: proveedor?.telefono ?? "");
    final correoController = TextEditingController(text: proveedor?.correo ?? "");
    final dirController = TextEditingController(text: proveedor?.direccion ?? "");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: Text(proveedor == null ? "Nuevo Proveedor" : "Editar Proveedor", 
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
              const SizedBox(height: 12),
              _buildField("Dirección", dirController),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC107)),
            onPressed: () async {
              if (nombreController.text.isEmpty) return;
              final p = Proveedor(
                id: proveedor?.id,
                nombre: nombreController.text,
                telefono: tlfController.text,
                correo: correoController.text,
                direccion: dirController.text,
              );
              if (proveedor == null) {
                await DatabaseHelper.instance.insertProveedor(p.toMap());
              } else {
                await DatabaseHelper.instance.updateProveedor(p.toMap());
              }
              _refreshProveedores();
              Navigator.pop(context);
            },
            child: Text(proveedor == null ? "AGREGAR" : "GUARDAR", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
      appBar: AppBar(title: const Text("PROVEEDORES"), centerTitle: true),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProveedorDialog(),
        backgroundColor: const Color(0xFFFFC107),
        child: const Icon(Icons.person_add, color: Colors.black),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
        : _proveedores.isEmpty
          ? const Center(child: Text("No hay proveedores registrados", style: TextStyle(color: Colors.grey)))
          : RepaintBoundary(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _proveedores.length,
                itemBuilder: (context, index) {
                  final p = _proveedores[index];
                  return Card(
                    color: const Color(0xFF1F1F1F),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => _showProveedorDialog(p),
                      title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text("${p.telefono} | ${p.direccion}", style: const TextStyle(color: Colors.grey)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () async {
                          await DatabaseHelper.instance.deleteProveedor(p.id!);
                          _refreshProveedores();
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
