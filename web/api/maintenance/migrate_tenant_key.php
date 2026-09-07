<?php
require_once 'config.php';
header('Content-Type: application/json');

$tables = ['articulos', 'clientes', 'cotizaciones', 'notas_entrega', 'proformas', 'tiendas', 'unidades_medida', 'proveedores', 'sub_ubicaciones'];
$results = [];

foreach ($tables as $t) {
    try {
        // 1. Verificar si existe la columna tenant_key
        $stmt = $pdo->query("SHOW COLUMNS FROM `$t` LIKE 'tenant_key'");
        $exists = $stmt->fetch();
        if (!$exists) {
            $pdo->exec("ALTER TABLE `$t` ADD COLUMN `tenant_key` VARCHAR(100) NOT NULL DEFAULT 'novaled'");
            $results[$t] = "Columna tenant_key agregada";
        } else {
            $results[$t] = "Columna tenant_key ya existe";
        }
        
        // Asignar novaled por defecto a registros existentes sin tenant
        $pdo->exec("UPDATE `$t` SET `tenant_key` = 'novaled' WHERE `tenant_key` IS NULL OR `tenant_key` = ''");
        
        // Si hay cotizaciones de ULTRASHOP, marcar su tenant_key
        if ($t === 'cotizaciones' || $t === 'proformas' || $t === 'notas_entrega') {
            $pdo->exec("UPDATE `$t` SET `tenant_key` = 'tenant_ultrashop' WHERE LOWER(vendedor) LIKE '%ultrashop%' OR LOWER(clienteNombre) LIKE '%ultrashop%'");
        }
    } catch (Exception $e) {
        $results[$t] = "Error: " . $e->getMessage();
    }
}

echo json_encode($results, JSON_PRETTY_PRINT);
?>
