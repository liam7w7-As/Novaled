<?php
require_once 'config.php';
header('Content-Type: application/json');

$last_sync = '1970-01-01 00:00:00';
$current_tenant_key = 'tenant_ultrashop';

$stmtQuery = $pdo->prepare("SELECT * FROM `cotizaciones` WHERE `last_modified` > ? AND `tenant_key` = ?");
$stmtQuery->execute([$last_sync, $current_tenant_key]);
$rows = $stmtQuery->fetchAll(PDO::FETCH_ASSOC);

echo json_encode([
    'count' => count($rows),
    'rows' => $rows
], JSON_PRETTY_PRINT);
?>
