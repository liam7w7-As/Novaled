import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../login_screen.dart';
import 'company_info_screen.dart';
import 'logo_size_screen.dart';
import 'agregar_foto_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showOpenAIKeyDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentKey = prefs.getString('openai_api_key') ?? prefs.getString('gemini_api_key') ?? '';
    final controller = TextEditingController(text: currentKey);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        title: Text(
          "Clave de API de OpenAI (ChatGPT)",
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Ingrese su API Key de OpenAI para habilitar el escaneo con IA.",
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: const InputDecoration(
                labelText: "OpenAI API Key",
                labelStyle: TextStyle(color: Color(0xFF00ADEF)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00ADEF)),
            onPressed: () async {
              await prefs.setString('openai_api_key', controller.text.trim());
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Clave guardada con éxito"), backgroundColor: Colors.green),
                );
              }
            },
            child: const Text(
              "GUARDAR",
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ajustes")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSettingsRow(
            context,
            "Información de la Compañía",
            Icons.business,
            () => Navigator.push(context, MaterialPageRoute(
              settings: const RouteSettings(name: '/ajustes/compania'),
              builder: (context) => const CompanyInfoScreen(),
            )),
          ),
          _buildSettingsRow(
            context,
            "Tamaño del Logo",
            Icons.image,
            () => Navigator.push(context, MaterialPageRoute(
              settings: const RouteSettings(name: '/ajustes/logo'),
              builder: (context) => const LogoSizeScreen(),
            )),
          ),
          _buildSettingsRow(
            context,
            "Fotos del Servicio",
            Icons.add_a_photo,
            () => Navigator.push(context, MaterialPageRoute(
              settings: const RouteSettings(name: '/ajustes/foto'),
              builder: (context) => const AgregarFotoScreen(),
            )),
          ),
          // Solo mostrar la configuración de OpenAI a los Developers/Dueños
          if (Session().role == UserRole.developer)
            _buildSettingsRow(
              context,
              "Configurar OpenAI API Key",
              Icons.key,
              () => _showOpenAIKeyDialog(context),
            ),
          _buildSettingsRow(
            context,
            "Importar Base de Datos",
            Icons.upload_file,
            () {},
          ),
          _buildSettingsRow(
            context,
            "Exportar Base de Datos",
            Icons.download_for_offline,
            () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsRow(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isDark ? Colors.transparent : Colors.grey[200]!),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF00ADEF)),
        title: Text(label, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
