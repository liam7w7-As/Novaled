# Sistema de Ventas Novaled

Aplicación Flutter diseñada para la gestión de documentos de ventas, incluyendo Cotizaciones, Notas de Entrega y Proformas.

## Estado del Proyecto
Actualmente, el sistema se encuentra en una fase estable con los módulos comerciales principales implementados y funcionales.

### Módulos Implementados
- **Cotizaciones:** Creación y gestión de presupuestos.
- **Notas de Entrega:** Gestión de despachos con personalización de ítems.
- **Proformas:** Generación de documentos proforma.

### Características Clave
- **Lógica de Términos y Firmas:** [COMPLETADO] Implementada y verificada en todos los módulos de creación de documentos. Permite personalizar los términos legales y las firmas en el PDF generado.
- **Personalización de Ítems:** Capacidad para editar descripciones, cantidades y unidades al momento de generar documentos.
- **Estándar Visual:**
  - Color Institucional: Cian (#00ADEF).
  - Logos: Tamaño estándar de 160pt para una presentación profesional.
  - Generación de PDF: Tablas optimizadas para claridad y profesionalismo.

## Desarrollo y Compilación
Para compilar la versión de escritorio para Windows:
```bash
flutter build windows
```

## Correcciones Recientes
- Se resolvieron errores de sintaxis críticos en `crear_nota_entrega_screen.dart` y `crear_proforma_screen.dart` relacionados con el uso de `showDialog` y `StatefulBuilder`.
- Estandarización de interfaz y lógica de sincronización de inventario en todos los módulos comerciales.
