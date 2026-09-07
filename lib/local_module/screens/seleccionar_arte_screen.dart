import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../product_model.dart';
import '../../drive_service.dart';
import '../models/articulo.dart';

class SeleccionarArteScreen extends StatefulWidget {
  final List<Product> products;
  const SeleccionarArteScreen({super.key, required this.products});

  @override
  State<SeleccionarArteScreen> createState() => _SeleccionarArteScreenState();
}

class _SeleccionarArteScreenState extends State<SeleccionarArteScreen> {
  final DriveService _drive = DriveService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Cálculo dinámico para mantener tarjetas pequeñas (~150px)
    int crossAxisCount = (screenWidth / 150).floor().clamp(2, 12);
    double aspectRatio = screenWidth > 600 ? 1.0 : 0.85;

    // 1. Filtrar por búsqueda
    final filteredProducts = widget.products.where((p) {
      final query = _searchQuery.toLowerCase();
      return p.titulo.toLowerCase().contains(query) ||
             p.familia.toLowerCase().contains(query) ||
             p.subcategoria.toLowerCase().contains(query);
    }).toList();

    // 2. Agrupar por Familia y Subcategoría
    Map<String, Map<String, List<Product>>> grouped = {};
    for (var p in filteredProducts) {
      String f = p.familia.isEmpty ? "SIN CATEGORÍA" : p.familia.toUpperCase();
      String s = p.subcategoria.isEmpty ? "GENERAL" : p.subcategoria.toUpperCase();
      grouped.putIfAbsent(f, () => {});
      grouped[f]!.putIfAbsent(s, () => []);
      grouped[f]![s]!.add(p);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("SELECCIONAR ARTE FINAL", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Buscar producto...",
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF00ADEF), size: 20),
                  filled: true,
                  fillColor: isDark ? Colors.black26 : Colors.grey[200],
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: grouped.entries.map((familiaEntry) {
          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              visualDensity: VisualDensity.compact,
              title: Text(
                familiaEntry.key,
                style: const TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold, fontSize: 14),
              ),
              children: familiaEntry.value.entries.map((subcatEntry) {
                return ExpansionTile(
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    subcatEntry.key,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                  ),
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(4),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: aspectRatio,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: subcatEntry.value.length,
                      itemBuilder: (context, index) {
                        final p = subcatEntry.value[index];
                        
                        return Card(
                          color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(color: isDark ? Colors.transparent : Colors.grey[200]!),
                          ),
                          child: InkWell(
                            onTap: () {
                              // Construir una descripción rica heredada
                              List<String> info = [];
                              if (p.detalles.isNotEmpty) info.add(p.detalles);
                              if (p.watts.isNotEmpty) info.add("Watts: ${p.watts}");
                              if (p.medidas.isNotEmpty) {
                                String m = p.medidas.entries.map((e) => "${e.key}: ${e.value}").join(", ");
                                info.add("Medidas: $m");
                              }
                              info.add("Categoría: ${p.familia} / ${p.subcategoria}");

                              final nuevoArt = Articulo(
                                nombre: p.titulo,
                                precio: double.tryParse(p.precio) ?? 0.0,
                                precioCaja: 0.0,
                                descripcion: info.join("\n"),
                                folderId: p.folderId,
                                finalArtId: p.finalArtId,
                                codCaja: p.codCaja,
                                proveedor: p.marca.isNotEmpty ? p.marca : null,
                                familia: p.familia,
                                subcategoria: p.subcategoria,
                              );
                              Navigator.pop(context, nuevoArt);
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _ProductThumbnail(product: p, drive: _drive),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(5.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.titulo,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: isDark ? Colors.white : Colors.black87),
                                      ),
                                      Text(
                                        "Bs. ${p.precio}",
                                        style: const TextStyle(color: Color(0xFF00ADEF), fontSize: 9),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ProductThumbnail extends StatefulWidget {
  final Product product;
  final DriveService drive;

  const _ProductThumbnail({required this.product, required this.drive});

  @override
  State<_ProductThumbnail> createState() => _ProductThumbnailState();
}

class _ProductThumbnailState extends State<_ProductThumbnail> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _initFuture();
  }

  @override
  void didUpdateWidget(_ProductThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.product.folderId != oldWidget.product.folderId ||
        widget.product.finalArtId != oldWidget.product.finalArtId) {
      _initFuture();
    }
  }

  void _initFuture() {
    if (widget.product.folderId != null) {
      _future = widget.drive.getProductThumbnail(widget.product.folderId!, widget.product.finalArtId);
    } else {
      _future = Future.value(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Intentar sacar de caché primero
    final cached = widget.product.folderId != null ? widget.drive.thumbnailCache[widget.product.folderId] : null;
    if (cached != null) {
      return Image.memory(cached, fit: BoxFit.cover);
    }

    if (widget.product.folderId == null) {
      return Container(
        color: isDark ? Colors.black26 : Colors.grey[200],
        child: const Icon(Icons.image, color: Colors.grey, size: 24),
      );
    }

    // Si no está, pedirlo
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: isDark ? Colors.black12 : Colors.grey[100],
            child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(snapshot.data!, fit: BoxFit.cover);
        }
        return Container(
          color: isDark ? Colors.black26 : Colors.grey[200],
          child: const Icon(Icons.image, color: Colors.grey, size: 24),
        );
      },
    );
  }
}
