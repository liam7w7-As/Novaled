<?php
require_once 'config.php';

// LOGGING DE DEBUG PARA SINCRONIZACIÓN
$raw_body = file_get_contents('php://input');
$auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['Authorization'] ?? '';
$log_entry = date('[Y-m-d H:i:s]') . " IP: " . $_SERVER['REMOTE_ADDR'] . 
             " UA: " . ($_SERVER['HTTP_USER_AGENT'] ?? 'N/A') . 
             " Auth: " . substr($auth_header, 0, 30) . "..." .
             " BodyLength: " . strlen($raw_body) . " Body: " . substr($raw_body, 0, 200) . "\n";
file_put_contents(__DIR__ . '/sync_debug.log', $log_entry, FILE_APPEND);

// Requerir autenticación válida JWT para sincronizar
$session = requireAuth();

function getTenantKeyFromUser($u) {
    $u = strtolower(trim($u));
    $novaled = ['novaled', 'novaled.elektroshop@gmail.com', 'novaled@gmail.com', 'joel', 'almir', 'victor', 'gustavo', 'alvaro', 'kimen', 'dani', 'celia', 'novaled.db'];
    if (in_array($u, $novaled) || strpos($u, 'novaled') !== false) {
        return 'novaled';
    }
    $safe = preg_replace('/[^a-z0-9_]/', '_', $u);
    return 'tenant_' . $safe;
}

$current_tenant_key = getTenantKeyFromUser($session['username'] ?? '');

// Obtener el payload JSON
$raw_input = file_get_contents('php://input');
$input = json_decode($raw_input, true);

if (!$input) {
    $decoded = base64_decode($raw_input);
    if ($decoded !== false) {
        $input = json_decode($decoded, true);
    }
}

if (!$input) {
    http_response_code(400);
    echo json_encode(["error" => "Payload JSON inválido."]);
    exit();
}

$table = $input['table'] ?? '';
$last_sync = $input['last_sync'] ?? '1970-01-01 00:00:00';
$records = $input['records'] ?? [];
$deleted_uuids = $input['deleted_uuids'] ?? [];

$allowed_tables = ['articulos', 'clientes', 'cotizaciones', 'notas_entrega', 'proformas', 'tiendas', 'unidades_medida', 'proveedores', 'sub_ubicaciones'];

if (empty($table) || !in_array($table, $allowed_tables)) {
    http_response_code(400);
    echo json_encode(["error" => "Tabla no válida o no permitida: " . htmlspecialchars($table)]);
    exit();
}

