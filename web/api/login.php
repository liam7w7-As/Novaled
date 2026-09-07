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
    // 1. Buscar usuario en base de datos MySQL (incluyendo verificación de estado)
    $stmt = $pdo->prepare("SELECT username, passwordHash, role, deleted FROM usuarios WHERE LOWER(username) = ? LIMIT 1");
    $stmt->execute([$username_input]);
    $user = $stmt->fetch();

    if (!$user) {
        http_response_code(401);
        echo json_encode(["error" => "Usuario no encontrado."]);
        exit();
    }

    // 2. Verificar si está dado de baja / eliminado
    if ((int)$user['deleted'] === 1 || (int)$user['deleted'] === 2 || $user['role'] === 'blocked') {
        http_response_code(403);
        echo json_encode(["error" => "Esta cuenta o empresa ha sido dada de baja. El acceso al sistema está bloqueado."]);
        exit();
    }

    // 3. Verificar si está suspendido
    if ($user['role'] === 'suspended') {
        http_response_code(403);
        echo json_encode(["error" => "Esta empresa ha sido suspendida por el administrador. El acceso está deshabilitado."]);
        exit();
    }

    // 4. Validar contraseña exacta (RECHAZAR SI ES INCORRECTA)
    if ($user['passwordHash'] !== $password_hash_input) {
        http_response_code(401);
        echo json_encode(["error" => "Contraseña incorrecta."]);
        exit();
    }

    // 5. Generar Token JWT firmado
    $token = generateToken($user['username'], $user['role']);

    // 6. Obtener lista de todos los usuarios activos para la caché offline
    $stmtAll = $pdo->query("SELECT username, passwordHash, role, createdAt FROM usuarios WHERE deleted = 0 AND role != 'suspended'");
    $allUsers = $stmtAll->fetchAll(PDO::FETCH_ASSOC);

    // 7. Devolver respuesta
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
