import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String currentVersion = "3.1.4";
  static const int currentBuild = 94;

  static Future<void> buscarActualizacion(BuildContext context, {bool silent = false}) async {
    if (!silent) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(
          child: CircularProgressIndicator(color: Colors.orangeAccent),
        ),
      );
    }

    bool closedLoader = false;

    try {
      final response = await http.get(Uri.parse('https://novaledbolivia.com/sistema/version.json'));
      if (!silent) {
        Navigator.of(context, rootNavigator: true).pop(); // cerrar cargador seguro
        closedLoader = true;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String serverVersion = data['version'] ?? '1.0.0';
        final int serverBuild = int.tryParse(data['build_number'].toString()) ?? 0;

        if (serverBuild > currentBuild) {
          _mostrarDialogoActualizacion(context, serverVersion);
        } else {
          if (!silent) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Ya tienes la versión más reciente (v$currentVersion)."),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        throw Exception("Error de respuesta del servidor: ${response.statusCode}");
      }
    } catch (e) {
      if (!silent && !closedLoader) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al buscar actualización: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static void _mostrarDialogoActualizacion(BuildContext context, String nuevaVersion) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
          title: Text(
            "Actualización Disponible",
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
          ),
          content: Text(
            "Hay una nueva versión de la aplicación disponible (v$nuevaVersion).\n\n¿Desea descargarla e instalarla ahora?",
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(context);
                final url = Uri.parse("https://novaledbolivia.com/sistema/Novaled_v$nuevaVersion.apk");
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No se pudo abrir el enlace de descarga.")),
                  );
                }
              },
              child: const Text("DESCARGAR", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
