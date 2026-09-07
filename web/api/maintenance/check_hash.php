<?php
require_once 'config.php';
header('Content-Type: application/json');

$stmt = $pdo->prepare("SELECT `username`, `passwordHash` FROM `usuarios` WHERE `username` = 'ultrashop'");
$stmt->execute();
$row = $stmt->fetch(PDO::FETCH_ASSOC);

$candidates = ['123456', 'ultrashop', 'admin', 'admin123', 'novaled', '1234', 'password', 'Patasca2029@', '67502547', 'novaled2026'];
$found = 'unknown';
foreach ($candidates as $c) {
    if (hash('sha256', $c) === $row['passwordHash']) {
        $found = $c;
        break;
    }
}

echo json_encode(['username' => $row['username'], 'plain' => $found, 'hash' => $row['passwordHash']]);
?>
