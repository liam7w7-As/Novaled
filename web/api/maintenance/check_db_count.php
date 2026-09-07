<?php
require_once 'config.php';

try {
    echo "--- Database Diagnosis ---\n";
    
    // List tables
    $stmt = $pdo->query("SHOW TABLES");
    $tables = $stmt->fetchAll(PDO::FETCH_COLUMN);
    echo "Tables in database:\n";
    foreach ($tables as $t) {
        $countStmt = $pdo->query("SELECT COUNT(*) FROM `$t`");
        $count = $countStmt->fetchColumn();
        echo " - $t ($count rows)\n";
    }
    
    // Sample articulos
    if (in_array('articulos', $tables)) {
        echo "\nSample records from 'articulos':\n";
        $stmt = $pdo->query("SELECT uuid, nombre, precio, imagen, last_modified, deleted FROM articulos LIMIT 5");
        $rows = $stmt->fetchAll();
        if (empty($rows)) {
            echo " (Table is empty)\n";
        } else {
            foreach ($rows as $r) {
                echo " - UUID: " . ($r['uuid'] ?? 'NULL') . " | Nombre: " . $r['nombre'] . " | Precio: " . $r['precio'] . " | Imagen: " . ($r['imagen'] ?? 'NULL') . " | Last Modified: " . $r['last_modified'] . " | Deleted: " . $r['deleted'] . "\n";
            }
        }
    }
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
?>
