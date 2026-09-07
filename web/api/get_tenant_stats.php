<?php
require_once 'config.php';

// Requerir autenticación válida JWT
$session = requireAuth();

try {
    // 1. Obtener lista de usuarios registrados
    $stmtUsers = $pdo->query("SELECT username, role, createdAt, deleted FROM usuarios");
    $users = $stmtUsers->fetchAll(PDO::FETCH_ASSOC);

    // 2. Extraer todos los tenant_key únicos presentes
    $tenants = ['novaled', 'tenant_ultrashop', 'tenant_unithor'];
    
    try {
        $stmtTenants = $pdo->query("
            SELECT DISTINCT tenant_key FROM (
                SELECT tenant_key FROM cotizaciones WHERE tenant_key IS NOT NULL AND tenant_key != ''
                UNION
                SELECT tenant_key FROM notas_entrega WHERE tenant_key IS NOT NULL AND tenant_key != ''
                UNION
                SELECT tenant_key FROM proformas WHERE tenant_key IS NOT NULL AND tenant_key != ''
                UNION
                SELECT tenant_key FROM articulos WHERE tenant_key IS NOT NULL AND tenant_key != ''
            ) AS t
        ");
        $foundTenants = $stmtTenants->fetchAll(PDO::FETCH_COLUMN);
        foreach ($foundTenants as $ft) {
            if (!in_array($ft, $tenants)) {
                $tenants[] = $ft;
            }
        }
    } catch (Exception $e) {}

    $stats = [];

    foreach ($tenants as $tk) {
        // Recopilar todos los documentos de las 3 tablas de forma única por UUID
        $docsByUuid = [];

        // A. Cotizaciones
        $stmtCot = $pdo->prepare("
            SELECT id, uuid, tipo_venta, tipo_documento, total, fecha, last_modified, deleted 
            FROM cotizaciones 
            WHERE tenant_key = ?
        ");
        $stmtCot->execute([$tk]);
        $cots = $stmtCot->fetchAll(PDO::FETCH_ASSOC);
        foreach ($cots as $c) {
            $uId = !empty($c['uuid']) ? $c['uuid'] : ('cot_' . $c['id']);
            $docsByUuid[$uId] = $c;
        }

        // B. Notas de Entrega
        $stmtNotas = $pdo->prepare("
            SELECT id, uuid, tipo_venta, tipo_documento, total, fecha, last_modified, deleted 
            FROM notas_entrega 
            WHERE tenant_key = ?
        ");
        $stmtNotas->execute([$tk]);
        $notas = $stmtNotas->fetchAll(PDO::FETCH_ASSOC);
        foreach ($notas as $n) {
            $uId = !empty($n['uuid']) ? $n['uuid'] : ('nota_' . $n['id']);
            $docsByUuid[$uId] = $n;
        }

        // C. Proformas
        $stmtProf = $pdo->prepare("
            SELECT id, uuid, tipo_venta, tipo_documento, total, fecha, last_modified, deleted 
            FROM proformas 
            WHERE tenant_key = ?
        ");
        $stmtProf->execute([$tk]);
        $profs = $stmtProf->fetchAll(PDO::FETCH_ASSOC);
        foreach ($profs as $p) {
            $uId = !empty($p['uuid']) ? $p['uuid'] : ('prof_' . $p['id']);
            if (!isset($docsByUuid[$uId])) {
                $docsByUuid[$uId] = $p;
            }
        }

        // Clasificación exacta sin duplicados
        $countCotizaciones = 0;
        $countNotasVenta = 0;
        $countNotasEntrega = 0;
        $mesActual = 0;
        $fechas = [];

        $currentMonth = date('m');
        $currentYear = date('Y');

        foreach ($docsByUuid as $d) {
            $tv = strtolower(trim($d['tipo_venta'] ?? ''));
            $td = strtolower(trim($d['tipo_documento'] ?? ''));

            if ($td === 'nota_entrega' || $tv === 'nota_entrega') {
                $countNotasEntrega++;
            } else if ($tv === 'punto_venta' || $td === 'nota_venta' || $td === 'proforma') {
                $countNotasVenta++;
            } else {
                $countCotizaciones++;
            }

            $docDate = !empty($d['fecha']) ? $d['fecha'] : ($d['last_modified'] ?? null);
            if ($docDate) {
                $fechas[] = $docDate;
                $t = strtotime($docDate);
                if ($t !== false && date('m', $t) === $currentMonth && date('Y', $t) === $currentYear) {
                    $mesActual++;
                }
            }
        }

        // Artículos
        $stmtArt = $pdo->prepare("SELECT COUNT(*) FROM articulos WHERE deleted = 0 AND tenant_key = ?");
        $stmtArt->execute([$tk]);
        $totalArt = (int)$stmtArt->fetchColumn();

        // Clientes
        $stmtCli = $pdo->prepare("SELECT COUNT(*) FROM clientes WHERE deleted = 0 AND tenant_key = ?");
        $stmtCli->execute([$tk]);
        $totalCli = (int)$stmtCli->fetchColumn();

        // Contar usuarios activos de este tenant
        $tenantUsers = 0;
        foreach ($users as $u) {
            if ((int)($u['deleted'] ?? 0) === 1) continue;
            $un = strtolower($u['username'] ?? '');
            if ($tk === 'novaled') {
                if ($un === 'novaled.elektroshop@gmail.com' || in_array($un, ['joel', 'almir', 'victor', 'gustavo', 'alvaro', 'kimen', 'dani'])) {
                    $tenantUsers++;
                }
            } else {
                $cleanTk = str_replace('tenant_', '', $tk);
                if (strpos($un, $cleanTk) !== false) {
                    $tenantUsers++;
                }
            }
        }
        $ultimaActividad = !empty($fechas) ? max($fechas) : null;
        $totalPuntoVenta = $countNotasVenta + $countNotasEntrega;
        $totalDocs = $countCotizaciones + $totalPuntoVenta;

        // Escaneos mágicos desde tenant_settings
        $totalEscaneos = 0;
        try {
            $stmtSettings = $pdo->prepare("SELECT `settings` FROM `tenant_settings` WHERE `tenant_key` = ? LIMIT 1");
            $stmtSettings->execute([$tk]);
            $setRow = $stmtSettings->fetch(PDO::FETCH_ASSOC);
            if ($setRow && !empty($setRow['settings'])) {
                $dec = json_decode($setRow['settings'], true);
                if (isset($dec['total_escaneos'])) {
                    $totalEscaneos = (int)$dec['total_escaneos'];
                } elseif (isset($dec['scans_count'])) {
                    $totalEscaneos = (int)$dec['scans_count'];
                }
            }
        } catch (Exception $e) {}

        $stats[$tk] = [
            'tenant_key' => $tk,
            'total_cotizaciones' => $countCotizaciones,
            'total_notas_venta' => $countNotasVenta,
            'total_notas_entrega' => $countNotasEntrega,
            'total_punto_venta' => $totalPuntoVenta,
            'total_escaneos' => $totalEscaneos,
            'total_usuarios' => $tenantUsers,
            'total_documentos' => $totalDocs,
            'documentos_mes_actual' => $mesActual,
            'total_articulos' => $totalArt,
            'total_clientes' => $totalCli,
            'ultima_actividad' => $ultimaActividad,
        ];
    }

    echo json_encode([
        'success' => true,
        'users' => $users,
        'stats' => $stats,
        'timestamp' => date('Y-m-d H:i:s')
    ]);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(["error" => "Error al obtener estadísticas de empresas: " . $e->getMessage()]);
}
?>
