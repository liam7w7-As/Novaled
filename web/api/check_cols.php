<?php
try {
    require_once 'config.php';
    header('Content-Type: application/json');
     = ->query('DESCRIBE cotizaciones');
     = ->fetchAll(PDO::FETCH_ASSOC);
    echo json_encode(['success' => true, 'cols' => ]);
} catch (Exception ) {
    echo json_encode(['success' => false, 'error' => ->getMessage()]);
}
?>