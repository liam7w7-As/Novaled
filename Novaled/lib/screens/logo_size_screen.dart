import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogoSizeScreen extends StatefulWidget {
  const LogoSizeScreen({super.key});

  @override
  State<LogoSizeScreen> createState() => _LogoSizeScreenState();
}

class _LogoSizeScreenState extends State<LogoSizeScreen> {
  double _logoScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadScale();
  }

  Future<void> _loadScale() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _logoScale = prefs.getDouble('logo_scale') ?? 1.0;
    });
  }

  Future<void> _saveScale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('logo_scale', _logoScale);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Escala guardada")),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tamaño del Logo")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Ajustar escala del logo en PDF",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 32),
            Slider(
              value: _logoScale,
              min: 0.1,
              max: 2.0,
              divisions: 19,
              activeColor: const Color(0xFFFFC107),
              inactiveColor: Colors.grey[800],
              label: _logoScale.toStringAsFixed(2),
              onChanged: (value) {
                setState(() {
                  _logoScale = value;
                });
              },
            ),
            Text(
              _logoScale.toStringAsFixed(2),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveScale,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: Colors.black,
                  shape: RoundedCornerShape(12),
                ),
                child: const Text("Guardar", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RoundedCornerShape extends OutlinedBorder {
  final double radius;
  const RoundedCornerShape(this.radius);
  
  @override
  OutlinedBorder copyWith({BorderSide? side}) => this;
  
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();
  
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  }
  
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
  
  @override
  ShapeBorder scale(double t) => this;
}
