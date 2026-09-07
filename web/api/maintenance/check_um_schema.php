<?php
require_once 'config.php';
header('Content-Type: application/json');

try {
    $stmt = $pdo->query("SHOW CREATE TABLE `unidades_medida`");
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    echo json_encode($row, JSON_PRETTY_PRINT);
} catch (Exception $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
?>
