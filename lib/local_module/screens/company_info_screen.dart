import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CompanyInfoScreen extends StatefulWidget {
  const CompanyInfoScreen({super.key});

  @override
  State<CompanyInfoScreen> createState() => _CompanyInfoScreenState();
}

class _CompanyInfoScreenState extends State<CompanyInfoScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _infoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('comp_name') ?? "";
      _emailController.text = prefs.getString('comp_email') ?? "";
      _phoneController.text = prefs.getString('comp_phone') ?? "";
      _addressController.text = prefs.getString('comp_address') ?? "";
      _infoController.text = prefs.getString('comp_info') ?? "";
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('comp_name', _nameController.text);
    await prefs.setString('comp_email', _emailController.text);
    await prefs.setString('comp_phone', _phoneController.text);
    await prefs.setString('comp_address', _addressController.text);
    await prefs.setString('comp_info', _infoController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Información guardada")),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Info de Compañía")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildField("Nombre", _nameController),
            _buildField("Email", _emailController),
            _buildField("Teléfono", _phoneController),
            _buildField("Dirección", _addressController),
            _buildField("Info Adicional", _infoController, maxLines: 3),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00ADEF),
                  foregroundColor: Colors.black,
                ),
                child: const Text("Guardar"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ADEF))),
        ),
      ),
    );
  }
}
