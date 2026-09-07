<?php
require_once 'config.php';

// Requerir autenticación válida JWT
$session = requireAuth();

// Solo los administradores y desarrolladores pueden guardar o editar usuarios
if ($session['role'] !== 'admin' && $session['role'] !== 'developer') {
    http_response_code(403);
    echo json_encode(["error" => "Prohibido. Se requieren permisos de administrador o desarrollador."]);
    exit();
}

$raw_input = file_get_contents('php://input');
$users = json_decode($raw_input, true);

if (!is_array($users)) {
    http_response_code(400);
    echo json_encode(["error" => "Payload de usuarios inválido."]);
    exit();
}

try {
    $pdo->beginTransaction();
    
    // Eliminar todos los usuarios actuales de la tabla usuarios para reemplazarlos con la nueva lista
    $pdo->exec("DELETE FROM usuarios");
    
    $stmt = $pdo->prepare("INSERT INTO usuarios (username, passwordHash, role, createdAt, deleted) VALUES (:username, :passwordHash, :role, :createdAt, 0)");
    
    foreach ($users as $user) {
        $username = trim($user['username']);
        if (empty($username)) continue;
        
        $stmt->execute([
            ':username' => $username,
            ':passwordHash' => $user['passwordHash'] ?? '',
            ':role' => $user['role'] ?? 'seller',
            ':createdAt' => $user['createdAt'] ?? date('c')
        ]);
    }
    
    $pdo->commit();
    echo json_encode(["success" => true]);
} catch (Exception $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    http_response_code(500);
    echo json_encode(["error" => "Error al guardar usuarios: " . $e->getMessage()]);
}
?>
