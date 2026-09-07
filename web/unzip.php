<?php
/**
 * Script auxiliar para descompresión rápida en el servidor Hostinger.
 * Se auto-elimina inmediatamente después de ejecutarse.
 */

header('Content-Type: text/plain; charset=utf-8');

$zipFile = 'deploy.zip';

if (!file_exists($zipFile)) {
    die("ERROR: El archivo $zipFile no existe en este directorio.");
}

$zip = new ZipArchive();
if ($zip->open($zipFile) === TRUE) {
    // Extraer todo en el directorio actual (public_html/sistema/)
    if ($zip->extractTo(__DIR__)) {
        echo "SUCCESS: Archivos extraídos correctamente.\n";
    } else {
        echo "ERROR: No se pudieron extraer los archivos en el servidor.\n";
    }
    $zip->close();
    
    // Eliminar el archivo zip para no dejar basura
    if (unlink($zipFile)) {
        echo "SUCCESS: Archivo temporal $zipFile eliminado.\n";
    } else {
        echo "WARNING: No se pudo eliminar el archivo temporal $zipFile.\n";
    }
} else {
    echo "ERROR: No se pudo abrir el archivo ZIP.\n";
}

// Auto-eliminación del script por seguridad
if (unlink(__FILE__)) {
    echo "SUCCESS: Script de descompresión auto-eliminado con éxito.\n";
} else {
    echo "WARNING: No se pudo eliminar el script de descompresión.\n";
}
?>
