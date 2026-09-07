<?php
require_once 'config.php';
header('Content-Type: application/json');

$tables = ['cotizaciones', 'proformas', 'notas_entrega', 'articulos', 'clientes', 'tiendas', 'unidades_medida', 'usuarios'];
$schema = [];

foreach ($tables as $t) {
    try {
        $stmt = $pdo->prepare("DESCRIBE `$t`");
        $stmt->execute();
        $schema[$t] = $stmt->fetchAll(PDO::FETCH_COLUMN);
    } catch (Exception $e) {
        $schema[$t] = ['error' => $e->getMessage()];
    }
}

echo json_encode($schema, JSON_PRETTY_PRINT);
?>
