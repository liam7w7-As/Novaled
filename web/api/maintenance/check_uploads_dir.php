<?php
require_once 'config.php';
header('Content-Type: application/json');

 = __DIR__ . '/uploads/';
 = file_exists();
 = is_writable();

if (!) {
    @mkdir(, 0777, true);
     = file_exists();
     = is_writable();
}

// List all files in uploads
 = [];
if () {
     = scandir();
}

echo json_encode([
    'upload_dir' => ,
    'exists' => ,
    'writable' => ,
    'files_count' => count(),
    'recent_files' => array_slice(array_reverse(), 0, 10)
], JSON_PRETTY_PRINT);
?>