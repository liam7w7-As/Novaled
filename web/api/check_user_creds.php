<?php
require_once 'config.php';
header('Content-Type: application/json');

try {
    $stmt = $pdo->query("SELECT `id`, `username`, `tenant_key`, `role` FROM `users` WHERE `username` LIKE '%ultrashop%' OR `username` LIKE '%joel%'");
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    echo json_encode($rows, JSON_PRETTY_PRINT);
} catch (Exception $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
?>
