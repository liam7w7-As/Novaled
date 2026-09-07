import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'services/empresa_service.dart';
import 'services/backup_service.dart';
import 'screens/main_layout_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PanelNovaledApp());
  try {
    await EmpresaService.instance.inicializar();
  } catch (e) {
    debugPrint("[PANEL] Error en inicializar(): $e");
  }
}

class PanelNovaledApp extends StatefulWidget {
  const PanelNovaledApp({super.key});

  @override
  State<PanelNovaledApp> createState() => _PanelNovaledAppState();
}

class _PanelNovaledAppState extends State<PanelNovaledApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: EmpresaService.instance),
        ChangeNotifierProvider.value(value: BackupService.instance),
      ],
      child: MaterialApp(
        title: 'Panel SuperAdmin - Novaled Sistema',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,
        home: MainLayoutScreen(
          onToggleTheme: _toggleTheme,
          isDarkMode: _themeMode == ThemeMode.dark,
        ),
      ),
    );
  }
}
