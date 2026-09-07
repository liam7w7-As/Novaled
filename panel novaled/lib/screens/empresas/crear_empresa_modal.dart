import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../services/empresa_service.dart';

class CrearEmpresaModal extends StatefulWidget {
  const CrearEmpresaModal({super.key});

  @override
  State<CrearEmpresaModal> createState() => _CrearEmpresaModalState();
}

class _CrearEmpresaModalState extends State<CrearEmpresaModal> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _razonSocialCtrl = TextEditingController();
  final _nitCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _ciudadCtrl = TextEditingController(text: 'La Paz');
  final _referenciaPagoCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();

  // Credenciales de Acceso
  final _usuarioCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _ocultarPass = true;
  String _rolUsuario = 'admin';

  String _planSeleccionado = 'pro_mensual'; // 'free', 'pro_mensual', 'pro_anual'
  bool _esTrial = false;
  int _diasTrial = 14;
  int _mesesPago = 1;
  String _metodoPago = 'Transferencia Bancaria';
  String _moneda = 'Bs.';

  void _generarClaveAleatoria() {
    final chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final randomStr = List.generate(8, (i) => chars[(DateTime.now().microsecondsSinceEpoch + i * 7) % chars.length]).join();
    setState(() {
      _passwordCtrl.text = "Nova@$randomStr";
    });
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
    _referenciaPagoCtrl.dispose();
    _notasCtrl.dispose();
    _usuarioCtrl.dispose();
    _passwordCtrl.dispose();
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
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 750),
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
                          color: AppColors.primaryGold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.add_business_rounded, color: AppColors.primaryGold, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Registrar Nueva Empresa",
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            "Alta de nuevo inquilino y asignación de plan",
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
              const SizedBox(height: 20),
              Divider(color: border, height: 1),
              const SizedBox(height: 16),

              // Formulario Scrolleable
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      "1. INFORMACIÓN DE LA EMPRESA",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            controller: _nombreCtrl,
                            label: "Nombre Comercial *",
                            hint: "Ej. Novaled Iluminación",
                            isDark: isDark,
                            validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _nitCtrl,
                            label: "NIT / CI / RUT",
                            hint: "Ej. 1029384021",
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
                            label: "Correo Oficial / Administrador *",
                            hint: "admin@empresa.com",
                            isDark: isDark,
                            validator: (v) => v == null || !v.contains('@') ? 'Email inválido' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _telefonoCtrl,
                            label: "Teléfono / WhatsApp",
                            hint: "+591 70000000",
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
                            hint: "La Paz",
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            controller: _direccionCtrl,
                            label: "Dirección Principal",
                            hint: "C. Isaac Tamayo #840",
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Text(
                      "2. CREDENCIALES DE ACCESO AL SISTEMA (USUARIO Y CONTRASEÑA)",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _usuarioCtrl,
                            label: "Usuario Inicial / Admin *",
                            hint: "Ej. novaled_admin",
                            isDark: isDark,
                            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa un usuario' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Contraseña *",
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _passwordCtrl,
                                obscureText: _ocultarPass,
                                validator: (v) => v == null || v.trim().length < 4 ? 'Mínimo 4 caracteres' : null,
                                style: GoogleFonts.poppins(fontSize: 13, color: textPrimary),
                                decoration: InputDecoration(
                                  hintText: "Contraseña segura",
                                  hintStyle: GoogleFonts.poppins(fontSize: 13, color: textSecondary.withOpacity(0.5)),
                                  filled: true,
                                  fillColor: isDark ? AppColors.cardDark : const Color(0xFFF1F5F9),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGold)),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(_ocultarPass ? Icons.visibility_off : Icons.visibility, size: 18, color: textSecondary),
                                        onPressed: () => setState(() => _ocultarPass = !_ocultarPass),
                                        tooltip: _ocultarPass ? "Ver contraseña" : "Ocultar",
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.auto_awesome, size: 18, color: AppColors.primaryGold),
                                        onPressed: _generarClaveAleatoria,
                                        tooltip: "Generar clave aleatoria",
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Text(
                      "3. SELECCIÓN DE PLAN Y TIER",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Selector de Tarjetas de Planes
                    Row(
                      children: [
                        Expanded(
                          child: _buildPlanOptionCard(
                            id: 'free',
                            title: 'Plan Free',
                            price: 'Bs. 0',
                            desc: '30 docs/mes • 1 usuario • Local',
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildPlanOptionCard(
                            id: 'pro_mensual',
                            title: 'PRO Mensual',
                            price: 'Bs. 150/mes',
                            desc: 'Ilimitado • Nube • Multiusuario',
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildPlanOptionCard(
                            id: 'pro_anual',
                            title: 'PRO Anual 👑',
                            price: 'Bs. 1500/año',
                            desc: '2 meses gratis • Ilimitado',
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Opciones si es PRO (Trial vs Pago Directo)
                    if (_planSeleccionado != 'free') ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.cardDark : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _esTrial,
                                      activeColor: AppColors.primaryPurple,
                                      onChanged: (val) {
                                        setState(() {
                                          _esTrial = val ?? false;
                                        });
                                      },
                                    ),
                                    Text(
                                      "Activar Periodo de Prueba (Trial Gratuito)",
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_esTrial)
                                  DropdownButton<int>(
                                    value: _diasTrial,
                                    dropdownColor: bg,
                                    underline: const SizedBox(),
                                    items: const [
                                      DropdownMenuItem(value: 7, child: Text("7 días")),
                                      DropdownMenuItem(value: 14, child: Text("14 días")),
                                      DropdownMenuItem(value: 30, child: Text("30 días")),
                                    ],
                                    onChanged: (v) => setState(() => _diasTrial = v ?? 14),
                                  ),
                              ],
                            ),
                            if (!_esTrial) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Método de Pago",
                                          style: GoogleFonts.poppins(fontSize: 11, color: textSecondary),
                                        ),
                                        const SizedBox(height: 4),
                                        DropdownButtonFormField<String>(
                                          value: _metodoPago,
                                          dropdownColor: bg,
                                          decoration: InputDecoration(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          items: const [
                                            DropdownMenuItem(value: 'Transferencia Bancaria', child: Text("Transferencia")),
                                            DropdownMenuItem(value: 'QR Simple', child: Text("QR Simple")),
                                            DropdownMenuItem(value: 'Efectivo', child: Text("Efectivo")),
                                            DropdownMenuItem(value: 'Tarjeta', child: Text("Tarjeta")),
                                          ],
                                          onChanged: (v) => setState(() => _metodoPago = v ?? 'Transferencia Bancaria'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _referenciaPagoCtrl,
                                      label: "Referencia / Comprobante",
                                      hint: "TRF-98214",
                                      isDark: isDark,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Divider(color: border, height: 1),
              const SizedBox(height: 16),

              // Botones de Acción
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
                    onPressed: _guardarEmpresa,
                    icon: const Icon(Icons.check_rounded, size: 18, color: Colors.black87),
                    label: Text(
                      "Crear Empresa",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGold,
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

  Widget _buildPlanOptionCard({
    required String id,
    required String title,
    required String price,
    required String desc,
    required bool isDark,
  }) {
    final isSelected = _planSeleccionado == id;
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;

    return InkWell(
      onTap: () => setState(() => _planSeleccionado = id),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryGold.withOpacity(0.12)
              : (isDark ? AppColors.cardDark : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primaryGold : (isDark ? AppColors.borderDark : AppColors.borderLight),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? AppColors.primaryGold : textPrimary,
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: AppColors.primaryGold, size: 16),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: GoogleFonts.poppins(fontSize: 10.5, color: AppColors.textDarkSecondary),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isDark,
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
          style: GoogleFonts.poppins(fontSize: 13, color: textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(fontSize: 12, color: textSecondary.withOpacity(0.6)),
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
              borderSide: const BorderSide(color: AppColors.primaryGold, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _guardarEmpresa() async {
    if (!_formKey.currentState!.validate()) return;

    final service = context.read<EmpresaService>();
    await service.crearEmpresa(
      nombreComercial: _nombreCtrl.text.trim(),
      razonSocial: _razonSocialCtrl.text.trim(),
      nitRut: _nitCtrl.text.trim(),
      telefono: _telefonoCtrl.text.trim(),
      emailContacto: _emailCtrl.text.trim(),
      direccionPrincipal: _direccionCtrl.text.trim(),
      ciudad: _ciudadCtrl.text.trim(),
      planId: _planSeleccionado,
      esTrial: _esTrial,
      diasTrial: _diasTrial,
      mesesPago: _mesesPago,
      metodoPago: _metodoPago,
      referenciaPago: _referenciaPagoCtrl.text.trim(),
      notasAdmin: _notasCtrl.text.trim(),
      usuarioAdmin: _usuarioCtrl.text.trim(),
      passwordAdmin: _passwordCtrl.text.trim(),
      rolUsuario: _rolUsuario,
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                "Empresa \"${_nombreCtrl.text.trim()}\" registrada exitosamente.",
                style: GoogleFonts.poppins(fontSize: 13),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}
