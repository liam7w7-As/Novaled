import 'dart:async';
import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models/cliente.dart';
import '../services/sync_service.dart';

class ClientsScreen extends StatefulWidget {
  final bool hideAppBar;
  const ClientsScreen({super.key, this.hideAppBar = false});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<Cliente> _clientes = [];
  bool _isLoading = true;

  bool _isSyncing = false;
  Cliente? _selectedCliente;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _refreshClientes().then((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _syncEverything(silent: true, isFirstSync: true);
          }
        });
      }
    });
    // Sincronización automática periódica en tiempo real (cada 10 segundos)
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_isSyncing) {
        _syncEverything(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshClientes({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.queryAllClientes();
    if (mounted) {
      setState(() {
        _clientes = data.map((e) => Cliente.fromMap(e)).toList();
        if (!silent) _isLoading = false;

        // Actualizar el cliente seleccionado con la información más reciente si fue editado,
        // o anular la selección si fue eliminado.
        if (_selectedCliente != null) {
          try {
            _selectedCliente = _clientes.firstWhere((c) => c.id == _selectedCliente!.id);
          } catch (_) {
            _selectedCliente = null;
          }
        }
      });
    }
  }

  Future<void> _syncEverything({bool silent = false, bool isFirstSync = false}) async {
    if (!mounted) return;
    setState(() => _isSyncing = true);

    BuildContext? loadingDialogContext;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isFirstSync) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          loadingDialogContext = dialogCtx;
          return PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              content: Row(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00ADEF)),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      "Cargando cambios recientes...",
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    try {
      final success = await SyncService.instance.syncTable('clientes').timeout(const Duration(seconds: 30));
      await _refreshClientes(silent: silent);
      
      if (!silent && mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Sincronización completa"), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Error de sincronización"), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint("Error sync clientes: $e");
      if (!silent && mounted) {
        final cleanMsg = e.toString().replaceFirst('Exception: ', '');
        final isOffline = cleanMsg.contains("Modo Offline");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOffline ? cleanMsg : "Error de sincronización: $cleanMsg"),
            backgroundColor: isOffline ? Colors.orange[800] : Colors.red,
            duration: Duration(seconds: isOffline ? 3 : 5),
          ),
        );
      }
    } finally {
      if (loadingDialogContext != null && loadingDialogContext!.mounted) {
        try {
          Navigator.pop(loadingDialogContext!);
        } catch (e) {
          debugPrint("Error cerrando diálogo de carga: $e");
        }
      }
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showClientDialog([Cliente? cliente]) {
    final nombreController = TextEditingController(text: cliente?.nombreCompania ?? "");
    final tlfController = TextEditingController(text: cliente?.telefono ?? "");
    final correoController = TextEditingController(text: cliente?.correo ?? "");
    final rnController = TextEditingController(text: cliente?.rn ?? "");
    final dir1Controller = TextEditingController(text: cliente?.direccion1 ?? "");
    final dir2Controller = TextEditingController(text: cliente?.direccion2 ?? "");
    final dir3Controller = TextEditingController(text: cliente?.direccion3 ?? "");
    final dirEnv1Controller = TextEditingController(text: cliente?.direccionEnvio1 ?? "");
    final dirEnv2Controller = TextEditingController(text: cliente?.direccionEnvio2 ?? "");
    final dirEnv3Controller = TextEditingController(text: cliente?.direccionEnvio3 ?? "");
    final infoController = TextEditingController(text: cliente?.infoAdicional ?? "");
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Calcular cuántas direcciones iniciales mostrar si ya tienen datos (en caso de edición)
    int visibleDirCount = 1;
    if (cliente != null) {
      if (cliente.direccion3 != null && cliente.direccion3!.trim().isNotEmpty) {
        visibleDirCount = 3;
      } else if (cliente.direccion2 != null && cliente.direccion2!.trim().isNotEmpty) {
        visibleDirCount = 2;
      }
    }

    int visibleDirEnvCount = 1;
    if (cliente != null) {
      if (cliente.direccionEnvio3 != null && cliente.direccionEnvio3!.trim().isNotEmpty) {
        visibleDirEnvCount = 3;
      } else if (cliente.direccionEnvio2 != null && cliente.direccionEnvio2!.trim().isNotEmpty) {
        visibleDirEnvCount = 2;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog.fullscreen(
              backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
              child: Scaffold(
                backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
                appBar: AppBar(
                  backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFF00ADEF),
                  foregroundColor: Colors.white,
                  title: Text(
                    cliente == null ? "Nuevo Cliente" : "Editar Cliente",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Información General",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF00ADEF) : const Color(0xFF0083B3),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildField("Nombre/Compañía *", nombreController),
                      const SizedBox(height: 12),
                      _buildField("Teléfono", tlfController),
                      const SizedBox(height: 12),
                      _buildField("Correo", correoController),
                      const SizedBox(height: 12),
                      _buildField("RN / NIT", rnController),
                      const SizedBox(height: 24),

                      // DIRECCIONES DE FACTURACIÓN
                      Text(
                        "Direcciones de Facturación",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF00ADEF) : const Color(0xFF0083B3),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildField("Dirección de Facturación 1", dir1Controller),
                      if (visibleDirCount >= 2) ...[
                        const SizedBox(height: 12),
                        _buildField("Dirección de Facturación 2", dir2Controller),
                      ],
                      if (visibleDirCount >= 3) ...[
                        const SizedBox(height: 12),
                        _buildField("Dirección de Facturación 3", dir3Controller),
                      ],
                      if (visibleDirCount < 3) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              visibleDirCount++;
                            });
                          },
                          icon: const Icon(Icons.add, color: Color(0xFF00ADEF)),
                          label: const Text(
                            "Agregar más dirección de facturación",
                            style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // DIRECCIONES DE ENVÍO
                      Text(
                        "Direcciones de Envío",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF00ADEF) : const Color(0xFF0083B3),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildField("Dirección de Envío 1", dirEnv1Controller),
                      if (visibleDirEnvCount >= 2) ...[
                        const SizedBox(height: 12),
                        _buildField("Dirección de Envío 2", dirEnv2Controller),
                      ],
                      if (visibleDirEnvCount >= 3) ...[
                        const SizedBox(height: 12),
                        _buildField("Dirección de Envío 3", dirEnv3Controller),
                      ],
                      if (visibleDirEnvCount < 3) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              visibleDirEnvCount++;
                            });
                          },
                          icon: const Icon(Icons.add, color: Color(0xFF00ADEF)),
                          label: const Text(
                            "Agregar más dirección de envío",
                            style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      Text(
                        "Otros Detalles",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF00ADEF) : const Color(0xFF0083B3),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildField("Información Adicional", infoController),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
                bottomNavigationBar: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                      color: isDark ? const Color(0xFF131A26) : Colors.white,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: const BorderSide(color: Colors.grey),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              "CANCELAR",
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: const Color(0xFF00ADEF),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              if (nombreController.text.trim().isEmpty) return;

                              final c = Cliente(
                                id: cliente?.id,
                                nombreCompania: nombreController.text.trim(),
                                telefono: tlfController.text.trim(),
                                correo: correoController.text.trim(),
                                rn: rnController.text.trim(),
                                direccion1: dir1Controller.text.trim(),
                                direccion2: visibleDirCount >= 2 ? dir2Controller.text.trim() : "",
                                direccion3: visibleDirCount >= 3 ? dir3Controller.text.trim() : "",
                                direccionEnvio1: dirEnv1Controller.text.trim(),
                                direccionEnvio2: visibleDirEnvCount >= 2 ? dirEnv2Controller.text.trim() : "",
                                direccionEnvio3: visibleDirEnvCount >= 3 ? dirEnv3Controller.text.trim() : "",
                                infoAdicional: infoController.text.trim(),
                                folderId: cliente?.folderId,
                              );

                              if (cliente == null) {
                                await DatabaseHelper.instance.insertCliente(c.toMap());
                              } else {
                                await DatabaseHelper.instance.updateCliente(c.toMap());
                              }

                              Navigator.pop(context);

                              SyncService.instance.syncTable('clientes').then((_) {
                                _refreshClientes();
                              });
                            },
                            child: Text(
                              cliente == null ? "AGREGAR" : "GUARDAR",
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildField(String label, TextEditingController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF00ADEF)),
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ADEF))),
      ),
    );
  }

  void _selectCliente(Cliente cli) {
    setState(() {
      _selectedCliente = cli;
    });
  }

  Future<void> _deleteClientAction(Cliente cli) async {
    // 1. Registrar borrado localmente para sincronización
    if (cli.folderId != null && cli.folderId!.isNotEmpty) {
      await DatabaseHelper.instance.recordDeletion('clientes', cli.folderId!);
    }
    // 2. Borrar local
    await DatabaseHelper.instance.deleteCliente(cli.id!);
    
    setState(() {
      if (_selectedCliente?.id == cli.id) {
        _selectedCliente = null;
      }
    });
    
    _refreshClientes();
    // 3. Sync silencioso
    _syncEverything(silent: true);
  }

  Future<void> _confirmDeleteClientDesktop(BuildContext context, Cliente cli) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        title: Text("Eliminar Cliente", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text("¿Deseas eliminar a ${cli.nombreCompania}?", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCELAR")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("ELIMINAR", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    
    if (confirm == true) {
      await _deleteClientAction(cli);
    }
  }

  Widget _buildNoSelectionView(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0F111A) : Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_pin,
              size: 80,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              "Selecciona un cliente para ver sus detalles",
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.w500
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientList(BuildContext context, List<Cliente> filteredClientes, bool isDark, bool isDesktop) {
    if (filteredClientes.isEmpty) {
      return Stack(
        children: [
          ListView(),
          Center(
            child: Text(
              _searchQuery.isNotEmpty
                ? "No se encontraron resultados"
                : "No hay clientes registrados. Desliza para sincronizar.",
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return RepaintBoundary(
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: filteredClientes.length,
        itemBuilder: (context, index) {
          final cli = filteredClientes[index];
          final isSelected = isDesktop && _selectedCliente?.id == cli.id;
          
          return Card(
            color: isSelected 
                ? (isDark ? const Color(0xFF1E2F3E) : const Color(0xFFE0F7FA))
                : (isDark ? const Color(0xFF1F1F1F) : Colors.white),
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected 
                    ? const Color(0xFF00ADEF) 
                    : (isDark ? Colors.transparent : Colors.grey[200]!),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: ListTile(
              onTap: () {
                if (isDesktop) {
                  _selectCliente(cli);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ClientDetailScreen(
                        cliente: cli,
                        onUpdate: _refreshClientes,
                      ),
                    ),
                  ).then((val) {
                    if (val == 'edit') {
                      _showClientDialog(cli);
                    } else if (val == 'delete') {
                      _deleteClientAction(cli);
                    }
                  });
                }
              },
              title: Text(
                "${index + 1}. ${cli.nombreCompania}", 
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  color: isDark ? Colors.white : Colors.black87
                )
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    "${cli.telefono.isNotEmpty ? cli.telefono : 'Sin teléfono'} | ${cli.correo.isNotEmpty ? cli.correo : 'Sin correo'}",
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  if (cli.rn.isNotEmpty || cli.direccion1.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      "${cli.rn.isNotEmpty ? 'RN: ${cli.rn}' : ''}${cli.rn.isNotEmpty && cli.direccion1.isNotEmpty ? ' | ' : ''}${cli.direccion1.isNotEmpty ? 'Dir: ${cli.direccion1}' : ''}",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 720;

    final filteredClientes = _clientes.where((c) {
      final query = _searchQuery.trim().toLowerCase();
      if (query.isEmpty) return true;
      return c.nombreCompania.toLowerCase().contains(query) ||
             c.rn.toLowerCase().contains(query);
    }).toList();

    Widget listPanel = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: "Buscar por nombre o RN/RUT...",
              hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600]),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF00ADEF)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = "";
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15.0),
                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15.0),
                borderSide: const BorderSide(color: Color(0xFF00ADEF), width: 2.0),
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              if (_clientes.isEmpty) {
                await _syncEverything();
              } else {
                await _refreshClientes();
              }
            },
            color: const Color(0xFF00ADEF),
            backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.grey[200],
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00ADEF)))
              : _buildClientList(context, filteredClientes, isDark, isDesktop),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: widget.hideAppBar ? null : AppBar(
        title: const Text("CLIENTES"), 
        centerTitle: true,
        actions: const [],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showClientDialog(),
        backgroundColor: const Color(0xFF00ADEF),
        child: const Icon(Icons.person_add, color: Colors.black),
      ),
      body: isDesktop
          ? Row(
              children: [
                Container(
                  width: 360,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: isDark ? Colors.white10 : Colors.black12,
                        width: 1,
                      ),
                    ),
                  ),
                  child: listPanel,
                ),
                Expanded(
                  child: _selectedCliente == null
                      ? _buildNoSelectionView(isDark)
                      : ClientDetailWidget(
                          cliente: _selectedCliente!,
                          isDark: isDark,
                          isDesktop: true,
                          onEdit: () => _showClientDialog(_selectedCliente),
                          onDelete: () => _confirmDeleteClientDesktop(context, _selectedCliente!),
                        ),
                ),
              ],
            )
          : listPanel,
    );
  }
}

