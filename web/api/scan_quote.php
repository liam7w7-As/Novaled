<?php
require_once 'config.php';

// Requerir autenticación válida JWT
file_put_contents(__DIR__ . '/debug_upload.log', date('Y-m-d H:i:s') . " - FILES: " . print_r($_FILES, true) . "\n", FILE_APPEND);
$session = requireAuth();

// Solo los desarrolladores/dueño pueden escanear
if ($session['role'] !== 'developer') {
    http_response_code(403);
    echo json_encode(["error" => "Prohibido. Se requieren permisos de Developer/Dueño."]);
    exit();
}

// Obtener la clave de OpenAI (ChatGPT)
$openai_key = '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';
if (defined('OPENAI_API_KEY') && !empty(OPENAI_API_KEY)) {
    $openai_key = OPENAI_API_KEY;
} else {
    // Buscar en los encabezados HTTP
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    foreach ($headers as $key => $val) {
        if (strtolower($key) === 'x-openai-key') {
            if (!empty($val)) {
                $openai_key = $val;
            }
            break;
        }
    }
}

if (empty($openai_key)) {
    http_response_code(400);
    echo json_encode(["error" => "Falta la clave de API de OpenAI (X-OpenAI-Key). Configúrela en los ajustes de la aplicación."]);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(["error" => "Método no permitido. Use POST."]);
    exit();
}

// Procesar imágenes subidas y preparar contenido para OpenAI
$content = [];
$content[] = [
    "type" => "text",
    "text" => "Analiza estas imágenes de una cotización, factura o solicitud de especificaciones y extrae la información en un formato JSON estructurado. Devuelve un objeto JSON con las siguientes dos claves:\n"
            . "1. 'cliente': un objeto que contenga los datos del cliente, comprador o unidad solicitante identificados en el documento:\n"
            . "   - 'nombre': nombre de la persona, compañía o unidad solicitante (ej: 'Unidad Administrativa Financiera', 'Unidad Solicitante', cliente, etc.) (texto, o null si no se identifica)\n"
            . "   - 'telefono': teléfono de contacto (texto, o null si no hay)\n"
            . "   - 'correo': correo electrónico (texto, o null si no hay)\n"
            . "2. 'items': un arreglo de objetos para cada artículo detectado en la cotización/solicitud, donde cada objeto tenga exactamente estos campos:\n"
            . "   - 'nombre': nombre principal exacto del ítem o artículo tal como aparece escrito en la columna ÍTEM o nombre del producto (obligatorio, texto. Copia de forma exacta lo que está escrito, ej: 'CORTAPICO', 'CANDADO', 'TUBO LED'. No inventes palabras, no asumas marcas ni nombres comerciales que no estén escritos, y no inventes terminaciones como 'CORTAPICHEL')\n"
            . "   - 'codigo': código, referencia o SKU (texto, si no hay pon '')\n"
            . "   - 'unidad': unidad de medida (texto, por ejemplo: Pza, Mts, Kg, Caja, Juego, Unidad. Si no hay pon 'Unidad')\n"
            . "   - 'precio': precio unitario del artículo (número decimal, si no hay precio o no está visible pon null)\n"
            . "   - 'cantidad': cantidad de unidades del artículo (número entero, si no está visible la cantidad en el documento pon 1)\n"
            . "   - 'caracteristicas': características técnicas, detalles, especificaciones o descripción del artículo (texto consolidando la información de la columna características o detalles, si no hay pon '')\n"
            . "   - 'categoria': una sugerencia de categoría o familia lógica para clasificar este producto (ej: 'Ferretería', 'Iluminación', 'Sanitarios', 'Plomería', 'Electricidad', etc.) (texto, obligatorio)\n"
            . "   - 'subcategoria': una sugerencia de subcategoría lógica para clasificar este producto (ej: 'Candados', 'Tubos LED', 'Inodoros', 'Grifería', 'Multitomas', etc. No inventes palabras vulgares o inexistentes) (texto, obligatorio)\n\n"
            . "Devuelve únicamente el objeto JSON válido, sin bloques de código de markdown ni explicaciones."
];

$has_images = false;

