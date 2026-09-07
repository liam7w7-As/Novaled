<?php
require_once 'config.php';
header('Content-Type: application/json');

try {
    $stmt = $pdo->query("SELECT `id`, `uuid`, `nombre`, `precio`, `tenant_key`, `last_modified`, `deleted` FROM `articulos` WHERE `tenant_key` LIKE '%ultrashop%' OR `id` > 1 ORDER BY `id` DESC LIMIT 15");
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    echo json_encode($rows, JSON_PRETTY_PRINT);
} catch (Exception $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
?>
