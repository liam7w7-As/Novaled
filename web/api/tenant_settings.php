<?php
require_once 'config.php';

// Permitir peticiones desde cualquier origen (CORS)
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Authorization");
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

try {
    // 1. Asegurar que la tabla tenant_settings existe
    $pdo->exec("CREATE TABLE IF NOT EXISTS `tenant_settings` (
        `tenant_key` VARCHAR(150) NOT NULL PRIMARY KEY,
        `settings` LONGTEXT NOT NULL,
        `updated_at` DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $method = $_SERVER['REQUEST_METHOD'];

    if ($method === 'GET') {
        $tenant_key = trim($_GET['tenant_key'] ?? '');
        if (empty($tenant_key)) {
            http_response_code(400);
            echo json_encode(["error" => "tenant_key es requerido"]);
            exit();
        }

        $defaultPlan = ($tenant_key === 'novaled') ? 'plus' : 'free';

        $stmt = $pdo->prepare("SELECT `settings`, `updated_at` FROM `tenant_settings` WHERE `tenant_key` = ? LIMIT 1");
        $stmt->execute([$tenant_key]);
        $row = $stmt->fetch();

        if ($row) {
            $decoded = json_decode($row['settings'], true) ?: [];
            if (!isset($decoded['plan_id'])) {
                $decoded['plan_id'] = $defaultPlan;
            }
            echo json_encode([
                "success" => true,
                "tenant_key" => $tenant_key,
                "settings" => $decoded,
                "updated_at" => $row['updated_at']
            ]);
        } else {
            echo json_encode([
                "success" => true,
                "tenant_key" => $tenant_key,
                "settings" => [
                    "plan_id" => $defaultPlan
                ],
                "updated_at" => null
            ]);
        }
        exit();
    } elseif ($method === 'POST') {
        $raw_input = file_get_contents('php://input');
        $input = json_decode($raw_input, true);

        if (!$input || empty($input['tenant_key']) || !isset($input['settings'])) {
            http_response_code(400);
            echo json_encode(["error" => "tenant_key y settings son requeridos"]);
            exit();
        }

        $tenant_key = trim($input['tenant_key']);
        $settings_data = is_string($input['settings']) ? json_decode($input['settings'], true) : $input['settings'];

        // Obtener configuración existente para fusionar
        $stmtOld = $pdo->prepare("SELECT `settings` FROM `tenant_settings` WHERE `tenant_key` = ? LIMIT 1");
        $stmtOld->execute([$tenant_key]);
        $oldRow = $stmtOld->fetch();
        $mergedSettings = $oldRow ? (json_decode($oldRow['settings'], true) ?: []) : [];

        if (is_array($settings_data)) {
            foreach ($settings_data as $k => $v) {
                $mergedSettings[$k] = $v;
            }
        }

        $settings_json = json_encode($mergedSettings);

        $stmt = $pdo->prepare("INSERT INTO `tenant_settings` (`tenant_key`, `settings`, `updated_at`) 
            VALUES (?, ?, NOW()) 
            ON DUPLICATE KEY UPDATE `settings` = VALUES(`settings`), `updated_at` = NOW()");
        $stmt->execute([$tenant_key, $settings_json]);

        echo json_encode([
            "success" => true,
            "message" => "Configuración del tenant guardada correctamente",
            "tenant_key" => $tenant_key,
            "settings" => $mergedSettings
        ]);
        exit();
    } else {
        http_response_code(405);
        echo json_encode(["error" => "Método no permitido"]);
        exit();
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(["error" => "Error interno en servidor: " . $e->getMessage()]);
    exit();
}
?>
