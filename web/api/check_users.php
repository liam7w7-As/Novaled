<?php
require_once 'config.php';
$stmt = $pdo->query("SELECT username, role, createdAt FROM usuarios");
echo json_encode($stmt->fetchAll(PDO::FETCH_ASSOC));
?>
