import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models/articulo.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Articulo> _articulos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshArticulos();
  }

  Future<void> _refreshArticulos() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.queryAllArticulos();
    setState(() {
      _articulos = data.map((e) => Articulo.fromMap(e)).toList();
      _isLoading = false;
    });
  }

  void _showArticuloDialog([Articulo? articulo]) {
    final nombreController = TextEditingController(text: articulo?.nombre ?? "");
    final precioController = TextEditingController(text: articulo?.precio.toString() ?? "");
    final descController = TextEditingController(text: articulo?.descripcion ?? "");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: Text(articulo == null ? "Nuevo Artículo" : "Editar Artículo", 
                   style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField("Nombre", nombreController, TextInputType.text),
              const SizedBox(height: 12),
              _buildField("Precio (Bs)", precioController, TextInputType.number),
              const SizedBox(height: 12),
              _buildField("Descripción", descController, TextInputType.multiline),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC107)),
            onPressed: () async {
              if (nombreController.text.isEmpty) return;
              final a = Articulo(
                id: articulo?.id,
                nombre: nombreController.text,
                precio: double.tryParse(precioController.text) ?? 0.0,
                descripcion: descController.text,
              );
              if (articulo == null) {
                await DatabaseHelper.instance.insertArticulo(a.toMap());
              } else {
                await DatabaseHelper.instance.updateArticulo(a.toMap());
              }
              _refreshArticulos();
              Navigator.pop(context);
            },
            child: Text(articulo == null ? "AGREGAR" : "GUARDAR", 
                       style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, TextInputType type) {
    return TextField(
      controller: controller,
      keyboardType: type,
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
      appBar: AppBar(
        title: const Text("INVENTARIO", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showArticuloDialog(),
        backgroundColor: const Color(0xFFFFC107),
        child: const Icon(Icons.add, color: Colors.black, size: 30),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
        : _articulos.isEmpty
          ? const Center(child: Text("No hay artículos registrados", style: TextStyle(color: Colors.grey)))
          : RepaintBoundary( // Aísla el renderizado para evitar glitches
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _articulos.length,
                itemBuilder: (context, index) {
                  final art = _articulos[index];
                  return Card(
                    color: const Color(0xFF1F1F1F),
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      onTap: () => _showArticuloDialog(art),
                      title: Text(art.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text("${art.precio.toStringAsFixed(2)} Bs\n${art.descripcion}", 
                                    style: const TextStyle(color: Colors.grey)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 28),
                        onPressed: () => _confirmDelete(art),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  void _confirmDelete(Articulo art) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Eliminar?"),
        content: Text("Se borrará '${art.nombre}'"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("NO")),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteArticulo(art.id!);
              _refreshArticulos();
              Navigator.pop(context);
            },
            child: const Text("SÍ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
