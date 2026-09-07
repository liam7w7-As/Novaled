import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/empresa_model.dart';
import '../../services/empresa_service.dart';

class EditarEmpresaModal extends StatefulWidget {
  final EmpresaModel empresa;

  const EditarEmpresaModal({super.key, required this.empresa});

  @override
  State<EditarEmpresaModal> createState() => _EditarEmpresaModalState();
}

class _EditarEmpresaModalState extends State<EditarEmpresaModal> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nombreCtrl;
  late TextEditingController _razonSocialCtrl;
  late TextEditingController _nitCtrl;
  late TextEditingController _telefonoCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _direccionCtrl;
  late TextEditingController _ciudadCtrl;
  late TextEditingController _notasCtrl;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.empresa.nombreComercial);
    _razonSocialCtrl = TextEditingController(text: widget.empresa.razonSocial);
    _nitCtrl = TextEditingController(text: widget.empresa.nitRut);
    _telefonoCtrl = TextEditingController(text: widget.empresa.telefono);
    _emailCtrl = TextEditingController(text: widget.empresa.emailContacto);
    _direccionCtrl = TextEditingController(text: widget.empresa.direccionPrincipal);
    _ciudadCtrl = TextEditingController(text: widget.empresa.ciudad);
    _notasCtrl = TextEditingController(text: widget.empresa.notasAdmin);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _razonSocialCtrl.dispose();
    _nitCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _direccionCtrl.dispose();
    _ciudadCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 700),
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPurple.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.edit_note_rounded, color: AppColors.primaryPurple, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Editar Empresa",
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            "Código: ${widget.empresa.codigoEmpresa}",
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: border, height: 1),
              const SizedBox(height: 16),

              Expanded(
                child: ListView(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            controller: _nombreCtrl,
                            label: "Nombre Comercial *",
                            isDark: isDark,
                            validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _nitCtrl,
                            label: "NIT / RUT / CI",
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _emailCtrl,
                            label: "Correo Electrónico *",
                            isDark: isDark,
                            validator: (v) => v == null || !v.contains('@') ? 'Email inválido' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _telefonoCtrl,
                            label: "Teléfono de Contacto",
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _ciudadCtrl,
                            label: "Ciudad",
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            controller: _direccionCtrl,
                            label: "Dirección Principal",
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _razonSocialCtrl,
                      label: "Razón Social Oficial",
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _notasCtrl,
                      label: "Notas Administrativas Internas",
                      isDark: isDark,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Divider(color: border, height: 1),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: border),
                    ),
                    child: Text(
                      "Cancelar",
                      style: GoogleFonts.poppins(color: textSecondary, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _guardarCambios,
                    icon: const Icon(Icons.save_rounded, size: 18, color: Colors.white),
                    label: Text(
                      "Guardar Cambios",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required bool isDark,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w500, color: textSecondary),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          validator: validator,
          maxLines: maxLines,
          style: GoogleFonts.poppins(fontSize: 13, color: textPrimary),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: isDark ? AppColors.cardDark : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryPurple, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    final updated = widget.empresa.copyWith(
      nombreComercial: _nombreCtrl.text.trim(),
      razonSocial: _razonSocialCtrl.text.trim(),
      nitRut: _nitCtrl.text.trim(),
      telefono: _telefonoCtrl.text.trim(),
      emailContacto: _emailCtrl.text.trim(),
      direccionPrincipal: _direccionCtrl.text.trim(),
      ciudad: _ciudadCtrl.text.trim(),
      notasAdmin: _notasCtrl.text.trim(),
    );

    final service = context.read<EmpresaService>();
    await service.actualizarEmpresa(updated);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Empresa \"${updated.nombreComercial}\" actualizada con éxito."),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
