<?php
require_once 'config.php';
header('Content-Type: application/json');

$tables = ['proformas', 'notas_entrega', 'cotizaciones'];
$res = [];

foreach ($tables as $t) {
    try {
        $stmt = $pdo->query("SELECT `id`, `uuid`, `clienteNombre`, `vendedor`, `estado_pago`, `saldo_cancelado`, `total`, `tipo_venta`, `last_modified` FROM `$t` ORDER BY `id` DESC LIMIT 6");
        $res[$t] = $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (Exception $e) {
        $res[$t] = ['error' => $e->getMessage()];
    }
}

echo json_encode($res, JSON_PRETTY_PRINT);
?>
