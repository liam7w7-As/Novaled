import 'package:flutter/material.dart';

class NovaledToast {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    IconData? icon,
    Duration duration = const Duration(seconds: 2),
  }) {
    // Bottom popups disabled as requested by user
    return;
  }

  static void proformaGenerada(BuildContext context) {
    show(context, "Se generó la proforma");
  }

  static void cotizacionGenerada(BuildContext context) {
    show(context, "Se generó la cotización");
  }

  static void notaEntregaGenerada(BuildContext context) {
    show(context, "Se generó la nota de entrega");
  }

  static void borrado(BuildContext context, {String message = "Borrado"}) {
    show(context, message);
  }

  static void copiado(BuildContext context, {String message = "Copiado"}) {
    show(context, message);
  }
}
