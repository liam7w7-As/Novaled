# Novaled System - Flutter Migration

Sistema avanzado de gestión de productos y artes finales para Novaled, desarrollado en Flutter con integración profunda en Google Drive y estética Cian/Celeste (#00ADEF).

## 🚀 Características Principales

- **Compatibilidad Multiplataforma (Android, Windows, Web)**: Soporte completo para ejecución en navegadores y escritorio, con lógica de autenticación adaptada y persistencia universal.
- **Persistencia Híbrida**: Implementación de caché local mediante `shared_preferences` que permite carga instantánea al iniciar la aplicación en cualquier plataforma.
- **Interacción por Gestos**: Las tarjetas de la pantalla principal permiten un deslizamiento (Swipe) a la derecha para revelar el botón "GESTIONAR EN DRIVE", abriendo directamente la carpeta del producto.
- **Modelo de Datos Extendido**: Captura de especificaciones técnicas adicionales como **Watts** y **Marca**, integrados en el flujo de sincronización JSON y en el Google Doc informativo.
- **Sincronización con Google Drive**: Organización automática de productos en carpetas individuales con archivos `data.json` para metadatos y almacenamiento de imágenes.
- **Persistencia de Sesión (Windows)**: Implementación de almacenamiento local de tokens OAuth2, permitiendo el acceso automático sin re-autenticación en el navegador tras el primer inicio.
- **Gestión de Artes Finales**: Flujo de validación donde la subida de un arte final cambia el estado a "Listo", incluyendo limpieza automática de archivos redundantes.
- **Jerarquía de Salida Inteligente**: Clasificación automática en `ARTES FINALES / Familia / Subcategoría / Producto / CodTienda.ext`.
- **Seguridad y Confirmación**: Diálogos de advertencia críticos para el borrado definitivo de productos y la carga de arte final, evitando pérdidas accidentales.
- **Gestión Granular de Permisos**: Integración con `permission_handler` para compatibilidad total con Android 13+, manejando acceso a cámara y galería de forma segura.
- **Gestión Dinámica de Stock (v14)**: Sistema de Tiendas y Depósitos personalizables. El stock se distribuye dinámicamente entre ubicaciones creadas por el usuario en lugar de nombres estáticos.
- **Módulo de Cotizaciones y Documentos Pro**: Gestión integral de Cotizaciones, Notas de Entrega y Proformas con descuentos porcentuales, términos configurables y soporte para firmas.
- **Generación de PDF Unificada**: Motor de PDF único y parametrizable que garantiza consistencia visual en todos los tipos de documentos comerciales.
- **Arquitectura de UI Estandarizada**: Selector de clientes de alta visibilidad, diálogos de selección múltiple buscables y tarjetas de items editables en todos los módulos.
- **Sincronización de Inventario en Tiempo Real**: Capacidad de actualizar o crear artículos en la base de datos directamente desde el flujo de creación de documentos comerciales.
- **Visualización Avanzada**: Sistema de carga híbrida; miniaturas instantáneas en listas y descarga automática de **Alta Resolución (HD)** en previsualización a pantalla completa con zoom interactivo.
- **Acciones Masivas en HD**: Soporte para selección múltiple de productos para descargar o compartir archivos originales (no miniaturas) simultáneamente.
- **Categorización Dinámica**: CRUD de Familias y Subcategorías sincronizado con la nube a través de `config.json`.
- **Interfaz Moderna**: Menú lateral (Drawer) para navegación rápida y diseño optimizado con acentos cian/celeste (`#00ADEF`).
- **Temas Dinámicos (Claro/Oscuro)**: Soporte completo para personalización visual. El sistema detecta la preferencia del dispositivo y permite el cambio manual con persistencia.
- **Limpieza de Drive**: Capacidad de eliminar imágenes individuales directamente desde la galería para evitar archivos residuales.

## 🛠️ Configuración Técnica

### Autenticación
Requiere los scopes `drive.file` y `drive`. 
- **Android/Web**: Utiliza `google_sign_in`.
- **Windows**: Utiliza flujo de consentimiento via `googleapis_auth`.

### Configuración Windows
Para compilar en Windows, se requiere:
1. **Activar el Modo de Desarrollador**: `Configuración > Privacidad y seguridad > Para desarrolladores`.
2. **Visual Studio 2022**: Instalar la carga de trabajo **"Desarrollo para el escritorio con C++"** (incluyendo el SDK de Windows y herramientas MSVC).
   - *Sin esto, Flutter no podrá generar el ejecutable .exe.*

### 🔐 Seguridad y Roles
El sistema implementa un control de acceso basado en roles para optimizar el flujo de trabajo:
- **Encriptación**: Las contraseñas se validan mediante el algoritmo de hash **SHA-256**.
- **Jerarquía de Usuarios**:
    - **ADMINISTRADOR (Almir, Joel)**: Permiso total sobre el sistema, gestión de inventario, artes finales y configuración global.
    - **DISEÑADOR (Victor)**: Enfocado en la producción visual. Tiene permisos para cargar artes finales y gestionar datos técnicos.
    - **VENDEDOR (Gustavo)**: Responsable de la validación final. Posee un sistema de **"Ticket de Verificación"** que marca el producto como verificado globalmente tras revisar los datos físicos.

### 🏛️ Arquitectura de Módulos Comerciales
Los módulos de **Cotizaciones, Notas de Entrega y Proformas** comparten una base lógica y visual común:
- **Selección Multi-Item**: Diálogo con búsqueda inteligente que permite añadir múltiples productos de una sola vez.
- **Edición Dinámica**: Ajuste de cantidades, unidades de medida (U, Mts, Pq), precios y descuentos con recálculo instantáneo de subtotales y ahorros.
- **Persistencia Dual**: El toggle "Actualizar Inventario" automatiza la detección de nuevos productos (`id == null`) para inserción o la actualización de existentes en la base de datos `sqflite`.
- **Identidad Visual Consistente**: El `PdfService` utiliza plantillas profesionales que adaptan el título y contenido según el tipo de documento generado.

## 📦 Exportación y Distribución

### Windows (Escritorio)
Para generar el ejecutable final:
1. Ejecutar `flutter build windows --release`.
2. Localizar la carpeta: `build\windows\x64\runner\Release`.
3. **Distribución**: Se debe copiar la carpeta `Release` completa (incluyendo archivos `.dll`). Se recomienda comprimirla en `.zip` para su entrega.

### Android
Para generar el instalador:
1. Ejecutar `flutter build apk --release`.
2. El archivo se encuentra en: `build\app\outputs\flutter-apk\app-release.apk`.

SHA-1 para registro en Console (Android):
`D9:6F:88:CB:73:FD:8D:CA:7F:3E:9B:58:4D:A7:1D:32:D6:C8:4E:FF`

## 📁 Estructura de Carpetas en Drive

### Directorio de Trabajo (Carpeta Raíz)
- `/config.json`: Persistencia de Familias y Subcategorías.
- `/[Nombre_Producto]/`: Carpeta individual por producto.
  - `data.json`: Metadatos (familia, subcat, medidas, códigos).
  - `ImagenX.jpg`: Fotos del producto.
  - `ARTE_FINAL_...`: Copia local del arte final.
  - `Doc Informativo`: Google Doc con ficha técnica.

### Directorio de Artes Finales (Carpeta "ARTES FINALES")
- `/Familia/Subcategoría/Nombre_Producto/CodTienda.ext`

---
*Desarrollado para el ecosistema Novaled.*

## 📋 Estado del Proyecto
- [x] Implementar persistencia local (Caché) universal para carga instantánea.
- [x] Añadir campos "Watts" y "Marca" en UI y Drive.
- [x] Implementar gesto Swipe para abrir carpeta de Drive.
- [x] Añadir botón de borrado definitivo en inventario.
- [x] Permitir captura directa desde cámara en todas las secciones.
- [x] Integrar `permission_handler` para gestión granular en Android 13+.
- [x] Soporte multiplataforma completo (Windows, Web, Android).
- [x] Formatear Google Doc con jerarquía Categoría > Título.
- [x] Mostrar ficha técnica completa en Pantalla Principal.
- [x] Eliminar dos puntos internos en formato de medidas.
- [x] Implementar gestión dinámica de Tiendas y Depósitos (Stock Local).
- [x] Refactorizar módulo de Cotizaciones (Descuentos, Firmas, Notas).
- [x] Motor de PDF profesional con campos comerciales extendidos.
- [x] Implementar lógica de términos y firmas en Notas de Entrega y Proformas.
- [x] Acciones de deslizamiento (Swipe) para Duplicar, Borrar y Convertir documentos.
- [x] Buscador inteligente por cliente y número de documento.
- [x] Toggle de visibilidad de Términos y Condiciones en todos los documentos.
- [x] Reparación de errores de fuentes Unicode (Unicode support) en el motor de PDF.
- [x] Optimización de UI en menús de configuración (prevención de overflow).
- [x] Configuración predeterminada de visibilidad (Términos/Ahorro) establecida en "desactivado".
- [x] Corrección de errores de ciclo de vida (setState after dispose) al guardar artículos.
- [x] Estandarización de UI/UX y lógica de sincronización de inventario en todos los módulos comerciales.
- [x] Sistema de edición avanzada de items con recálculo en tiempo real y persistencia selectiva.
