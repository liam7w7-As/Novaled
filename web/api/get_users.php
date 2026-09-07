<?php
require_once 'config.php';

// Requerir autenticación válida JWT
$session = requireAuth();

try {
    $stmt = $pdo->query("SELECT username, passwordHash, role, createdAt FROM usuarios WHERE deleted = 0");
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
    echo json_encode($users);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(["error" => "Error al obtener usuarios: " . $e->getMessage()]);
}
?>
