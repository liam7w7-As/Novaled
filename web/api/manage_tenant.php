<?php
require_once 'config.php';

// Requerir autenticación válida JWT de SuperAdmin
$session = requireAuth();

$raw_input = file_get_contents('php://input');
$input = json_decode($raw_input, true);

if (!$input || empty($input['tenant_key']) || empty($input['action'])) {
    http_response_code(400);
    echo json_encode(["error" => "Parámetros tenant_key y action requeridos."]);
    exit();
}

$tenant_key = trim($input['tenant_key']);
$action = trim($input['action']);
$email = trim(strtolower($input['email'] ?? ''));

try {
    $cleanTk = str_replace('tenant_', '', $tenant_key);

    if ($action === 'suspend') {
        // Suspender inmediatamente todas las cuentas y cerrar sesiones activas
        $stmtUsers = $pdo->prepare("
            UPDATE usuarios 
            SET role = 'suspended' 
            WHERE LOWER(username) = ? 
               OR LOWER(username) LIKE ? 
               OR LOWER(username) LIKE ?
        ");
        $stmtUsers->execute([
            $email,
            '%' . $cleanTk . '%',
            $tenant_key . '%'
        ]);

        echo json_encode([
            "success" => true,
            "message" => "Empresa suspendida y sesiones cerradas inmediatamente en MySQL."
        ]);
    } else if ($action === 'unsuspend' || $action === 'reactivate') {
        // Reactivar cuentas suspendidas
        $stmtUsers = $pdo->prepare("
            UPDATE usuarios 
            SET role = 'admin' 
            WHERE (LOWER(username) = ? 
               OR LOWER(username) LIKE ? 
               OR LOWER(username) LIKE ?)
               AND role = 'suspended'
        ");
        $stmtUsers->execute([
            $email,
            '%' . $cleanTk . '%',
            $tenant_key . '%'
        ]);

        echo json_encode([
            "success" => true,
            "message" => "Empresa reactivada y acceso habilitado en MySQL."
        ]);
    } else if ($action === 'soft_delete') {
        // Bloquear y dar de baja a todos los usuarios de esta empresa (30 días de papelera)
        $stmtUsers = $pdo->prepare("
            UPDATE usuarios 
            SET deleted = 1 
            WHERE LOWER(username) = ? 
               OR LOWER(username) LIKE ? 
               OR LOWER(username) LIKE ?
        ");
        $stmtUsers->execute([
            $email,
            '%' . $cleanTk . '%',
            $tenant_key . '%'
        ]);

        echo json_encode([
            "success" => true,
            "message" => "Empresa enviada a papelera (30 días) y acceso bloqueado en MySQL."
        ]);
    } else if ($action === 'restore') {
        // Restaurar acceso a los usuarios
        $stmtUsers = $pdo->prepare("
            UPDATE usuarios 
            SET deleted = 0, role = 'admin' 
            WHERE LOWER(username) = ? 
               OR LOWER(username) LIKE ? 
               OR LOWER(username) LIKE ?
        ");
        $stmtUsers->execute([
            $email,
            '%' . $cleanTk . '%',
            $tenant_key . '%'
        ]);

        echo json_encode([
            "success" => true,
            "message" => "Empresa restaurada y acceso reactivado en MySQL."
        ]);
    } else if ($action === 'hard_delete') {
        // Purgar definitivamente todos los datos de la empresa
        $pdo->beginTransaction();

        $stmt = $pdo->prepare("DELETE FROM cotizaciones WHERE tenant_key = ?");
        $stmt->execute([$tenant_key]);

        $stmt = $pdo->prepare("DELETE FROM notas_entrega WHERE tenant_key = ?");
        $stmt->execute([$tenant_key]);

        $stmt = $pdo->prepare("DELETE FROM proformas WHERE tenant_key = ?");
        $stmt->execute([$tenant_key]);

        $stmt = $pdo->prepare("DELETE FROM articulos WHERE tenant_key = ?");
        $stmt->execute([$tenant_key]);

        $stmt = $pdo->prepare("DELETE FROM clientes WHERE tenant_key = ?");
        $stmt->execute([$tenant_key]);

        $stmt = $pdo->prepare("DELETE FROM tiendas WHERE tenant_key = ?");
        $stmt->execute([$tenant_key]);

        $stmt = $pdo->prepare("DELETE FROM usuarios WHERE LOWER(username) = ? OR LOWER(username) LIKE ?");
        $stmt->execute([$email, '%' . $cleanTk . '%']);

        $pdo->commit();

        echo json_encode([
            "success" => true,
            "message" => "Empresa purgada permanentemente de MySQL."
        ]);
    } else {
        http_response_code(400);
        echo json_encode(["error" => "Acción no válida."]);
    }
} catch (Exception $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    http_response_code(500);
    echo json_encode(["error" => "Error procesando acción: " . $e->getMessage()]);
}
?>
