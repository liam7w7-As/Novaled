<?php
require_once 'config.php';
header('Content-Type: application/json');

$stmt = $pdo->query("SELECT id, uuid, clienteNombre, total, tenant_key, last_modified FROM cotizaciones ORDER BY id DESC LIMIT 10");
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode($rows, JSON_PRETTY_PRINT);
?>
