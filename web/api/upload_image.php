<?php
require_once 'config.php';

// Requerir autenticación válida JWT
$session = requireAuth();

// Directorio de subida
$upload_dir = 'uploads/';

if (!file_exists($upload_dir)) {
    mkdir($upload_dir, 0755, true);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(["error" => "Método no permitido. Use POST."]);
    exit();
}

if (!isset($_FILES['image'])) {
    http_response_code(400);
    echo json_encode(["error" => "No se recibió ninguna imagen (clave 'image' requerida)."]);
    exit();
}

$file = $_FILES['image'];

if ($file['error'] !== UPLOAD_ERR_OK) {
    http_response_code(400);
    echo json_encode(["error" => "Error de subida de archivo: " . $file['error']]);
    exit();
}

// Validar tipo de archivo
$allowed_types = ['image/jpeg', 'image/png', 'image/webp'];
$file_info = getimagesize($file['tmp_name']);

if (!$file_info) {
    http_response_code(400);
    echo json_encode(["error" => "El archivo subido no es una imagen válida."]);
    exit();
}

$mime_type = $file_info['mime'];
if (!in_array($mime_type, $allowed_types)) {
    http_response_code(400);
    echo json_encode(["error" => "Tipo de imagen no permitido. Solo se aceptan JPEG, PNG y WEBP."]);
    exit();
}

// Generar nombre de archivo único
$extension = pathinfo($file['name'], PATHINFO_EXTENSION);
if (empty($extension)) {
    $extension = ($mime_type === 'image/png') ? 'png' : (($mime_type === 'image/webp') ? 'webp' : 'jpg');
}
$prefix = (strpos($file['name'], 'COMP_') === 0) ? 'COMP_' : 'ART_';
$new_filename = $prefix . time() . '_' . bin2hex(random_bytes(4)) . '.' . $extension;
$destination = $upload_dir . $new_filename;

if (move_uploaded_file($file['tmp_name'], $destination)) {
    echo json_encode([
        "success" => true,
        "filename" => $new_filename,
        "url" => "https://novaledbolivia.com/sistema/api/uploads/" . $new_filename
    ]);
} else {
    http_response_code(500);
    echo json_encode(["error" => "No se pudo guardar la imagen en el servidor."]);
}
?>
