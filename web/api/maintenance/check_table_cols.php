<?php
require_once 'config.php';
header('Content-Type: application/json');

$tables = ['cotizaciones', 'proformas', 'articulos', 'clientes', 'usuarios'];
$res = [];
foreach ($tables as $t) {
    try {
        $stmt = $pdo->query("DESCRIBE `$t`");
        $res[$t] = $stmt->fetchAll(PDO::FETCH_COLUMN);
    } catch (Exception $e) {
        $res[$t] = $e->getMessage();
    }
}
echo json_encode($res, JSON_PRETTY_PRINT);
?>
