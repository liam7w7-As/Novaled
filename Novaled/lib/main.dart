import 'package:flutter/material.dart';
import 'screens/inventory_screen.dart';
import 'screens/clients_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/cotizaciones_screen.dart';
import 'screens/agregar_foto_screen.dart';
import 'screens/proveedores_screen.dart';
import 'screens/notas_entrega_screen.dart';
import 'screens/proformas_screen.dart';

void main() {
  runApp(const NovaledApp());
}

class NovaledApp extends StatelessWidget {
  const NovaledApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Novaled',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFC107),
          onPrimary: Colors.black,
          surface: Color(0xFF1F1F1F),
          secondary: Color(0xFFFFC107),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const CotizacionesScreen(),
    const InventoryScreen(),
    const ClientsScreen(),
    const SettingsScreen(),
  ];

  void changeTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: _screens,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: Colors.black,
        selectedItemColor: const Color(0xFFFFC107),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Inicio"),
          BottomNavigationBarItem(icon: Icon(Icons.description), label: "Docs"),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: "Inventario"),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: "Clientes"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Ajustes"),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("novaled", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: [
          _buildDashCard(context, "Inventario", Icons.inventory_2, const Color(0xFFCA8A04), 2),
          _buildDashCard(context, "Clientes", Icons.people, const Color(0xFF6B7280), 3),
          _buildDashCard(context, "Cotizaciones", Icons.calculate, const Color(0xFF78350F), 1),
          _buildDashCard(context, "Nota Entrega", Icons.local_shipping, const Color(0xFF16A34A), -2),
          _buildDashCard(context, "Proforma", Icons.receipt_long, const Color(0xFF9333EA), -3),
          _buildDashCard(context, "Proveedor", Icons.store, const Color(0xFF2563EB), -4),
          _buildDashCard(context, "Servicio", Icons.build, const Color(0xFF0369A1), -1),
        ],
      ),
    );
  }

  Widget _buildDashCard(BuildContext context, String title, IconData icon, Color color, int index) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (index == -1) {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AgregarFotoScreen()));
            } else if (index == -2) {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const NotasEntregaScreen()));
            } else if (index == -3) {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ProformasScreen()));
            } else if (index == -4) {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ProveedoresScreen()));
            } else {
              final mainState = context.findAncestorStateOfType<_MainScreenState>();
              mainState?.changeTab(index);
            }
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 48),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}
