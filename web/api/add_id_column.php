<?php
require_once 'config.php';

$tables = ['articulos', 'clientes', 'cotizaciones', 'notas_entrega', 'proformas', 'tiendas', 'unidades_medida', 'proveedores'];
$results = [];

foreach ($tables as $table) {
    try {
        // Verificar si la columna 'id' ya existe
        $stmt = $pdo->prepare("DESCRIBE `$table`");
        $stmt->execute();
        $columns = $stmt->fetchAll(PDO::FETCH_COLUMN);
        
        if (!in_array('id', $columns)) {
            // No existe, la añadimos
            $pdo->exec("ALTER TABLE `$table` ADD COLUMN `id` INT AUTO_INCREMENT UNIQUE");
            $results[] = "$table: Columna 'id' agregada con éxito.";
        } else {
            $results[] = "$table: La columna 'id' ya existe.";
        }

        if ($table === 'articulos' && !in_array('fecha', $columns)) {
            $pdo->exec("ALTER TABLE `articulos` ADD COLUMN `fecha` VARCHAR(50) DEFAULT ''");
            $results[] = "articulos: Columna 'fecha' agregada con éxito.";
        }
    } catch (Exception $e) {
        $results[] = "$table: Error - " . $e->getMessage();
    }
}

echo json_encode([
    "success" => true,
    "results" => $results
]);
?>
