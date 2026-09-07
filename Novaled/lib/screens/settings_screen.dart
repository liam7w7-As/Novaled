import 'package:flutter/material.dart';
import 'company_info_screen.dart';
import 'logo_size_screen.dart';
import 'agregar_foto_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
            () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CompanyInfoScreen())),
          ),
          _buildSettingsRow(
            context,
            "Tamaño del Logo",
            Icons.image,
            () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LogoSizeScreen())),
          ),
          _buildSettingsRow(
            context,
            "Fotos del Servicio",
            Icons.add_a_photo,
            () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AgregarFotoScreen())),
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
    return Card(
      color: const Color(0xFF1F1F1F),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFFFC107)),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
