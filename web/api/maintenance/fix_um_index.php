<?php
require_once 'config.php';
header('Content-Type: application/json');

try {
    // Drop existing unique key on nombre
    try {
        $pdo->exec("ALTER TABLE `unidades_medida` DROP INDEX `nombre`");
    } catch (Exception $e) {}

    // Add composite unique key on (nombre, tenant_key)
    try {
        $pdo->exec("ALTER TABLE `unidades_medida` ADD UNIQUE KEY `uniq_nombre_tenant` (`nombre`, `tenant_key`)");
    } catch (Exception $e) {}

    // Show updated schema
    $stmt = $pdo->query("SHOW CREATE TABLE `unidades_medida`");
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    echo json_encode($row, JSON_PRETTY_PRINT);
} catch (Exception $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
?>
