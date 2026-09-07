<?php
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('error_log', __DIR__ . '/php_error.log');

// Permitir peticiones desde cualquier origen (CORS)
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Authorization");
header("Content-Type: application/json; charset=UTF-8");

// Manejar preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

$host = 'localhost';
$db   = 'u321709103_novaled';
$pass = 'Lnovando2029@';

// En Hostinger el usuario suele llevar el prefijo de la cuenta. Intentamos con el prefijo, si falla con el original.
$users_to_try = ['u321709103_novaled', 'novaled'];
$pdo = null;
$error = null;

foreach ($users_to_try as $user) {
    try {
        $dsn = "mysql:host=$host;dbname=$db;charset=utf8mb4";
        $options = [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ];
        $pdo = new PDO($dsn, $user, $pass, $options);
        break; // Éxito
    } catch (PDOException $e) {
        $error = $e->getMessage();
    }
}

if (!$pdo) {
    http_response_code(500);
    echo json_encode(["error" => "No se pudo conectar a la base de datos: $error"]);
    exit();
}

// Configuración y funciones helper de seguridad para JWT
define('JWT_SECRET', 'NOVALED_SUPER_SECRET_KEY_2026_@_!');

function generateToken($username, $role) {
    $header = json_encode(['alg' => 'HS256', 'typ' => 'JWT']);
    $payload = json_encode([
        'username' => $username,
        'role' => $role,
        'exp' => time() + (3600 * 24 * 30) // Expiración en 30 días
    ]);
    $base64UrlHeader = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($header));
    $base64UrlPayload = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($payload));
    $signature = hash_hmac('sha256', $base64UrlHeader . "." . $base64UrlPayload, JWT_SECRET, true);
    $base64UrlSignature = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($signature));
    return $base64UrlHeader . "." . $base64UrlPayload . "." . $base64UrlSignature;
}

function validateToken($jwt) {
    if (empty($jwt)) return null;
    $tokenParts = explode('.', $jwt);
    if (count($tokenParts) !== 3) return null;
    
    $header = base64_decode(str_replace(['-', '_'], ['+', '/'], $tokenParts[0]));
    $payload = base64_decode(str_replace(['-', '_'], ['+', '/'], $tokenParts[1]));
    $signatureProvided = $tokenParts[2];
    
    $payloadData = json_decode($payload, true);
    if (!$payloadData || !isset($payloadData['exp']) || $payloadData['exp'] < time()) {
        return null; // Expirado o payload inválido
    }
    
    // Re-calcular la firma para verificación
    $base64UrlHeader = $tokenParts[0];
    $base64UrlPayload = $tokenParts[1];
    $signature = hash_hmac('sha256', $base64UrlHeader . "." . $base64UrlPayload, JWT_SECRET, true);
    $base64UrlSignature = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($signature));
    
    if (hash_equals($base64UrlSignature, $signatureProvided)) {
        return $payloadData;
    }
    return null;
}

function getBearerToken() {
    $authHeader = null;
    if (isset($_SERVER['Authorization'])) {
        $authHeader = $_SERVER['Authorization'];
    } elseif (isset($_SERVER['HTTP_AUTHORIZATION'])) {
        $authHeader = $_SERVER['HTTP_AUTHORIZATION'];
    } elseif (isset($_SERVER['HTTP_X_AUTHORIZATION'])) {
        $authHeader = $_SERVER['HTTP_X_AUTHORIZATION'];
    } else {
        $headers = function_exists('getallheaders') ? getallheaders() : [];
        foreach ($headers as $key => $val) {
            if (strtolower($key) === 'authorization' || strtolower($key) === 'x-authorization') {
                $authHeader = $val;
                break;
            }
        }
    }
    
    // Fallback a query parameters
    if (!$authHeader && isset($_GET['token'])) {
        $authHeader = $_GET['token'];
    }
    if (!$authHeader && isset($_POST['token'])) {
        $authHeader = $_POST['token'];
    }

    if ($authHeader) {
        if (preg_match('/Bearer\s(\S+)/', $authHeader, $matches)) {
            return $matches[1];
        }
        // Si no tiene el prefijo Bearer pero parece un JWT
        if (substr_count($authHeader, '.') === 2) {
            return $authHeader;
        }
    }
    return null;
}

function requireAuth() {
    global $pdo;
    $token = getBearerToken();
    $session = validateToken($token);
    if (!$session) {
        http_response_code(401);
        echo json_encode(["error" => "No autorizado. Token inválido o expirado."]);
        exit();
    }

    // Verificación en vivo contra la base de datos MySQL
    try {
        if ($pdo && !empty($session['username'])) {
            $stmtUser = $pdo->prepare("SELECT role, deleted FROM usuarios WHERE LOWER(username) = ? LIMIT 1");
            $stmtUser->execute([strtolower($session['username'])]);
            $u = $stmtUser->fetch();
            if ($u) {
                if ((int)$u['deleted'] === 1 || (int)$u['deleted'] === 2 || $u['role'] === 'blocked') {
                    http_response_code(403);
                    echo json_encode([
                        "error" => "DELETED",
                        "message" => "Esta empresa o cuenta ha sido dada de baja. El acceso está bloqueado."
                    ]);
                    exit();
                }
                if ($u['role'] === 'suspended') {
                    http_response_code(403);
                    echo json_encode([
                        "error" => "SUSPENDED",
                        "message" => "Esta empresa ha sido suspendida por el administrador. El acceso ha sido cerrado."
                    ]);
                    exit();
                }
            }
        }
    } catch (Exception $e) {}

    return $session;
}
?>
