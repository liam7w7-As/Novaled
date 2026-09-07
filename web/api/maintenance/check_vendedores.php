<?php
require_once 'config.php';
header('Content-Type: application/json');

$tables = ['cotizaciones', 'notas_entrega', 'proformas'];
$res = [];

foreach ($tables as $t) {
    try {
        $stmt = $pdo->query("DESCRIBE `$t`");
        $cols = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $colNames = array_column($cols, 'Field');
        
        if (!in_array('vendedor', $colNames)) {
            $pdo->exec("ALTER TABLE `$t` ADD COLUMN `vendedor` VARCHAR(100) DEFAULT NULL");
            $colNames[] = 'vendedor (ADDED)';
        }
        if (!in_array('sucursal', $colNames)) {
            $pdo->exec("ALTER TABLE `$t` ADD COLUMN `sucursal` VARCHAR(255) DEFAULT NULL");
            $colNames[] = 'sucursal (ADDED)';
        }
        
        $stmt2 = $pdo->query("SELECT `id`, `uuid`, `clienteNombre`, `vendedor`, `sucursal`, `total` FROM `$t` ORDER BY `id` DESC LIMIT 5");
        $rows = $stmt2->fetchAll(PDO::FETCH_ASSOC);
        
        $res[$t] = [
            'columns' => $colNames,
            'recent_rows' => $rows
        ];
    } catch (Exception $e) {
        $res[$t] = ['error' => $e->getMessage()];
    }
}

echo json_encode($res, JSON_PRETTY_PRINT);
?>