// Soportar archivos con cualquier llave (ej: image0, image1, etc.)
foreach ($_FILES as $file_key => $file_info) {
    if (is_array($file_info['tmp_name'])) {
        for ($i = 0; $i < count($file_info['tmp_name']); $i++) {
            if ($file_info['error'][$i] === UPLOAD_ERR_OK) {
                $tmp_name = $file_info['tmp_name'][$i];
                $type = $file_info['type'][$i];
                $name = $file_info['name'][$i];
                
                if (function_exists('mime_content_type')) {
                    $real_type = mime_content_type($tmp_name);
                    if ($real_type) {
                        $type = $real_type;
                    }
                }
                
                $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
                $valid_exts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
                
                if (strpos($type, 'image/') === 0 || in_array($ext, $valid_exts)) {
                    if (strpos($type, 'image/') !== 0) {
                        if ($ext === 'png') {
                            $type = 'image/png';
                        } else {
                            $type = 'image/jpeg';
                        }
                    }
                    
                    $data = base64_encode(file_get_contents($tmp_name));
                    $content[] = [
                        "type" => "image_url",
                        "image_url" => [
                            "url" => "data:" . $type . ";base64," . $data
                        ]
                    ];
                    $has_images = true;
                }
            }
        }
    } else {
        if ($file_info['error'] === UPLOAD_ERR_OK) {
            $tmp_name = $file_info['tmp_name'];
            $type = $file_info['type'];
            $name = $file_info['name'];
            
            if (function_exists('mime_content_type')) {
                $real_type = mime_content_type($tmp_name);
                if ($real_type) {
                    $type = $real_type;
                }
            }
            
            $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
            $valid_exts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
            
            if (strpos($type, 'image/') === 0 || in_array($ext, $valid_exts)) {
                if (strpos($type, 'image/') !== 0) {
                    if ($ext === 'png') {
                        $type = 'image/png';
                    } else {
                        $type = 'image/jpeg';
                    }
                }
                
                $data = base64_encode(file_get_contents($tmp_name));
                $content[] = [
                    "type" => "image_url",
                    "image_url" => [
                        "url" => "data:" . $type . ";base64," . $data
                    ]
                ];
                $has_images = true;
            }
        }
    }
}

if (!$has_images) {
    http_response_code(400);
    echo json_encode(["error" => "No se recibieron imágenes válidas."]);
    exit();
}

// Realizar la llamada a OpenAI API (gpt-4o-mini)
$url = "https://api.openai.com/v1/chat/completions";
$payload = [
    "model" => "gpt-4o-mini",
    "messages" => [
        [
            "role" => "user",
            "content" => $content
        ]
    ],
    "response_format" => [
        "type" => "json_object"
    ],
    "max_tokens" => 4096
];

$ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json',
    'Authorization: Bearer ' . $openai_key
]);
curl_setopt($ch, CURLOPT_TIMEOUT, 90);

$response = curl_exec($ch);
$http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curl_error = curl_error($ch);
curl_close($ch);

if ($response === false) {
    http_response_code(500);
    echo json_encode(["error" => "Error de conexión con la API de OpenAI: " . $curl_error]);
    exit();
}

if ($http_code !== 200) {
    http_response_code($http_code);
    echo json_encode([
        "error" => "La API de OpenAI respondió con código de error " . $http_code,
        "details" => json_decode($response, true)
    ]);
    exit();
}

$res_data = json_decode($response, true);
$text = null;
try {
    if (isset($res_data['choices'][0]['message']['content'])) {
        $text = $res_data['choices'][0]['message']['content'];
        file_put_contents(__DIR__ . '/debug_upload.log', date('Y-m-d H:i:s') . " - OPENAI RESPONSE CONTENT: " . $text . "\n", FILE_APPEND);
    }
} catch (Exception $e) {
    // ignorar
}

if (empty($text)) {
    http_response_code(500);
    echo json_encode(["error" => "No se pudo extraer texto de la respuesta de OpenAI.", "raw" => $res_data]);
    exit();
}

// Limpiar y parsear el JSON recibido
$cleaned_text = trim($text);
if (preg_match('/^```(?:json)?\s*([\s\S]*?)\s*```$/i', $cleaned_text, $matches)) {
    $cleaned_text = trim($matches[1]);
}

$decoded = json_decode($cleaned_text, true);
if ($decoded === null) {
    http_response_code(500);
    echo json_encode([
        "error" => "La API de OpenAI no devolvió un JSON válido.",
        "text" => $text
    ]);
    exit();
}

$items = [];
$cliente = null;

if (is_array($decoded)) {
    if (isset($decoded['items']) && is_array($decoded['items'])) {
        $items = $decoded['items'];
    } else {
        $items = $decoded;
    }
    
    if (isset($decoded['cliente']) && is_array($decoded['cliente'])) {
        $cliente = $decoded['cliente'];
    }
}

echo json_encode([
    "success" => true,
    "items" => $items,
    "cliente" => $cliente
]);
?>
