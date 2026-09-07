<?php
require_once 'config.php';
header('Content-Type: application/json');

$tables = ['cotizaciones', 'notas_entrega', 'proformas'];
$res = [];

$colsToAdd = [
    'metodo_pago' => 'VARCHAR(100) DEFAULT "Transferencia Bancaria"',
    'estado_pago' => 'VARCHAR(50) DEFAULT "por_cobrar"',
    'comprobante_img' => 'TEXT DEFAULT NULL',
    'comprobado' => 'INT DEFAULT 0',
    'saldo_cancelado' => 'DECIMAL(12,2) DEFAULT 0.00',
    'tipo_venta' => 'VARCHAR(50) DEFAULT "punto_venta"',
    'tipo_documento' => 'VARCHAR(50) DEFAULT "cotizacion"'
];

foreach ($tables as $t) {
    try {
        $stmt = $pdo->query("DESCRIBE `$t`");
        $cols = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $colNames = array_column($cols, 'Field');
        
        $added = [];
        foreach ($colsToAdd as $col => $def) {
            if (!in_array($col, $colNames)) {
                $pdo->exec("ALTER TABLE `$t` ADD COLUMN `$col` $def");
                $added[] = $col;
            }
        }
        
        $res[$t] = [
            'added' => $added,
            'all_columns' => array_column($pdo->query("DESCRIBE `$t`")->fetchAll(PDO::FETCH_ASSOC), 'Field')
        ];
    } catch (Exception $e) {
        $res[$t] = ['error' => $e->getMessage()];
    }
}

echo json_encode($res, JSON_PRETTY_PRINT);
?>
