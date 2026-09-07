<?php
require_once 'config.php';
$stmt = $pdo->query("SELECT id, uuid, clienteNombre, vendedor, tenant_key, last_modified FROM cotizaciones ORDER BY id DESC LIMIT 10");
echo json_encode($stmt->fetchAll(PDO::FETCH_ASSOC), JSON_PRETTY_PRINT);
?>
