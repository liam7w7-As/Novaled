<?php
require_once 'config.php';
header('Content-Type: application/json');

try {
    $stmt = $pdo->query("SELECT `id`, `uuid`, `nombre`, `tenant_key`, `deleted` FROM `unidades_medida` WHERE `tenant_key` LIKE '%ultrashop%' OR `tenant_key` = 'novaled' ORDER BY `id` DESC");
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    echo json_encode($rows, JSON_PRETTY_PRINT);
} catch (Exception $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
?>
