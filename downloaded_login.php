<?php
require_once 'config.php';

// Obtener payload JSON
$raw_input = file_get_contents('php://input');
$input = json_decode($raw_input, true);

if (!$input || empty($input['username']) || empty($input['passwordHash'])) {
    http_response_code(400);
    echo json_encode(["error" => "Parámetros username y passwordHash requeridos."]);
    exit();
}

$username_input = trim(strtolower($input['username']));
$password_hash_input = trim($input['passwordHash']);

try {
    // 1. Buscar usuario en base de datos MySQL
    $stmt = $pdo->prepare("SELECT username, passwordHash, role FROM usuarios WHERE LOWER(username) = ? AND deleted = 0 LIMIT 1");
    $stmt->execute([$username_input]);
    $user = $stmt->fetch();

    if (!$user || $user['passwordHash'] !== $password_hash_input) {
        http_response_code(401);
        echo json_encode(["error" => "Usuario o contraseña incorrectos."]);
        exit();
    }

    // 2. Generar Token JWT firmado
    $token = generateToken($user['username'], $user['role']);

    // 3. Obtener lista de todos los usuarios para la caché offline de la aplicación móvil/web
    $stmtAll = $pdo->query("SELECT username, passwordHash, role, createdAt FROM usuarios WHERE deleted = 0");
    $allUsers = $stmtAll->fetchAll(PDO::FETCH_ASSOC);

    // 4. Devolver respuesta
    echo json_encode([
        "success" => true,
        "token" => $token,
        "username" => $user['username'],
        "role" => $user['role'],
        "users" => $allUsers
    ]);

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(["error" => "Error interno de base de datos durante el inicio de sesión: " . $e->getMessage()]);
}
?>