try {
    $pdo->beginTransaction();
    $pdo->exec("SET UNIQUE_CHECKS=0");
    $pdo->exec("SET FOREIGN_KEY_CHECKS=0");

    // 1. Obtener las columnas reales de la tabla en MySQL para mapear correctamente
    $stmt = $pdo->prepare("DESCRIBE `$table`");
    $stmt->execute();
    $columns = $stmt->fetchAll(PDO::FETCH_COLUMN);

    // 2. Procesar subidas locales a la nube
    foreach ($records as &$record) {
        $normalized = [];
        foreach ($record as $key => $val) {
            foreach ($columns as $col) {
                if (strtolower($key) === strtolower($col)) {
                    $normalized[$col] = $val;
                    break;
                }
            }
        }
        if (in_array('tenant_key', $columns)) {
            if (empty($normalized['tenant_key'])) {
                $normalized['tenant_key'] = $current_tenant_key;
            }
        }
        $record = $normalized;
    }
    unset($record);
    foreach ($records as $record) {
        if (empty($record['uuid'])) continue;

        $exists = false;
        
        // Especial para unidades_medida: Si ya existe el nombre en MySQL, unificar el UUID y reactivar solo si es una nueva creación
        if ($table === 'unidades_medida' && !empty($record['nombre'])) {
            if (in_array('tenant_key', $columns)) {
                $checkName = $pdo->prepare("SELECT `uuid`, `deleted` FROM `unidades_medida` WHERE `nombre` = ? AND `tenant_key` = ? LIMIT 1");
                $checkName->execute([$record['nombre'], $record['tenant_key'] ?? $current_tenant_key]);
            } else {
                $checkName = $pdo->prepare("SELECT `uuid`, `deleted` FROM `unidades_medida` WHERE `nombre` = ? LIMIT 1");
                $checkName->execute([$record['nombre']]);
            }
            $existingRow = $checkName->fetch();
            if ($existingRow) {
                $existingUuid = $existingRow['uuid'];
                $existingDeleted = (int)$existingRow['deleted'];

                // Si ya estaba marcado como eliminado en MySQL y el cliente envía el MISMO uuid viejo, no revivirlo (es un registro obsoleto)
                if ($existingDeleted === 1 && $existingUuid === $record['uuid']) {
                    continue;
                }

                if (in_array('tenant_key', $columns)) {
                    $updUuid = $pdo->prepare("UPDATE `unidades_medida` SET `uuid` = ?, `deleted` = 0, `last_modified` = NOW() WHERE `nombre` = ? AND `tenant_key` = ?");
                    $updUuid->execute([$record['uuid'], $record['nombre'], $record['tenant_key'] ?? $current_tenant_key]);
                } else {
                    $updUuid = $pdo->prepare("UPDATE `unidades_medida` SET `uuid` = ?, `deleted` = 0, `last_modified` = NOW() WHERE `nombre` = ?");
                    $updUuid->execute([$record['uuid'], $record['nombre']]);
                }
                $exists = true;
            }
        }

        if (!$exists) {
            // Verificar si el registro ya existe en el servidor por su UUID único
            $checkStmt = $pdo->prepare("SELECT `deleted` FROM `$table` WHERE `uuid` = ? LIMIT 1");
            $checkStmt->execute([$record['uuid']]);
            $existingDeletedCol = $checkStmt->fetchColumn();
            if ($existingDeletedCol !== false) {
                $exists = true;
                // Si ya estaba eliminado en el servidor y la subida no especifica recreación, no resucitarlo
                if ((int)$existingDeletedCol === 1 && !isset($record['deleted'])) {
                    continue;
                }
            }
        }

        if ($exists !== false) {
            // Existe: Hacer UPDATE.
            $update_parts = [];
            $bind_values = [];
            foreach ($columns as $col) {
                if ($col === 'last_modified' || $col === 'id') continue;
                if (array_key_exists($col, $record)) {
                    $update_parts[] = "`$col` = :$col";
                    $bind_values[":$col"] = $record[$col];
                }
            }
            if (in_array('deleted', $columns)) {
                $update_parts[] = "`deleted` = 0";
            }
            if (in_array('last_modified', $columns)) {
                $update_parts[] = "`last_modified` = NOW()";
            }
            if (!empty($update_parts)) {
                $query = "UPDATE `$table` SET " . implode(', ', $update_parts) . " WHERE `uuid` = :uuid_match";
                $bind_values[":uuid_match"] = $record['uuid'];
                $stmt = $pdo->prepare($query);
                $stmt->execute($bind_values);
            }
        } else {
            // No existe: Hacer INSERT. Ignoramos el ID del cliente y dejamos que MySQL lo autoincremente
            $insert_cols = [];
            $placeholders = [];
            $bind_values = [];
            foreach ($columns as $col) {
                if ($col === 'last_modified' || $col === 'id') continue;
                if (array_key_exists($col, $record)) {
                    $insert_cols[] = "`$col`";
                    $placeholders[] = ":$col";
                    $bind_values[":$col"] = $record[$col];
                }
            }
            // Asegurar el estado deleted
            if (!in_array('`deleted`', $insert_cols) && in_array('deleted', $columns)) {
                $insert_cols[] = "`deleted`";
                $placeholders[] = ":deleted";
                $bind_values[":deleted"] = 0;
            }
            if (!in_array('`last_modified`', $insert_cols) && in_array('last_modified', $columns)) {
                $insert_cols[] = "`last_modified`";
                $placeholders[] = "NOW()";
            }
            if (!empty($insert_cols)) {
                $query = "INSERT INTO `$table` (" . implode(', ', $insert_cols) . ") VALUES (" . implode(', ', $placeholders) . ")";
                $stmt = $pdo->prepare($query);
                $stmt->execute($bind_values);
            }
        }
    }

    $deleted_names = $input['deleted_names'] ?? [];

    // 3. Procesar eliminaciones locales a la nube
    if (!empty($deleted_uuids) && in_array('deleted', $columns)) {
        $placeholders = implode(', ', array_fill(0, count($deleted_uuids), '?'));
        $query = "UPDATE `$table` SET `deleted` = 1, `last_modified` = NOW() WHERE `uuid` IN ($placeholders)";
        $stmt = $pdo->prepare($query);
        $stmt->execute($deleted_uuids);
    }

    // También procesar eliminaciones por nombre para tablas como unidades_medida, articulos, tiendas
    if (!empty($deleted_names) && in_array('deleted', $columns) && in_array('nombre', $columns)) {
        $namePlaceholders = implode(', ', array_fill(0, count($deleted_names), '?'));
        if (in_array('tenant_key', $columns)) {
            $params = array_merge($deleted_names, [$current_tenant_key]);
            $query = "UPDATE `$table` SET `deleted` = 1, `last_modified` = NOW() WHERE `nombre` IN ($namePlaceholders) AND `tenant_key` = ?";
        } else {
            $params = $deleted_names;
            $query = "UPDATE `$table` SET `deleted` = 1, `last_modified` = NOW() WHERE `nombre` IN ($namePlaceholders)";
        }
        $stmt = $pdo->prepare($query);
        $stmt->execute($params);
    }

    $pdo->commit();
    $pdo->exec("SET UNIQUE_CHECKS=1");
    $pdo->exec("SET FOREIGN_KEY_CHECKS=1");

    // 4. Obtener hora actual del servidor MySQL
    $stmtTime = $pdo->query("SELECT NOW() as server_time");
    $server_time = $stmtTime->fetchColumn();

    // 5. Descargar cambios remotos (records creados o modificados después del último sync filtrados por tenant)
    if (in_array('tenant_key', $columns)) {
        if ($current_tenant_key === 'novaled') {
            $stmtQuery = $pdo->prepare("SELECT * FROM `$table` WHERE `last_modified` > ? AND (`tenant_key` = 'novaled' OR `tenant_key` IS NULL OR `tenant_key` = '')");
            $stmtQuery->execute([$last_sync]);
        } else {
            $stmtQuery = $pdo->prepare("SELECT * FROM `$table` WHERE `last_modified` > ? AND `tenant_key` = ?");
            $stmtQuery->execute([$last_sync, $current_tenant_key]);
        }
    } else {
        $stmtQuery = $pdo->prepare("SELECT * FROM `$table` WHERE `last_modified` > ?");
        $stmtQuery->execute([$last_sync]);
    }
    $remote_records = $stmtQuery->fetchAll();

    echo json_encode([
        "success" => true,
        "server_time" => $server_time,
        "records" => $remote_records
    ]);

} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    $pdo->exec("SET UNIQUE_CHECKS=1");
    $pdo->exec("SET FOREIGN_KEY_CHECKS=1");
    http_response_code(500);
    echo json_encode(["error" => "Error de sincronización en servidor: " . $e->getMessage()]);
}
?>