class ClientDetailScreen extends StatelessWidget {
  final Cliente cliente;
  final VoidCallback onUpdate;

  const ClientDetailScreen({
    super.key,
    required this.cliente,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text("DETALLES DEL CLIENTE"),
        centerTitle: true,
      ),
      body: ClientDetailWidget(
        cliente: cliente,
        isDark: isDark,
        isDesktop: false,
        onEdit: () {
          Navigator.pop(context, 'edit');
        },
        onDelete: () {
          Navigator.pop(context, 'delete');
        },
      ),
    );
  }
}

class ClientDetailWidget extends StatelessWidget {
  final Cliente cliente;
  final bool isDark;
  final bool isDesktop;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ClientDetailWidget({
    super.key,
    required this.cliente,
    required this.isDark,
    required this.isDesktop,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            color: isDark ? const Color(0xFF161A22) : Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabecera con Avatar e Información Básica
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: const Color(0xFF00ADEF),
                        child: Text(
                          cliente.nombreCompania.trim().isEmpty 
                              ? "?" 
                              : cliente.nombreCompania.trim().substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.black, 
                            fontWeight: FontWeight.bold, 
                            fontSize: 28
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cliente.nombreCompania,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (cliente.rn.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00ADEF).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "RN / NIT: ${cliente.rn}",
                                  style: const TextStyle(
                                    color: Color(0xFF00ADEF),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12
                                  ),
                                ),
                              )
                            else
                              Text(
                                "Sin RN / NIT registrado",
                                style: TextStyle(
                                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 40, color: Colors.grey),
                  
                  // Secciones de Información
                  _buildSectionHeader("Información de Contacto", Icons.contact_mail),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.phone, "Teléfono", cliente.telefono.isNotEmpty ? cliente.telefono : "Sin teléfono registrado", isDark),
                  _buildDetailRow(Icons.email, "Correo Electrónico", cliente.correo.isNotEmpty ? cliente.correo : "Sin correo registrado", isDark),
                  if (cliente.infoAdicional.isNotEmpty)
                    _buildDetailRow(Icons.info_outline, "Información Adicional", cliente.infoAdicional, isDark),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader("Direcciones de Facturación", Icons.receipt_long),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.location_on_outlined, "Dirección 1", cliente.direccion1.isNotEmpty ? cliente.direccion1 : "No especificada", isDark),
                  if (cliente.direccion2.isNotEmpty)
                    _buildDetailRow(Icons.location_on_outlined, "Dirección 2", cliente.direccion2, isDark),
                  if (cliente.direccion3.isNotEmpty)
                    _buildDetailRow(Icons.location_on_outlined, "Dirección 3", cliente.direccion3, isDark),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader("Direcciones de Envío", Icons.local_shipping),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.local_shipping_outlined, "Dirección de Envío 1", cliente.direccionEnvio1.isNotEmpty ? cliente.direccionEnvio1 : "No especificada", isDark),
                  if (cliente.direccionEnvio2.isNotEmpty)
                    _buildDetailRow(Icons.local_shipping_outlined, "Dirección de Envío 2", cliente.direccionEnvio2, isDark),
                  if (cliente.direccionEnvio3.isNotEmpty)
                    _buildDetailRow(Icons.local_shipping_outlined, "Dirección de Envío 3", cliente.direccionEnvio3, isDark),
                  
                  const SizedBox(height: 40),
                  // Botones de Acción
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, color: Color(0xFF00ADEF), size: 18),
                        label: const Text("EDITAR", style: TextStyle(color: Color(0xFF00ADEF), fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF00ADEF)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                        label: const Text("ELIMINAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00ADEF), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF00ADEF),
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 0.5
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 6.0, bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                    fontWeight: FontWeight.w500
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black87
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
