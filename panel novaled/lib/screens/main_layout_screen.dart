import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../services/empresa_service.dart';
import 'dashboard/dashboard_screen.dart';
import 'empresas/lista_empresas_screen.dart';
import 'planes/configuracion_planes_screen.dart';
import 'pagos/historial_pagos_screen.dart';
import 'auditoria/logs_screen.dart';
import 'backups/backups_screen.dart';

class MainLayoutScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const MainLayoutScreen({
    super.key,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _currentTabIndex = 0;

  void _navigateToTab(int index) {
    setState(() {
      _currentTabIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textDarkPrimary : AppColors.textLightPrimary;
    final textSecondary = isDark ? AppColors.textDarkSecondary : AppColors.textLightSecondary;
    final sidebarBg = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar de Navegación
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: sidebarBg,
              border: Border(right: BorderSide(color: border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Logo Novaled
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGold,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.flash_on_rounded, color: Colors.black87, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "NOVALED",
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: textPrimary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryPurple.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    "SUPERADMIN SAAS",
                                    style: GoogleFonts.poppins(
                                      fontSize: 9.0,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryPurple,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Consumer<EmpresaService>(
                        builder: (_, service, __) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: service.isOnline
                                  ? AppColors.success.withOpacity(0.12)
                                  : AppColors.danger.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: service.isOnline
                                    ? AppColors.success.withOpacity(0.3)
                                    : AppColors.danger.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: service.isOnline ? AppColors.success : AppColors.danger,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    service.isOnline ? "Servidor Online Conectado" : "Conectando al Servidor...",
                                    style: GoogleFonts.poppins(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: service.isOnline ? AppColors.success : AppColors.danger,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Divider(color: border, height: 1),
                const SizedBox(height: 16),

                // Lista de Menú
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      _buildNavItem(0, "Dashboard", Icons.dashboard_rounded, textPrimary, textSecondary),
                      _buildNavItem(1, "Empresas", Icons.business_rounded, textPrimary, textSecondary),
                      _buildNavItem(2, "Planes & Tarifas", Icons.workspace_premium_rounded, textPrimary, textSecondary),
                      _buildNavItem(3, "Facturación", Icons.receipt_long_rounded, textPrimary, textSecondary),
                      _buildNavItem(4, "Auditoría", Icons.history_rounded, textPrimary, textSecondary),
                      _buildNavItem(5, "Backups & Nube", Icons.cloud_sync_rounded, textPrimary, textSecondary),
                    ],
                  ),
                ),

                Divider(color: border, height: 1),
                // Footer / Switch Theme
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              widget.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                              size: 18,
                              color: textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                widget.isDarkMode ? "Modo Oscuro" : "Modo Claro",
                                style: GoogleFonts.poppins(fontSize: 12, color: textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onToggleTheme,
                        icon: Icon(
                          widget.isDarkMode ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                          color: AppColors.primaryGold,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Contenido Principal
          Expanded(
            child: _buildCurrentScreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String title, IconData icon, Color textPrimary, Color textSecondary) {
    final isSelected = _currentTabIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: InkWell(
        onTap: () => setState(() => _currentTabIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryGold : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.black87 : textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.black87 : textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentTabIndex) {
      case 0:
        return DashboardScreen(onNavigateTab: _navigateToTab);
      case 1:
        return const ListaEmpresasScreen();
      case 2:
        return const ConfiguracionPlanesScreen();
      case 3:
        return const HistorialPagosScreen();
      case 4:
        return const LogsScreen();
      case 5:
        return const BackupsScreen();
      default:
        return DashboardScreen(onNavigateTab: _navigateToTab);
    }
  }
}
