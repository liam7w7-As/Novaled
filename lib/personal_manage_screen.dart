import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'drive_service.dart';
import 'login_screen.dart';
import 'main.dart';
import 'local_module/tenant_helper.dart';

class PersonalManageScreen extends StatefulWidget {
  final bool hideAppBar;
  const PersonalManageScreen({super.key, this.hideAppBar = false});

  @override
  State<PersonalManageScreen> createState() => _PersonalManageScreenState();
}

class _PersonalManageScreenState extends State<PersonalManageScreen> {
  final DriveService _drive = DriveService();
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  
  String _selectedRole = 'seller'; // 'admin', 'designer', 'seller'
  bool _isSaving = false;
  bool _isLoading = true;

  // Lista local para mostrar
  List<Map<String, dynamic>> _customUsers = [];
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    // Validar acceso solo para administradores
    if (Session().role != UserRole.admin && Session().role != UserRole.developer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Acceso denegado: Solo el administrador o dueño puede gestionar el personal"),
            backgroundColor: Colors.redAccent,
          ),
        );
        Navigator.pop(context);
      });
    }
    _loadUsersData();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_isLoading) {
        _loadUsersData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Widget _buildRoleChip({
    required String label,
    required IconData icon,
    required Color color,
    required UserRole role,
    required String roleName,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ActionChip(
      avatar: Icon(icon, color: color, size: 16),
      label: Text(
        label,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      backgroundColor: isDark ? const Color(0xFF0B0C10) : Colors.grey[200],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.4)),
      ),
      onPressed: () {
        Session().originalUserName ??= Session().userName;
        Session().originalRole ??= Session().role;
        Session().userName = "PRUEBA_$roleName";
        Session().role = role;

        sessionNotifier.value++;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Viendo el sistema como: $roleName"),
            backgroundColor: const Color(0xFF10B981),
          ),
        );

        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      },
    );
  }

  Future<void> _loadUsersData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    
    // 1. Cargar caché local primero
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('novaled_custom_users');
    if (cached != null) {
      try {
        if (mounted) {
          setState(() {
            _customUsers = List<Map<String, dynamic>>.from(jsonDecode(cached));
          });
        }
      } catch (e) {
        debugPrint("Error decodificando caché de usuarios: $e");
      }
    }

    // 2. Sincronizar desde la base de datos MySQL
    try {
      final token = prefs.getString('novaled_jwt_token') ?? '';
      final response = await http.get(
        Uri.parse('https://novaledbolivia.com/sistema/api/get_users.php'),
        headers: {
          'Authorization': 'Bearer $token',
          'X-Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final List<dynamic> decoded = jsonDecode(response.body);
        final driveUsers = List<Map<String, dynamic>>.from(decoded);
        if (driveUsers.isNotEmpty) {
          await prefs.setString('novaled_custom_users', jsonEncode(driveUsers));
          if (mounted) {
            setState(() {
              _customUsers = driveUsers;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error sincronizando usuarios de MySQL: $e");
    } finally {
      if (mounted) {
        setState(() {
          if (!silent) _isLoading = false;
        });
      }
    }
  }

  String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  Future<void> _addUser() async {
    if (!_formKey.currentState!.validate()) return;
    
    final username = _userController.text.trim();
    final password = _passController.text;

    // Validar duplicados con existentes de manera insensible a mayúsculas
    if (_customUsers.any((u) => u['username'].toString().toLowerCase().trim() == username.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("El usuario ya se encuentra registrado"), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final canAdd = await PlanLimitHelper.canCreateUser(_customUsers.length);
    if (!canAdd) {
      if (mounted) {
        final isFree = await TenantHelper.isFreePlan();
        PlanLimitHelper.showUpgradeDialog(
          context,
          feature: "usuarios creados",
          currentLimit: isFree ? PlanLimitHelper.freeUsuarios : PlanLimitHelper.proUsuarios,
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      final newUser = {
        "username": username,
        "passwordHash": _hashPassword(password),
        "role": _selectedRole,
        "createdAt": DateTime.now().toIso8601String(),
      };

      // Clonar y agregar
      final updatedList = List<Map<String, dynamic>>.from(_customUsers)..add(newUser);

      // Guardar localmente
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('novaled_custom_users', jsonEncode(updatedList));

      // Subir a la base de datos MySQL
      final token = prefs.getString('novaled_jwt_token') ?? '';
      final response = await http.post(
        Uri.parse('https://novaledbolivia.com/sistema/api/save_users.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Authorization': 'Bearer $token',
        },
        body: jsonEncode(updatedList),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception("Error del servidor (${response.statusCode}): ${response.body}");
      }

      if (mounted) {
        setState(() {
          _customUsers = updatedList;
          _userController.clear();
          _passController.clear();
          _selectedRole = 'seller';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Personal agregado exitosamente"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al guardar en la nube: $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteUser(String username) async {
    final currentSessionUser = Session().userName?.toLowerCase().trim();
    if (username.toLowerCase().trim() == currentSessionUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No puedes eliminar a tu propio usuario activo"), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final admins = _customUsers.where((u) => u['role']?.toString() == 'admin' || u['role']?.toString() == 'developer').toList();
    final targetUser = _customUsers.firstWhere((u) => u['username'].toString().toLowerCase().trim() == username.toLowerCase().trim(), orElse: () => <String, dynamic>{});
    if (targetUser.isNotEmpty && (targetUser['role'] == 'admin' || targetUser['role'] == 'developer') && admins.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se puede eliminar al último Administrador o Developer del sistema"), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Eliminar Personal"),
        content: Text("¿Está seguro que desea eliminar a '$username'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("CANCELAR")),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("ELIMINAR"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final updatedList = List<Map<String, dynamic>>.from(_customUsers)
        ..removeWhere((u) => u['username'].toString().toLowerCase().trim() == username.toLowerCase().trim());

      // Guardar localmente
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('novaled_custom_users', jsonEncode(updatedList));

      // Subir a la base de datos MySQL
      final token = prefs.getString('novaled_jwt_token') ?? '';
      final response = await http.post(
        Uri.parse('https://novaledbolivia.com/sistema/api/save_users.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Authorization': 'Bearer $token',
        },
        body: jsonEncode(updatedList),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception("Error del servidor (${response.statusCode}): ${response.body}");
      }

      if (mounted) {
        setState(() {
          _customUsers = updatedList;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("🗑️ Personal eliminado con éxito"), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al sincronizar cambio: $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final username = user['username']?.toString() ?? "";
    String selectedRole = user['role']?.toString() ?? "seller";
    final editPassController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) {
        final isDark = Theme.of(c).brightness == Brightness.dark;
        final primaryCyan = const Color(0xFF00ADEF);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1F2833) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.edit, color: primaryCyan),
                  const SizedBox(width: 10),
                  Text("Editar Personal: $username"),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: editPassController,
                      obscureText: true,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        labelText: "Nueva Contraseña",
                        helperText: "Dejar vacío para no cambiar",
                        helperStyle: const TextStyle(fontSize: 10),
                        labelStyle: TextStyle(color: isDark ? Colors.grey : Colors.grey[700], fontSize: 12),
                        prefixIcon: Icon(Icons.lock, color: primaryCyan),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      validator: (val) {
                        if (val != null && val.isNotEmpty && val.length < 4) {
                          return "Mínimo 4 caracteres";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Rol en el Sistema:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      dropdownColor: isDark ? const Color(0xFF1F2833) : Colors.white,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'seller', child: Text("Vendedor")),
                        DropdownMenuItem(value: 'designer', child: Text("Diseñador")),
                        DropdownMenuItem(value: 'admin', child: Text("Administrador")),
                        DropdownMenuItem(value: 'developer', child: Text("Developer/Dueño")),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedRole = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text("CANCELAR"),
                ),
                TextButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(c, true);
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: primaryCyan),
                  child: const Text("GUARDAR"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm != true) return;

    final currentSessionUser = Session().userName?.toLowerCase().trim();
    if (username.toLowerCase().trim() == currentSessionUser && (selectedRole != 'admin' && selectedRole != 'developer')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No puedes degradar tu propio rol administrativo"), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedList = _customUsers.map((u) {
        if (u['username'].toString().toLowerCase().trim() == username.toLowerCase().trim()) {
          final updatedUser = Map<String, dynamic>.from(u);
          updatedUser['role'] = selectedRole;
          if (editPassController.text.isNotEmpty) {
            updatedUser['passwordHash'] = _hashPassword(editPassController.text);
          }
          return updatedUser;
        }
        return u;
      }).toList();

      // Guardar localmente
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('novaled_custom_users', jsonEncode(updatedList));

      // Subir a la base de datos MySQL
      final token = prefs.getString('novaled_jwt_token') ?? '';
      final response = await http.post(
        Uri.parse('https://novaledbolivia.com/sistema/api/save_users.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Authorization': 'Bearer $token',
        },
        body: jsonEncode(updatedList),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception("Error del servidor (${response.statusCode}): ${response.body}");
      }

      if (mounted) {
        setState(() {
          _customUsers = updatedList;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Personal actualizado correctamente"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al guardar cambios: $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      editPassController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryCyan = const Color(0xFF00ADEF);
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 750;

    Widget formWidget = Card(
      elevation: 4,
      color: isDark ? const Color(0xFF1F2833) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_add_rounded, color: primaryCyan, size: 28),
                  const SizedBox(width: 10),
                  const Text(
                    "Registrar Nuevo Personal",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _userController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: "Nombre de Usuario",
                  labelStyle: TextStyle(color: isDark ? Colors.grey : Colors.grey[700]),
                  prefixIcon: Icon(Icons.person, color: primaryCyan),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: primaryCyan, width: 2),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return "Ingrese el nombre de usuario";
                  if (val.trim().contains(" ")) return "No se permiten espacios en el usuario";
                  return null;
                },
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _passController,
                obscureText: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: "Contraseña",
                  labelStyle: TextStyle(color: isDark ? Colors.grey : Colors.grey[700]),
                  prefixIcon: Icon(Icons.lock, color: primaryCyan),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: primaryCyan, width: 2),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return "Ingrese la contraseña";
                  if (val.trim().length < 4) return "Mínimo 4 caracteres";
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text(
                "Asignar Rol en el Sistema:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white70 : Colors.black87),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedRole,
                dropdownColor: isDark ? const Color(0xFF1F2833) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: 'seller', child: Text("Vendedor (Visualizar, proformas)")),
                  DropdownMenuItem(value: 'designer', child: Text("Diseñador (Subir artes finales)")),
                  DropdownMenuItem(value: 'admin', child: Text("Administrador (Control total)")),
                  DropdownMenuItem(value: 'developer', child: Text("Developer/Dueño (Permiso total)")),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedRole = val);
                },
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _addUser,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryCyan,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 3,
                  ),
                  child: _isSaving 
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text("AGREGAR PERSONAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final List<Widget> listItems = [
      if (_customUsers.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(
            child: Text(
              "No hay personal registrado",
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          ),
        )
      else
        ..._customUsers.map((user) {
          final name = user['username']?.toString() ?? "";
          final role = user['role']?.toString() ?? "seller";
          
          Color badgeColor = Colors.orange;
          String roleLabel = "Vendedor";
          IconData leadIcon = Icons.store;
          
          if (role == 'developer') {
            badgeColor = Colors.purpleAccent;
            roleLabel = "Developer/Dueño";
            leadIcon = Icons.code;
          } else if (role == 'admin') {
            badgeColor = Colors.redAccent;
            roleLabel = "Administrador";
            leadIcon = Icons.admin_panel_settings;
          } else if (role == 'designer') {
            badgeColor = primaryCyan;
            roleLabel = "Diseñador";
            leadIcon = Icons.brush;
          }

          return Card(
            color: isDark ? const Color(0xFF0B0C10) : Colors.grey[50],
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: badgeColor.withOpacity(0.2),
                child: Icon(leadIcon, color: badgeColor, size: 20),
              ),
              title: Text(
                name,
                style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
              ),
              subtitle: Text("Rol: $roleLabel", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility, color: Colors.greenAccent),
                    onPressed: () {
                      UserRole targetRole = UserRole.seller;
                      if (role == 'developer') {
                        targetRole = UserRole.developer;
                      } else if (role == 'admin') {
                        targetRole = UserRole.admin;
                      } else if (role == 'designer') {
                        targetRole = UserRole.designer;
                      }

                      Session().originalUserName ??= Session().userName;
                      Session().originalRole ??= Session().role;
                      Session().userName = name;
                      Session().role = targetRole;

                      sessionNotifier.value++;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Viendo el sistema como $name ($roleLabel)"),
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      );

                      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                    },
                    tooltip: "Ver como",
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blueAccent),
                    onPressed: () => _editUser(user),
                    tooltip: "Editar personal",
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => _deleteUser(name),
                    tooltip: "Eliminar personal",
                  ),
                ],
              ),
            ),
          );
        }),
    ];

    Widget impersonateSelectorWidget = Card(
      elevation: 2,
      color: isDark ? const Color(0xFF1F2833) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.visibility_outlined, color: primaryCyan, size: 22),
                const SizedBox(width: 8),
                Text(
                  "Ver como Rango: ¿Ver como cuál rango?",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildRoleChip(
                  label: "Vendedor",
                  icon: Icons.store,
                  color: Colors.orange,
                  role: UserRole.seller,
                  roleName: "Vendedor",
                ),
                _buildRoleChip(
                  label: "Diseñador",
                  icon: Icons.brush,
                  color: Colors.cyan,
                  role: UserRole.designer,
                  roleName: "Diseñador",
                ),
                _buildRoleChip(
                  label: "Almacenes",
                  icon: Icons.admin_panel_settings,
                  color: Colors.redAccent,
                  role: UserRole.admin,
                  roleName: "Almacenes",
                ),
                _buildRoleChip(
                  label: "Dueño",
                  icon: Icons.code,
                  color: Colors.purpleAccent,
                  role: UserRole.developer,
                  roleName: "Dueño",
                ),
              ],
            ),
          ],
        ),
      ),
    );

    Widget listWidget = Card(
      elevation: 2,
      color: isDark ? const Color(0xFF1F2833) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                "Personal Registrado (${_customUsers.length})",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
              ),
            ),
            const Divider(color: Colors.white10),
            if (isMobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: listItems,
              )
            else
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: listItems,
                ),
              ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0C10) : Colors.grey[50],
      appBar: widget.hideAppBar ? null : AppBar(
        title: const Text("GESTIÓN DE PERSONAL"),
        backgroundColor: isDark ? const Color(0xFF1F2833) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        actions: const [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isMobile
              ? ListView(
                  padding: const EdgeInsets.all(15),
                  children: [
                    impersonateSelectorWidget,
                    const SizedBox(height: 15),
                    formWidget,
                    const SizedBox(height: 20),
                    listWidget,
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: impersonateSelectorWidget,
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: formWidget,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 20, bottom: 20),
                              child: listWidget,
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
